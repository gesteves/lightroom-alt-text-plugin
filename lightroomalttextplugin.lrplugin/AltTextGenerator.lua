local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrFileUtils = import 'LrFileUtils'
local LrExportSession = import 'LrExportSession'
local LrStringUtils = import 'LrStringUtils'
local LrPathUtils = import 'LrPathUtils'

-- Load configuration, secrets, and JSON library
local configPath = LrPathUtils.child(_PLUGIN.path, 'config.lua')
local config = dofile(configPath)
local secretsPath = LrPathUtils.child(_PLUGIN.path, 'secrets.lua')
local secrets = dofile(secretsPath)
local dkjsonPath = LrPathUtils.child(_PLUGIN.path, 'dkjson.lua')
local json = dofile(dkjsonPath)

local function resizePhoto(photo)
    local tempDir = LrPathUtils.getStandardFilePath('temp')
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

    error("Failed to resize the photo")
end

local function encodePhotoToBase64(filePath)
    local file = io.open(filePath, "rb") -- r read mode and b binary mode
    local data = file:read("*all") -- *all reads the whole file
    file:close()

    local base64 = LrStringUtils.encodeBase64(data)
    return base64
end

local function requestAltTextFromOpenAI(imageBase64)
    local apiKey = secrets.OPENAI_API_KEY
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

local function generateAltTextForPhoto(photo)
    local resizedFilePath = resizePhoto(photo)
    local base64Image = encodePhotoToBase64(resizedFilePath)
    
    local response = requestAltTextFromOpenAI(base64Image)
    
    if response and response.choices and response.choices[1] and response.choices[1].message and response.choices[1].message.content then
        local altText = response.choices[1].message.content:match("^%s*(.-)%s*$") -- Trim whitespace
        LrTasks.startAsyncTask(function()
            photo.catalog:withWriteAccessDo("Set Alt Text", function()
                photo:setRawMetadata('caption', altText)
            end)
            LrDialogs.showBezel("Alt text generated and saved to caption.")
        end)
    else
        LrDialogs.message("Failed to generate alt text.")
    end

    LrFileUtils.delete(resizedFilePath) -- Clean up the resized image
end

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local selectedPhotos = catalog:getTargetPhotos()
    
    if #selectedPhotos == 0 then
        LrDialogs.message("Please select at least one photo.")
        return
    end
    
    for _, photo in ipairs(selectedPhotos) do
        generateAltTextForPhoto(photo)
    end
end)
