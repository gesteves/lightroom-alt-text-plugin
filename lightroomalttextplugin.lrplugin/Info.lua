return {
  LrSdkVersion = 6.0,
  LrSdkMinimumVersion = 6.0,
  LrPluginName = "Alt Text Generator",
  LrToolkitIdentifier = "com.example.lightroom.alttextgenerator",
  LrPluginInfoUrl = "https://github.com/gesteves/lightroom-alt-text-plugin",
  LrInitPlugin = "AltTextGenerator.lua",
  LrLibraryMenuItems = {
      {
          title = "Generate Alt Text with ChatGPT",
          file = "AltTextGenerator.lua",
      },
  },
  LrPluginInfoProvider = 'PluginInfoProvider.lua',
  VERSION = { major=1, minor=0, revision=0, build=7, },
}
