local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'
local LrBinding = import 'LrBinding'

local prefs = LrPrefs.prefsForPlugin()

if prefs.metadataField == nil then
    prefs.metadataField = "caption"
end

if prefs.skipExisting == nil then
    prefs.skipExisting = false
end

return {
    sectionsForTopOfDialog = function(f)
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
                        value = bind { key = 'claudeApiKey', object = prefs },
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
                        items = {
                            { title = "Caption", value = "caption" },
                            { title = "Headline", value = "headline" },
                            { title = "Title", value = "title" },
                        },
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
