local LrPrefs = import 'LrPrefs'

-- The re-entrancy flag in AltTextGenerator.lua is normally cleared by a cleanup
-- handler, but that never runs if Lightroom crashes or is force-quit mid-run.
-- Nothing can be running when the plugin loads, so reset it here.
LrPrefs.prefsForPlugin().isRunning = false
