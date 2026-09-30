return {
  MODEL = "claude-sonnet-5-5",
  -- Thinking tokens count against max_tokens, so leave room for them on top of
  -- the alt text itself.
  MAX_TOKENS = 4096,
  EFFORT = "low",
  ANTHROPIC_VERSION = "2023-06-01",
  ANTHROPIC_BETA = "server-side-fallback-2026-07-01",
  REQUEST_TIMEOUT = 120,
  MAX_RETRIES = 3,
  MAX_ALT_TEXT_LENGTH = 1000,
  MAX_IMAGE_DIMENSION = 1568,
  DEFAULT_METADATA_FIELD = "caption",
  METADATA_FIELDS = {
    { title = "Caption", value = "caption" },
    { title = "Headline", value = "headline" },
    { title = "Title", value = "title" },
  },
  INSTRUCTIONS = [[
You are an expert at writing alt text for images for accessibility purposes. Your job is to receive an image and write a short alt text that describes its contents objectively.

<instructions>
  - Keep the description factual and objective. Omit subjective details such as the mood of the image.
  - Use present participles (verbs ending in -ing) without auxiliary verbs rather than present tense verbs when describing actions (for example, "a dog running on the beach," not "a dog runs on the beach" or "a dog is running on the beach").
  - Do not specify if the image is in color or black and white.
  - Follow Chicago Manual of Style 18 conventions.
  - The alt text must be less than 1,000 characters.
  - Output ONLY the alt text itself with no preamble, explanation, or additional text. The user should be able to copy and paste your entire response directly as the alt text.
</instructions>
  ]]
}
