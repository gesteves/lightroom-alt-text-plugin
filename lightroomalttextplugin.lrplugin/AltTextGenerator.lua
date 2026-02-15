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

local configPath = LrPathUtils.child(_PLUGIN.path, 'config.lua')
local config = dofile(configPath)
local prefs = LrPrefs.prefsForPlugin()
local dkjsonPath = LrPathUtils.child(_PLUGIN.path, 'dkjson.lua')
local json = dofile(dkjsonPath)

local function sanitizeForLog(str)
    local apiKey = prefs.claudeApiKey
    if apiKey and apiKey ~= "" and str then
        return str:gsub(apiKey, "[REDACTED]")
    end
    return str or ""
end

local function resizePhoto(photo, progressScope)
    progressScope:setCaption("Resizing photo...")
    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local photoName = LrPathUtils.leafName(photo:getFormattedMetadata('fileName'))
    local resizedPhotoPath = LrPathUtils.child(tempDir, photoName)

    if LrFileUtils.exists(resizedPhotoPath) then
        LrFileUtils.delete(resizedPhotoPath)
    end

    local exportSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = tempDir,
        LR_export_useSubfolder = false,
        LR_format = 'JPEG',
        LR_jpeg_quality = 0.8,
        LR_minimizeEmbeddedMetadata = true,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = 1024,
        LR_size_maxWidth = 1024,
        LR_size_resizeType = 'wh',
        LR_size_units = 'pixels',
    }

    local exportSession = LrExportSession({
        photosToExport = {photo},
        exportSettings = exportSettings
    })

    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
        if success then
            return path
        end
    end

    return nil
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

local function requestAltTextFromClaude(imageBase64, progressScope)
    progressScope:setCaption("Requesting alt text from Claude...")

    local url = "https://api.anthropic.com/v1/messages"
    local headers = {
        { field = "Content-Type", value = "application/json" },
        { field = "x-api-key", value = prefs.claudeApiKey },
        { field = "anthropic-version", value = "2023-06-01" },
    }

    local body = {
        model = config.MODEL,
        max_tokens = 300,
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

    local bodyJson = json.encode(body)
    local response, _ = LrHttp.post(url, bodyJson, headers)

    if not response then
        return nil, "No response from Claude API"
    end

    local ok, decoded = pcall(json.decode, response)
    if not ok then
        logger:trace("Failed to parse Claude response: " .. sanitizeForLog(response))
        return nil, "Invalid response from Claude"
    end

    if decoded.error and decoded.error.message then
        logger:trace("Claude API error: " .. sanitizeForLog(json.encode(decoded, { indent = true })))
        return nil, "Claude error: " .. decoded.error.message
    end

    local content = decoded.content or {}
    for _, block in ipairs(content) do
        if block.type == "text" and block.text then
            return block.text
        end
    end

    logger:trace("Claude returned unexpected response: " .. sanitizeForLog(json.encode(decoded, { indent = true })))
    return nil, "Claude returned an unexpected response"
end

local function generateAltTextForPhoto(photo, progressScope)
    local metadataField = prefs.metadataField or "caption"

    local resizedFilePath = resizePhoto(photo, progressScope)
    if not resizedFilePath then
        return false, "Failed to resize photo"
    end

    local base64Image = encodePhotoToBase64(resizedFilePath, progressScope)
    LrFileUtils.delete(resizedFilePath)

    if not base64Image then
        return false, "Failed to encode photo"
    end

    local altText, err = requestAltTextFromClaude(base64Image, progressScope)

    if altText then
        photo.catalog:withWriteAccessDo("Set Alt Text", function()
            photo:setRawMetadata(metadataField, altText)
        end)
        return true
    end

    return false, err or "Failed to generate alt text"
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("GenerateAltText", function(context)
        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()

        if #selectedPhotos == 0 then
            LrDialogs.message("Please select at least one photo.")
            return
        end

        local apiKey = prefs.claudeApiKey
        if not apiKey or apiKey == "" then
            LrDialogs.message("Your Claude API key is missing. Please set it up in the plugin manager.")
            return
        end

        local metadataField = prefs.metadataField or "caption"
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

            local shouldSkip = false
            if skipExisting then
                local existing = photo:getFormattedMetadata(metadataField)
                if existing and existing ~= "" then
                    shouldSkip = true
                end
            end

            if shouldSkip then
                skipped = skipped + 1
            else
                local success, err = generateAltTextForPhoto(photo, progressScope)
                if success then
                    successes = successes + 1
                else
                    failures = failures + 1
                    if err then
                        errors[err] = (errors[err] or 0) + 1
                    end
                end
            end

            progressScope:setPortionComplete(i, #selectedPhotos)
        end

        progressScope:done()

        if progressScope:isCanceled() then
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
            if #errorDetails > 0 then
                summary = summary .. "\n\n" .. table.concat(errorDetails, "\n")
            end

            LrDialogs.message("Alt Text Generator", summary)
        end
    end)
end)
