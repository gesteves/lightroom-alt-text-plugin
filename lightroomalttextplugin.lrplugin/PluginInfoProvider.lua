local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'
local LrBinding = import 'LrBinding'
local LrPathUtils = import 'LrPathUtils'

local config = dofile(LrPathUtils.child(_PLUGIN.path, 'config.lua'))
local ApiKey = dofile(LrPathUtils.child(_PLUGIN.path, 'ApiKey.lua'))
local prefs = LrPrefs.prefsForPlugin()

if prefs.metadataField == nil then
    prefs.metadataField = config.DEFAULT_METADATA_FIELD
end

if prefs.skipExisting == nil then
    prefs.skipExisting = false
end

return {
    -- The API key lives in encrypted storage (LrPasswords), not prefs, so the
    -- field binds to the dialog's property table and is saved when it closes.
    startDialog = function(propertyTable)
        propertyTable.claudeApiKey = ApiKey.get() or ""
    end,

    endDialog = function(propertyTable)
        ApiKey.set(propertyTable.claudeApiKey)
    end,

    sectionsForTopOfDialog = function(f, propertyTable)
        local bind = LrView.bind
        local share = LrView.share

        return {
            {
                title = "Alt Text Generator Settings",
                f:row {
                    f:static_text {
                        title = "Claude API Key:",
                        alignment = 'right',
                        width = share 'label_width',
                    },
                    f:password_field {
                        value = bind { key = 'claudeApiKey', object = propertyTable },
                        width_in_chars = 50,
                    },
                },
                f:row {
                    f:static_text {
                        title = "Save alt text to:",
                        alignment = 'right',
                        width = share 'label_width',
                    },
                    f:popup_menu {
                        value = bind { key = 'metadataField', object = prefs },
                        items = config.METADATA_FIELDS,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        alignment = 'right',
                        width = share 'label_width',
                    },
                    f:checkbox {
                        title = "Skip photos that already have a value in the selected field",
                        value = bind { key = 'skipExisting', object = prefs },
                    },
                },
            },
        }
    end,
}
