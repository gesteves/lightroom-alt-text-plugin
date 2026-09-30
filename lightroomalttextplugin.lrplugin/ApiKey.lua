local LrPasswords = import 'LrPasswords'
local LrPrefs = import 'LrPrefs'

local KEY = 'claudeApiKey'

local ApiKey = {}

-- Returns the stored API key, or nil if there isn't one. Older versions kept the
-- key in plaintext prefs; if one is found there it's moved into encrypted
-- storage and removed from prefs.
function ApiKey.get()
    local prefs = LrPrefs.prefsForPlugin()
    local legacy = prefs.claudeApiKey
    if legacy and legacy ~= "" then
        LrPasswords.store(KEY, legacy)
        prefs.claudeApiKey = nil
        return legacy
    end

    local key = LrPasswords.retrieve(KEY)
    if key and key ~= "" then
        return key
    end
    return nil
end

function ApiKey.set(value)
    -- Store an empty string rather than nil to clear it: the SDK only documents
    -- string values for store().
    value = tostring(value or ""):match("^%s*(.-)%s*$")
    LrPasswords.store(KEY, value)
end

return ApiKey
