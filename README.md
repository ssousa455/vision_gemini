# opencode-vision-gemini

> Vision capability for text-only LLMs in [OpenCode](https://opencode.ai) — routes image analysis through Google Gemini Vision.

Paste or drop an image into an OpenCode chat session. The plugin auto-saves it to disk, injects the file path into your message, and reminds the model that vision tools are available. The model then calls one of four tools (`vision_describe`, `vision_ocr`, `vision_analyze`, `vision_recent_images`) and answers based on Gemini's text description of the image.

Works with **any** model — even free text-only ones like DeepSeek, Llama, or Qwen hosted on OpenCode's free providers.

---

## Why this plugin exists

I tried using [`opencode-vision`](https://github.com/NickRivers1983/opencode-vision) (the most starred vision MCP for OpenCode at the time) and it failed for two reasons:

1. **It is an MCP server, not a plugin.** It needs a Python runtime with PaddleOCR and a dozen heavy ML dependencies installed. Setup is brittle on Windows.
2. **It does not auto-handle pasted images.** You have to manually save the image to a path and tell the model where it is, every time. The model still thinks it is text-only and often says *"I cannot see images"* even when you give it a file path.

So I built `opencode-vision-gemini` to fix both problems:

- **It is a Node.js plugin** — runs in-process inside OpenCode, zero external runtime, no MCP transport issues.
- **It auto-saves pasted/dropped images** to a known directory and **injects the file path** into the message with a system-level reminder.
- **It uses Google Gemini 2.5 Flash** for the heavy lifting — generous free tier (1,500 requests/day), no credit card, returns text that any model can reason about.
- **It works for every model** because vision is a *tool result*, not a *model feature*.

### When to use this vs `opencode-vision`

| Feature                          | `opencode-vision-gemini` (this) | `opencode-vision` (MCP)             |
| -------------------------------- | ------------------------------- | ----------------------------------- |
| Works on Windows (no setup)      | ✅                              | ❌ (Python + PaddleOCR install)     |
| Auto-saves pasted images         | ✅                              | ❌                                  |
| Works with any text-only model   | ✅                              | ⚠️ (model still says "I can't see") |
| Offline OCR                      | ❌ (needs internet for Gemini)  | ✅ (PaddleOCR runs locally)         |
| Free tier                        | ✅ (1,500 req/day, Gemini)      | ✅ (free)                           |
| Setup time                       | ~2 minutes                      | ~30 minutes                         |
| Quality of OCR                   | High (Gemini 2.5 Flash)         | High                                |

**Bottom line:** use this plugin unless you specifically need offline OCR.

---

## Who can use it

Anyone running **OpenCode** (the AI coding CLI by `sst`) on:

- Windows (PowerShell 7+ or WSL)
- macOS
- Linux

You also need:

- A **Google AI Studio API key** (free, takes 1 minute to create — see below)
- An **internet connection** (the plugin calls Gemini's REST API directly)

You do **not** need:

- A Python runtime
- An Ollama server
- A paid model or paid API key
- A multimodal model — any text-only model works

---

## Requirements

| Tool      | Version    | Why                                      |
| --------- | ---------- | ---------------------------------------- |
| OpenCode  | ≥ 1.0      | Plugin API (`@opencode-ai/plugin`)      |
| Node.js   | ≥ 20       | Plugin runtime                          |
| Gemini key | any tier  | `GOOGLE_API_KEY` env var                 |

---

## Installation

### Step 1 — Get a Gemini API key (free)

1. Go to [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey).
2. Sign in with your Google account.
3. Click **Create API key** → **Create API key in new project**.
4. Copy the key (starts with `AIza...`).

The free tier gives you **1,500 Gemini 2.5 Flash requests per day** — more than enough for personal use.

### Step 2 — Clone this repo and install the plugin

Pick **one** of the three installation paths below.

#### Option A — One-liner install (recommended)

**Windows (PowerShell 7+):**

```powershell
iwr -useb https://raw.githubusercontent.com/ssousa455/vison_gemini/main/scripts/install.ps1 | iex
```

**macOS / Linux (bash):**

```bash
curl -fsSL https://raw.githubusercontent.com/ssousa455/vison_gemini/main/scripts/install.sh | bash
```

The script will:

1. Ask for (or auto-detect) your `GOOGLE_API_KEY`.
2. Clone this repo into `~/.config/opencode/plugins/vision-gemini/`.
3. Add the plugin to `~/.config/opencode/opencode.jsonc`.
4. Save the key to `~/.config/opencode/.env` with `chmod 600`.
5. Run the smoke test.

#### Option B — Manual install (3 commands)

```bash
git clone https://github.com/ssousa455/vison_gemini.git \
  ~/.config/opencode/plugins/vision-gemini

# Add to ~/.config/opencode/opencode.jsonc → "plugin": [...]
#   "file://C:/Users/.../plugins/vision-gemini"   (Windows)
#   "file:///home/.../plugins/vision-gemini"       (Unix)

# Add to ~/.config/opencode/.env
echo 'GOOGLE_API_KEY=AIza_your_key_here' >> ~/.config/opencode/.env
```

See [`examples/opencode.jsonc.snippet`](examples/opencode.jsonc.snippet) and [`examples/.env.snippet`](examples/.env.snippet) for the exact lines to add.

### Step 3 — Verify

```bash
cd ~/.config/opencode/plugins/vision-gemini
npm test
```

Expected output:

```
OK: 4 tools + chat.message hook registered
  - vision_describe: function
  - vision_ocr: function
  - vision_analyze: function
  - vision_recent_images: function
  - chat.message: function
```

Then in any OpenCode session:

```bash
opencode run "describe this image" -f ./photo.jpg
```

You should see the model call `vision_analyze` and return a description.

---

## Using the plugin in a session

### The 4 tools

| Tool                   | What it does                                                     |
| ---------------------- | ---------------------------------------------------------------- |
| `vision_describe`      | Detailed visual description. Optional `prompt` for questions.    |
| `vision_ocr`           | Extracts text from the image exactly as it appears.              |
| `vision_analyze`       | All-in-one: context + description + OCR.                         |
| `vision_recent_images` | Lists images auto-saved by the plugin in the last few minutes.  |

### How to use

1. **Paste an image** (`Ctrl+V` in the chat) **or drop a file** (drag from Explorer/Finder).
2. The plugin auto-saves it to:
   - **Windows:** `%LOCALAPPDATA%\opencode\images\`
   - **macOS / Linux:** `~/.local/share/opencode/images/`
   - Override with the `OPENCODE_VISION_DIR` env var.
3. The model is told the file path and that it has vision tools available.
4. The model calls `vision_analyze` (or whichever tool is appropriate), Gemini returns a text description, and the model answers your question.

You can also ask the model about images that are **already on disk** (e.g. from a previous paste, or a screenshot you took yourself):

```
User: run vision_ocr on ~/Downloads/contract.png
User: use vision_recent_images to find my last 3 screenshots
User: describe C:\Users\Sergi\Desktop\diagram.png
```

### Example interaction

```
> [user pastes screenshot of an error dialog]

⚙ vision_analyze {"image_path":".../2026-06-02T05-21-12_screenshot_a1b2c3d4e5.png"}

The image shows a Windows error dialog titled "Visual Studio Code has stopped
responding" with the message "A problem caused the program to stop working
correctly. Windows will close the program and notify you if a solution is
available." Two buttons are visible: "Close program" and "Wait for the program
to respond." This is a common crash dialog; the most likely causes are...
```

---

## Configuration

All configuration is environment-based. Add to `~/.config/opencode/.env`:

```bash
# Required: your Gemini API key
GOOGLE_API_KEY=AIza_your_key_here

# Optional: change where images are auto-saved
OPENCODE_VISION_DIR=/custom/path/to/images
```

### Which Gemini model?

The plugin currently uses **`gemini-2.5-flash`** — the best free-tier balance of speed, quality, and rate limits. To change the model, edit `index.js` line ~147:

```js
const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${key}`;
```

Replace `gemini-2.5-flash` with any model from [the Gemini API docs](https://ai.google.dev/models/gemini) (e.g. `gemini-2.5-pro` for higher quality, slower responses).

---

## Troubleshooting

### Model still says "I can't see images"

The plugin handles this through **three layers**:

1. **Per-message hint** (`chat.message` hook): when an image is detected, an explicit `[SYSTEM: ...]` block is injected telling the model to call the tool and where the file is.
2. **Persistent system prompt** (`experimental.chat.system.transform` hook): every model gets a `VISION CAPABILITY` reminder appended to the system prompt.
3. **Config-level instructions** (`opencode.jsonc` → `instructions` array): a static reminder is added globally.

If the model still refuses, check `~/.config/opencode/opencode.jsonc` — make sure the vision-gemini plugin is in the `plugin` array with a valid `file://` URL.

### `GOOGLE_API_KEY not set`

Make sure the key is in `~/.config/opencode/.env` (not just `~/.bashrc`). The plugin reads it via `process.env` first, then falls back to reading the `.env` file directly.

### Gemini 503 "temporarily unavailable"

Free-tier Gemini sometimes returns 503 under high load. Wait a few seconds and retry. If it persists, switch to a paid tier or a different model.

### `File not found` from `vision_*` tools

The path must be **absolute**. Use `vision_recent_images` to discover where the plugin saved the most recent image, or use `realpath` / `Resolve-Path` to get an absolute path.

### `npm test` fails

Make sure you're running Node 20+ and that `~/.config/opencode/node_modules/@opencode-ai/plugin` exists. OpenCode installs it automatically — running `opencode --version` once should create it.

---

## Development

```bash
git clone https://github.com/ssousa455/vison_gemini.git
cd vison_gemini
npm test
```

To test against a real image:

```bash
node examples/make-test-image.js
node examples/manual-test.js ./test-output.png
```

To uninstall:

```bash
rm -rf ~/.config/opencode/plugins/vision-gemini
# Then remove the entry from opencode.jsonc → "plugin": [...]
```

---

## License

MIT — see [`LICENSE`](LICENSE).

## Credits

- Inspired by [`opencode-vision`](https://github.com/NickRivers1983/opencode-vision) (which I couldn't get to work on Windows).
- Powered by [Google Gemini 2.5 Flash](https://ai.google.dev/).
- Built for [OpenCode](https://opencode.ai) by `sst`.
