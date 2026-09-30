return {
  LrSdkVersion = 6.0,
  LrSdkMinimumVersion = 6.0,
  LrPluginName = "Alt Text Generator",
  LrToolkitIdentifier = "com.gesteves.lightroom.alttextgenerator",
  LrPluginInfoUrl = "https://github.com/gesteves/lightroom-alt-text-plugin",
  LrInitPlugin = "Init.lua",
  -- Library > Plug-in Extras
  LrLibraryMenuItems = {
      {
          title = "Generate Alt Text with Claude",
          file = "AltTextGenerator.lua",
          enabledWhen = "photosSelected",
      },
  },
  -- File > Plug-in Extras, available in every module
  LrExportMenuItems = {
      {
          title = "Generate Alt Text with Claude",
          file = "AltTextGenerator.lua",
          enabledWhen = "photosSelected",
      },
  },
  LrPluginInfoProvider = 'PluginInfoProvider.lua',
  VERSION = { major=2, minor=2, revision=0, build=0, },
}
