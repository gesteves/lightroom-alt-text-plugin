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

-- Load configuration and JSON library
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

    local base64 = LrStringUtils.encodeBase64(data)
    return base64
end


local function requestAltTextFromOpenAI(imageBase64, progressScope)
    progressScope:setCaption("Requesting alt text from OpenAI...")
    local apiKey = prefs.openaiApiKey
    if not apiKey then
        LrDialogs.message("Your OpenAI API key is missing. Please set it up in the plugin manager.")
        return nil
    end

    local url = "https://api.openai.com/v1/chat/completions"
    local headers = {
        { field = "Content-Type", value = "application/json" },
        { field = "Authorization", value = "Bearer " .. apiKey },
    }
    local body = {
        model = "gpt-4o",
        messages = {
            {
                role = "system",
                content = config.SYSTEM_PROMPT
            },
            {
                role = "user",
                content = {
                    {
                        type = "image_url",
                        image_url = {
                            url = "data:image/jpeg;base64," .. imageBase64
                        }
                    }
                }
            }
        }
    }
    local bodyJson = json.encode(body)
    local response, hdrs = LrHttp.post(url, bodyJson, headers)
    if response then
        return json.decode(response)
    end
    return nil
end

local function generateAltTextForPhoto(photo, progressScope)
    resizedFilePath = resizePhoto(photo, progressScope)

    if not resizedFilePath then
        return false
    end

    local base64Image = encodePhotoToBase64(resizedFilePath, progressScope)

    if not base64Image then
        return false
    end

    LrFileUtils.delete(resizedFilePath)
    
    local response = requestAltTextFromOpenAI(base64Image, progressScope)
    
    if response and response.choices and response.choices[1] and response.choices[1].message and response.choices[1].message.content then
        local altTextJson = response.choices[1].message.content:match("^%s*(.-)%s*$") -- Trim whitespace
        local altTextData = json.decode(altTextJson)
        if altTextData and altTextData.altText then
            local altText = altTextData.altText
            photo.catalog:withWriteAccessDo("Set Alt Text", function()
                photo:setRawMetadata('caption', altText)
            end)
            LrDialogs.showBezel("Alt text generated and saved to caption.")
            return true
        else
            LrDialogs.message("Failed to get alt text from OpenAI response.")
            return false
        end
    else
        LrDialogs.message("Something went wrong, please try again!")
        return false
    end
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

        local totalPhotos = #selectedPhotos
        for i, photo in ipairs(selectedPhotos) do
            progressScope:setPortionComplete(i - 1, totalPhotos)
            if not generateAltTextForPhoto(photo, progressScope) then
                break
            end
            progressScope:setPortionComplete(i, totalPhotos)
        end

        progressScope:done()
    end)
end)
