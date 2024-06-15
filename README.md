This is a hacky plugin for Lightroom Classic that generates alt text for photos using ChatGPT-4o and saves it to the caption field in the photo's exif data.

To use it:

1. Clone this repo
2. Get an OpenAI API key at https://platform.openai.com/api-keys (make sure it has access to the `gpt-4o` model)
3. Paste the API key in the `secrets.lua.example` file in the repo, and rename it `secrets.lua`
4. Open Lightroom Classic, go to File > Plug-in Manager > Add, and select the `lightroomalttextplugin.lrdevplugin` folder in this repo
5. Select an image, go to Library > Plug-in Extras > Generate Alt Text with ChatGPT
6. Wait a few seconds, a message will let you know when the alt text has been generated
7. Inspect the caption in the photo's metadata, and adjust as needed
