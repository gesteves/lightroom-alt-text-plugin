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
        return nil
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
        LR_size_maxHeight = 2000,
        LR_size_maxWidth = 2000,
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

local function requestAltTextFromOpenAI(imageBase64, progressScope)
    progressScope:setCaption("Requesting alt text from OpenAI...")
    local apiKey = prefs.openaiApiKey
    if not apiKey then
        LrDialogs.message("Your OpenAI API key is missing. Please set it up in the plugin manager.")
        return nil
    end

    local url = "https://api.openai.com/v1/responses"
    local headers = {
        { field = "Content-Type", value = "application/json" },
        { field = "Authorization", value = "Bearer " .. apiKey },
    }

    local body = {
        model = "gpt-4.1",
        store = false,
        instructions = config.INSTRUCTIONS,
        user = "lightroom-plugin",
        input = {
            {
                role = "user",
                content = {
                    {
                        type = "input_image",
                        image_url = "data:image/jpeg;base64," .. imageBase64
                    }
                }
            }
        },
        text = {
            format = {
                type = "json_schema",
                name = "alt_text",
                schema = {
                    type = "object",
                    properties = {
                        altText = { type = "string" }
                    },
                    required = { "altText" },
                    additionalProperties = false
                }
            }
        }
    }

    local bodyJson = json.encode(body)
    local response, _ = LrHttp.post(url, bodyJson, headers)

    if not response then
        LrDialogs.message("No response from OpenAI. Please try again.")
        return nil
    end

    local ok, decoded = pcall(json.decode, response)
    if not ok then
        logger:trace("Failed to parse OpenAI response: " .. tostring(response))
        LrDialogs.message("Invalid response from OpenAI.")
        return nil
    end

    -- Check for API error
    if decoded.error and decoded.error.message then
        logger:trace("OpenAI API error:\n" .. json.encode(decoded, { indent = true }))
        LrDialogs.message("OpenAI error: " .. decoded.error.message)
        return nil
    end

    -- Normal success path
    local outputs = decoded.output or {}
    for _, output in ipairs(outputs) do
        if output.role == "assistant" and output.content and output.content[1] and output.content[1].text then
            return json.decode(output.content[1].text)
        end
    end

    LrDialogs.message("OpenAI returned an unexpected response.")
    return nil
end

local function generateAltTextForPhoto(photo, progressScope)
    local resizedFilePath = resizePhoto(photo, progressScope)
    if not resizedFilePath then
        return false
    end

    local base64Image = encodePhotoToBase64(resizedFilePath, progressScope)
    if not base64Image then
        return false
    end

    LrFileUtils.delete(resizedFilePath)

    local response = requestAltTextFromOpenAI(base64Image, progressScope)

    if response and response.altText then
        local altText = response.altText
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
