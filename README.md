This is a plugin for Lightroom Classic that generates alt text for photos using Claude and saves it to the caption field in the photo's metadata.

To use it:

1. Clone this repo
2. Get a Claude API key at https://console.anthropic.com/settings/keys
3. Open Lightroom Classic, go to File > Plug-in Manager > Add, and select the `lightroomalttextplugin.lrplugin` folder in this repo
4. Paste the Claude API key in the settings section, and click "done"
5. Select an image, go to Library > Plug-in Extras > Generate Alt Text with Claude
6. Wait a few seconds, a message will let you know when the alt text has been generated
7. Inspect the alt text in the photo's metadata, and edit as needed
