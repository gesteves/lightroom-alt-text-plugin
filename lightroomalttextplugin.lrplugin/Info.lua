return {
  LrSdkVersion = 6.0,
  LrSdkMinimumVersion = 6.0,
  LrPluginName = "Alt Text Generator",
  LrToolkitIdentifier = "com.gesteves.lightroom.alttextgenerator",
  LrPluginInfoUrl = "https://github.com/gesteves/lightroom-alt-text-plugin",
  LrLibraryMenuItems = {
      {
          title = "Generate Alt Text with Claude",
          file = "AltTextGenerator.lua",
      },
  },
  LrPluginInfoProvider = 'PluginInfoProvider.lua',
  VERSION = { major=2, minor=1, revision=0, build=0, },
}
