local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrFileUtils = import 'LrFileUtils'
local LrExportSession = import 'LrExportSession'
local LrStringUtils = import 'LrStringUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrLogger = import 'LrLogger'

local logger = LrLogger('AltTextPlugin')
logger:enable("logfile")

local prefs = LrPrefs.prefsForPlugin()

local function loadModule(fileName)
    local ok, result = pcall(dofile, LrPathUtils.child(_PLUGIN.path, fileName))
    if not ok then
        LrDialogs.message(
            "Alt Text Generator failed to load.",
            "Could not load " .. fileName .. ": " .. tostring(result),
            "critical"
        )
        error("Failed to load " .. fileName)
    end
    return result
end

local config = loadModule('config.lua')
local json = loadModule('dkjson.lua')
local ApiKey = loadModule('ApiKey.lua')

local API_URL = "https://api.anthropic.com/v1/messages"

-- Statuses worth retrying: timeouts, rate limits, server errors, and overload.
local RETRYABLE_STATUS = {
    [408] = true, [429] = true, [500] = true, [502] = true,
    [503] = true, [504] = true, [529] = true,
}

-- Set once per run; used to authenticate requests and to scrub logs.
local apiKey

local function validateMetadataField(field)
    for _, item in ipairs(config.METADATA_FIELDS) do
        if item.value == field then
            return field
        end
    end
    return config.DEFAULT_METADATA_FIELD
end

-- Replaces every occurrence of the API key with a placeholder. Uses a plain-text
-- search because API keys contain "-", which is a Lua pattern quantifier.
local function sanitizeForLog(str)
    str = str or ""
    if not apiKey or apiKey == "" then
        return str
    end
    local parts = {}
    local pos = 1
    while true do
        local first, last = string.find(str, apiKey, pos, true)
        if not first then
            break
        end
        table.insert(parts, str:sub(pos, first - 1))
        table.insert(parts, "[REDACTED]")
        pos = last + 1
    end
    table.insert(parts, str:sub(pos))
    return table.concat(parts)
end

local function getHeader(hdrs, name)
    if not hdrs then
        return nil
    end
    name = name:lower()
    for _, header in ipairs(hdrs) do
        if type(header) == "table" and header.field and header.field:lower() == name then
            return header.value
        end
    end
    return nil
end

local function isBlank(str)
    return str == nil or LrStringUtils.trimWhitespace(str) == ""
end

-- Returns the rendered JPEG path and the temp folder holding it, or nil and an
-- error message. The caller is responsible for deleting the temp folder.
local function resizePhoto(photo, progressScope)
    progressScope:setCaption("Resizing photo...")

    -- Export into a per-photo temp subfolder keyed on the photo's unique local
    -- identifier, so two selected photos that share a filename can never collide
    -- and stale files from earlier runs can't make Lightroom append a "-2" suffix.
    local tempDir = LrPathUtils.child(
        LrPathUtils.getStandardFilePath('temp'),
        'alttext-' .. tostring(photo.localIdentifier)
    )
    if LrFileUtils.exists(tempDir) then
        LrFileUtils.delete(tempDir)
    end
    LrFileUtils.createAllDirectories(tempDir)

    local exportSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = tempDir,
        LR_export_useSubfolder = false,
        LR_format = 'JPEG',
        LR_jpeg_quality = 0.8,
        LR_minimizeEmbeddedMetadata = true,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = config.MAX_IMAGE_DIMENSION,
        LR_size_maxWidth = config.MAX_IMAGE_DIMENSION,
        LR_size_resizeType = 'wh',
        LR_size_units = 'pixels',
    }

    local exportSession = LrExportSession({
        photosToExport = {photo},
        exportSettings = exportSettings
    })

    local renderError
    for _, rendition in exportSession:renditions() do
        -- On failure the second value is a message suitable for display, such as
        -- the original file being missing.
        local success, pathOrMessage = rendition:waitForRender()
        if success then
            return pathOrMessage, tempDir
        end
        renderError = pathOrMessage
    end

    LrFileUtils.delete(tempDir)
    return nil, renderError or "Failed to resize photo"
end

local function encodePhotoToBase64(filePath, progressScope)
    progressScope:setCaption("Encoding photo...")

    local file = io.open(filePath, "rb")
    if not file then
        return nil
    end

    local data = file:read("*all")
    file:close()

    return LrStringUtils.encodeBase64(data)
end

-- Posts to the Messages API, retrying transient failures with exponential
-- backoff (or the server's retry-after hint). Returns LrHttp.post's results.
local function postWithRetries(bodyJson, headers, progressScope)
    local attempt = 0
    while true do
        local response, hdrs = LrHttp.post(API_URL, bodyJson, headers, "POST", config.REQUEST_TIMEOUT)
        local status = hdrs and hdrs.status
        local retryable = (response == nil) or (status ~= nil and RETRYABLE_STATUS[status] == true)

        if not retryable or attempt >= config.MAX_RETRIES or progressScope:isCanceled() then
            return response, hdrs
        end

        attempt = attempt + 1
        local delay = tonumber(getHeader(hdrs, "retry-after")) or 2 ^ attempt
        delay = math.max(1, math.min(delay, 60))
        logger:trace(string.format(
            "Claude API request failed (status %s); retry %d of %d in %d seconds",
            tostring(status), attempt, config.MAX_RETRIES, delay
        ))
        progressScope:setCaption(string.format("Claude is busy, retrying in %d seconds...", delay))
        LrTasks.sleep(delay)
    end
end

local function requestAltTextFromClaude(imageBase64, progressScope)
    progressScope:setCaption("Requesting alt text from Claude...")

    local headers = {
        { field = "Content-Type", value = "application/json" },
        { field = "x-api-key", value = apiKey },
        { field = "anthropic-version", value = config.ANTHROPIC_VERSION },
        { field = "anthropic-beta", value = config.ANTHROPIC_BETA },
    }

    local body = {
        model = config.MODEL,
        max_tokens = config.MAX_TOKENS,
        output_config = { effort = config.EFFORT },
        -- Retry declined requests on a fallback model chosen by the server.
        fallbacks = "default",
        system = config.INSTRUCTIONS,
        messages = {
            {
                role = "user",
                content = {
                    {
                        type = "image",
                        source = {
                            type = "base64",
                            media_type = "image/jpeg",
                            data = imageBase64
                        }
                    },
                    {
                        type = "text",
                        text = "Please generate alt text for this image."
                    }
                }
            }
        }
    }

    local response, hdrs = postWithRetries(json.encode(body), headers, progressScope)

    if not response then
        -- On a transport-level failure LrHttp.post returns nil plus an info table
        -- whose "error" entry describes what went wrong (timeout, bad host, etc.).
        local detail = "no response"
        if hdrs and hdrs.error then
            detail = hdrs.error.name or hdrs.error.errorCode or detail
        end
        logger:trace("Claude API request failed: " .. tostring(detail))
        return nil, "Could not reach the Claude API: " .. tostring(detail)
    end

    local status = hdrs and hdrs.status
    local ok, decoded = pcall(json.decode, response)
    if not ok or type(decoded) ~= "table" then
        logger:trace("Failed to parse Claude response (status " .. tostring(status) .. "): " .. sanitizeForLog(response))
        return nil, "Invalid response from Claude"
    end

    if status == 401 then
        return nil, "Invalid Claude API key. Please check it in the plugin settings."
    end

    if decoded.type == "error" or (status and status ~= 200) then
        logger:trace("Claude API error: " .. sanitizeForLog(json.encode(decoded, { indent = true })))
        local message = decoded.error and decoded.error.message or ("HTTP status " .. tostring(status))
        return nil, "Claude error: " .. message
    end

    if decoded.stop_reason == "refusal" then
        local category = decoded.stop_details and decoded.stop_details.category
        logger:trace("Claude declined the request: " .. tostring(category))
        if type(category) == "string" then
            return nil, "Claude declined to describe this photo (" .. category .. ")"
        end
        return nil, "Claude declined to describe this photo"
    end

    if decoded.stop_reason == "max_tokens" then
        -- The reply was cut off; saving it would store truncated alt text.
        return nil, "Claude's response was cut off before it finished"
    end

    -- Read blocks by type: the response can begin with (empty) thinking blocks.
    local texts = {}
    for _, block in ipairs(decoded.content or {}) do
        if block.type == "text" and type(block.text) == "string" then
            table.insert(texts, block.text)
        end
    end
    local altText = LrStringUtils.trimWhitespace(table.concat(texts))

    if altText == "" then
        logger:trace("Claude returned unexpected response: " .. sanitizeForLog(json.encode(decoded, { indent = true })))
        return nil, "Claude returned an unexpected response"
    end

    -- Count UTF-8 characters (not bytes) by skipping continuation bytes.
    local length = select(2, altText:gsub("[^\128-\191]", ""))
    if length > config.MAX_ALT_TEXT_LENGTH then
        logger:trace("Alt text too long (" .. length .. " characters): " .. altText)
        return nil, "Claude's alt text was longer than " .. config.MAX_ALT_TEXT_LENGTH .. " characters"
    end

    return altText
end

local function generateAltTextForPhoto(photo, metadataField, progressScope)
    local resizedFilePath, tempDirOrError = resizePhoto(photo, progressScope)
    if not resizedFilePath then
        return false, tempDirOrError
    end

    local base64Image = encodePhotoToBase64(resizedFilePath, progressScope)
    LrFileUtils.delete(tempDirOrError)

    if not base64Image then
        return false, "Failed to encode photo"
    end

    local altText, err = requestAltTextFromClaude(base64Image, progressScope)
    if not altText then
        return false, err or "Failed to generate alt text"
    end

    -- setRawMetadata is synchronous, so a plain pcall is fine here and gives a
    -- specific message if the field can't be written.
    local wrote = false
    local result = photo.catalog:withWriteAccessDo("Set Alt Text", function()
        wrote = pcall(function()
            photo:setRawMetadata(metadataField, altText)
        end)
    end, { timeout = 30 })

    if result == "aborted" then
        return false, "Timed out waiting to write to the catalog"
    end
    if not wrote then
        return false, "Failed to save alt text"
    end
    return true
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("GenerateAltText", function(context)
        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()

        if #selectedPhotos == 0 then
            LrDialogs.message("Please select at least one photo.")
            return
        end

        apiKey = ApiKey.get()
        if not apiKey then
            LrDialogs.message("Your Claude API key is missing. Please set it up in the plugin manager.")
            return
        end

        -- Re-entrancy guard: prevent a second run from starting while one is in
        -- progress. The flag lives in prefs (each menu click re-runs this file
        -- fresh, so a local variable wouldn't persist) and is cleared by a cleanup
        -- handler so it resets even if the task errors or is canceled. Init.lua
        -- also clears it at startup in case Lightroom quit mid-run.
        if prefs.isRunning then
            LrDialogs.message("Alt text generation is already running.")
            return
        end
        prefs.isRunning = true
        context:addCleanupHandler(function()
            prefs.isRunning = false
        end)

        local metadataField = validateMetadataField(prefs.metadataField)
        local skipExisting = prefs.skipExisting or false

        local progressScope = LrProgressScope({
            title = "Generating Alt Text",
            functionContext = context,
        })

        local successes = 0
        local failures = 0
        local skipped = 0
        local errors = {}

        for i, photo in ipairs(selectedPhotos) do
            if progressScope:isCanceled() then
                break
            end

            progressScope:setPortionComplete(i - 1, #selectedPhotos)

            local shouldSkip = photo:getRawMetadata('isVideo')
            if not shouldSkip and skipExisting then
                shouldSkip = not isBlank(photo:getFormattedMetadata(metadataField))
            end

            if shouldSkip then
                skipped = skipped + 1
            else
                local photoName = photo:getFormattedMetadata('fileName')
                -- LrTasks.pcall (unlike Lua's pcall) can wrap yielding SDK calls,
                -- so an unexpected error fails this photo instead of the batch.
                local ok, success, err = LrTasks.pcall(generateAltTextForPhoto, photo, metadataField, progressScope)
                if not ok then
                    err = "Unexpected error: " .. tostring(success)
                    success = false
                end
                if success then
                    successes = successes + 1
                else
                    failures = failures + 1
                    err = err or "Failed to generate alt text"
                    logger:trace("Alt text failed for " .. tostring(photoName) .. ": " .. sanitizeForLog(tostring(err)))
                    errors[err] = (errors[err] or 0) + 1
                end
            end

            progressScope:setPortionComplete(i, #selectedPhotos)
        end

        local canceled = progressScope:isCanceled()
        progressScope:done()

        if canceled then
            local parts = {"Operation canceled."}
            if successes > 0 then
                table.insert(parts, successes .. " photo(s) completed before cancellation.")
            end
            LrDialogs.message(table.concat(parts, " "))
        elseif failures == 0 and skipped == 0 then
            LrDialogs.showBezel("Alt text generated for " .. successes .. " photo(s).")
        else
            local parts = {}
            if successes > 0 then
                table.insert(parts, successes .. " succeeded")
            end
            if failures > 0 then
                table.insert(parts, failures .. " failed")
            end
            if skipped > 0 then
                table.insert(parts, skipped .. " skipped")
            end
            local summary = table.concat(parts, ", ") .. "."

            local errorDetails = {}
            for err, count in pairs(errors) do
                if count > 1 then
                    table.insert(errorDetails, err .. " (" .. count .. "x)")
                else
                    table.insert(errorDetails, err)
                end
            end
            table.sort(errorDetails)
            if #errorDetails > 0 then
                summary = summary .. "\n\n" .. table.concat(errorDetails, "\n")
            end

            LrDialogs.message("Alt Text Generator", summary)
        end
    end)
end)
