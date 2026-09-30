This is a plugin for Lightroom Classic that generates alt text for photos using Claude (Claude Sonnet 5.5) and saves it to a metadata field of your choice (Caption by default).

To use it:

1. Clone this repo
2. Get a Claude API key at https://console.anthropic.com/settings/keys
3. Open Lightroom Classic, go to File > Plug-in Manager > Add, and select the `lightroomalttextplugin.lrplugin` folder in this repo
4. In the plugin's settings section:
   - Paste your Claude API key (it's kept in Lightroom's encrypted password storage)
   - Choose which field to save the alt text to: Caption, Headline, or Title
   - Optionally, skip photos that already have a value in that field
5. Click "Done"
6. Select one or more photos, then go to Library > Plug-in Extras > Generate Alt Text with Claude (or File > Plug-in Extras > Generate Alt Text with Claude from any module)
7. Wait a few seconds; a message will let you know when the alt text has been generated. Videos are skipped.
8. Inspect the alt text in the photo's metadata, and edit as needed

If something goes wrong, the plugin writes details to `AltTextPlugin.log` in Lightroom's log folder (`~/Documents/LrClassicLogs` on macOS).
