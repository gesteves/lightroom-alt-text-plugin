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
    local apiKey = prefs.claudeApiKey
    if not apiKey or apiKey == "" then
        LrDialogs.message("Your Claude API key is missing. Please set it up in the plugin manager.")
        return nil
    end

    local url = "https://api.anthropic.com/v1/messages"
    local headers = {
        { field = "Content-Type", value = "application/json" },
        { field = "x-api-key", value = apiKey },
        { field = "anthropic-version", value = "2023-06-01" },
    }

    local body = {
        model = "claude-sonnet-4-5",
        max_tokens = 1024,
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
        LrDialogs.message("No response from Claude. Please try again.")
        return nil
    end

    local ok, decoded = pcall(json.decode, response)
    if not ok then
        logger:trace("Failed to parse Claude response: " .. tostring(response))
        LrDialogs.message("Invalid response from Claude.")
        return nil
    end

    -- Check for API error
    if decoded.error and decoded.error.message then
        logger:trace("Claude API error:\n" .. json.encode(decoded, { indent = true }))
        LrDialogs.message("Claude error: " .. decoded.error.message)
        return nil
    end

    -- Normal success path - Claude returns content array with text blocks
    local content = decoded.content or {}
    for _, block in ipairs(content) do
        if block.type == "text" and block.text then
            return block.text
        end
    end

    LrDialogs.message("Claude returned an unexpected response.")
    return nil
end

local function generateAltTextForPhoto(photo, progressScope)
    local resizedFilePath = resizePhoto(photo, progressScope)
    if not resizedFilePath then
        return false
    end

    local base64Image = encodePhotoToBase64(resizedFilePath, progressScope)
    LrFileUtils.delete(resizedFilePath)

    if not base64Image then
        return false
    end

    local altText = requestAltTextFromClaude(base64Image, progressScope)

    if altText then
        photo.catalog:withWriteAccessDo("Set Alt Text", function()
            photo:setRawMetadata('caption', altText)
        end)
        LrDialogs.showBezel("Alt text generated and saved to caption.")
        return true
    end

    return false
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("GenerateAltText", function(context)
        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()

        if #selectedPhotos == 0 then
            LrDialogs.message("Please select at least one photo.")
            return
        end

        local progressScope = LrProgressScope({
            title = "Generating Alt Text",
            functionContext = context,
        })

        for i, photo in ipairs(selectedPhotos) do
            progressScope:setPortionComplete(i - 1, #selectedPhotos)
            if not generateAltTextForPhoto(photo, progressScope) then
                break
            end
            progressScope:setPortionComplete(i, #selectedPhotos)
        end

        progressScope:done()
    end)
end)
