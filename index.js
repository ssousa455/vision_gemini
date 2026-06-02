import { tool } from "@opencode-ai/plugin";
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { resolve, join, basename, extname } from "node:path";
import { homedir, tmpdir } from "node:os";
import { createHash } from "node:crypto";

// ──────────────────────────────────────────────────────────────────────────────
// API key resolution
// ──────────────────────────────────────────────────────────────────────────────

function loadApiKey() {
  const fromEnv = process.env.GOOGLE_API_KEY || process.env.GEMINI_API_KEY;
  if (fromEnv) return fromEnv;
  for (const p of [
    resolve(homedir(), ".config/opencode/.env"),
    resolve(homedir(), ".env"),
  ]) {
    if (!existsSync(p)) continue;
    for (const line of readFileSync(p, "utf8").split(/\r?\n/)) {
      const m = line.match(/^\s*(GOOGLE_API_KEY|GEMINI_API_KEY)\s*=\s*(.+?)\s*$/);
      if (m) {
        process.env[m[1]] = m[2];
        return m[2];
      }
    }
  }
  return null;
}

// ──────────────────────────────────────────────────────────────────────────────
// Image helpers
// ──────────────────────────────────────────────────────────────────────────────

const MIME = {
  "image/png": ".png",
  "image/jpeg": ".jpg",
  "image/jpg": ".jpg",
  "image/webp": ".webp",
  "image/gif": ".gif",
  "image/bmp": ".bmp",
  "image/heic": ".heic",
  "image/heif": ".heif",
};

const IMAGE_DIR = process.env.OPENCODE_VISION_DIR
  ? resolve(process.env.OPENCODE_VISION_DIR)
  : join(process.env.LOCALAPPDATA || join(homedir(), "AppData/Local"), "opencode", "images");

try {
  mkdirSync(IMAGE_DIR, { recursive: true });
} catch {}

function isImageMime(mime) {
  return typeof mime === "string" && mime.toLowerCase().startsWith("image/");
}

async function saveDataUrl(url) {
  const m = url.match(/^data:([^;,]+)(;base64)?,(.*)$/s);
  if (!m) return null;
  const mime = m[1].toLowerCase();
  if (!isImageMime(mime)) return null;
  const ext = MIME[mime] || ".bin";
  const isBase64 = !!m[2];
  const data = m[3];
  const buf = isBase64
    ? Buffer.from(data, "base64")
    : Buffer.from(decodeURIComponent(data), "utf8");
  return { buf, mime, ext };
}

async function saveFileUrl(url) {
  // file:///C:/path or file://hostname/path
  try {
    const u = new URL(url);
    if (u.protocol !== "file:") return null;
    const p = decodeURIComponent(u.pathname);
    if (!existsSync(p)) return null;
    const buf = readFileSync(p);
    const ext = extname(p) || ".bin";
    const mime = Object.entries(MIME).find(([, e]) => e === ext.toLowerCase())?.[0] || "image/png";
    return { buf, mime, ext };
  } catch {
    return null;
  }
}

async function saveRemoteUrl(url) {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    const mime = (res.headers.get("content-type") || "image/png").split(";")[0].toLowerCase();
    if (!isImageMime(mime)) return null;
    const ext = MIME[mime] || ".bin";
    return { buf, mime, ext };
  } catch {
    return null;
  }
}

async function saveImageFromPart(part) {
  const url = part.url || "";
  if (url.startsWith("data:")) return await saveDataUrl(url);
  if (url.startsWith("file:")) return await saveFileUrl(url);
  if (url.startsWith("http://") || url.startsWith("https://")) return await saveRemoteUrl(url);
  return null;
}

function persistImage(buf, mime, ext, originalName) {
  const hash = createHash("sha1").update(buf).digest("hex").slice(0, 10);
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const base = (originalName || "image").replace(/[^\w.\-]/g, "_").replace(/\.[^.]+$/, "");
  const filename = `${ts}_${base}_${hash}${ext}`;
  const fullPath = join(IMAGE_DIR, filename);
  writeFileSync(fullPath, buf);
  return fullPath;
}

function listRecentImages(limit = 10) {
  try {
    const files = readdirSync(IMAGE_DIR)
      .map((name) => {
        const full = join(IMAGE_DIR, name);
        try {
          const s = statSync(full);
          return { name, full, mtime: s.mtimeMs, size: s.size };
        } catch {
          return null;
        }
      })
      .filter(Boolean)
      .sort((a, b) => b.mtime - a.mtime)
      .slice(0, limit);
    return files;
  } catch {
    return [];
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Gemini Vision
// ──────────────────────────────────────────────────────────────────────────────

async function callGemini(prompt, b64, mime) {
  const key = loadApiKey();
  if (!key) throw new Error("GOOGLE_API_KEY not set. Add to ~/.config/opencode/.env");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${key}`;
  const payload = {
    contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: b64 } }] }],
  };
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini ${res.status}: ${err.slice(0, 200)}`);
  }
  const json = await res.json();
  return json.candidates?.[0]?.content?.parts?.[0]?.text || "(no text)";
}

function resolveMime(path) {
  const ext = path.toLowerCase().match(/\.[^.]+$/)?.[0];
  return Object.entries(MIME).find(([, e]) => e === ext)?.[0] || "image/png";
}

async function analyzeImage(absPath, prompt) {
  if (!existsSync(absPath)) throw new Error(`File not found: ${absPath}`);
  const b64 = readFileSync(absPath).toString("base64");
  const mime = resolveMime(absPath);
  return await callGemini(prompt, b64, mime);
}

// ──────────────────────────────────────────────────────────────────────────────
// Plugin
// ──────────────────────────────────────────────────────────────────────────────

export const VisionGeminiPlugin = async () => {
  return {
    tool: {
      vision_describe: tool({
        description:
          "Describe an image in detail. Returns composition, colors, visible text, objects, and context. Pass an optional `prompt` for specific questions about the image.",
        args: {
          image_path: tool.schema.string().describe("Absolute path to the image file"),
          prompt: tool.schema
            .string()
            .optional()
            .describe("Optional custom question about the image"),
        },
        async execute(args) {
          const abs = resolve(args.image_path);
          const p =
            args.prompt ||
            "Describe this image comprehensively. Include: 1) main subject and composition, 2) colors/lighting/style, 3) ALL visible text (transcribed exactly), 4) people/objects/environment, 5) context (UI screenshot, photo, diagram, etc.), 6) notable visual elements. Be precise. Do not speculate.";
          return await analyzeImage(abs, p);
        },
      }),
      vision_ocr: tool({
        description:
          "Extract text from an image using OCR via Google Gemini Vision. Returns the extracted text exactly as it appears.",
        args: {
          image_path: tool.schema.string().describe("Absolute path to the image file containing text"),
        },
        async execute(args) {
          const abs = resolve(args.image_path);
          return await analyzeImage(
            abs,
            "Extract ALL text from this image EXACTLY as it appears. Preserve original language, capitalization, line breaks, and formatting. Return ONLY the extracted text with no commentary. If no text, say '[No text detected]'."
          );
        },
      }),
      vision_analyze: tool({
        description:
          "Complete image analysis: file metadata + visual description + OCR text extraction. Best for comprehensive understanding of any image.",
        args: {
          image_path: tool.schema.string().describe("Absolute path to the image file"),
        },
        async execute(args) {
          const abs = resolve(args.image_path);
          return await analyzeImage(
            abs,
            "Provide a complete analysis of this image with three sections: 1) CONTEXT - what kind of image (screenshot/photo/diagram/document), overall purpose; 2) DESCRIPTION - detailed visual description of composition, colors, people, objects, environment; 3) TEXT - all visible text transcribed exactly, preserving original language. Be precise and structured."
          );
        },
      }),
      vision_recent_images: tool({
        description:
          "List images that were recently pasted/dropped into the chat (auto-saved by the plugin) or saved to the plugin image directory. Use this when the user pastes an image and you need to find its path before calling vision_describe/ocr/analyze.",
        args: {
          limit: tool.schema.number().optional().describe("Maximum number of images to return (default 5)"),
        },
        async execute(args) {
          const files = listRecentImages(args.limit ?? 5);
          if (!files.length) {
            return `No images found in ${IMAGE_DIR}.`;
          }
          return files
            .map((f, i) => `${i + 1}. ${f.full}  (${(f.size / 1024).toFixed(1)} KB, ${new Date(f.mtime).toISOString()})`)
            .join("\n");
        },
      }),
    },

    // ── Hook: auto-save pasted/dropped images and inject path into the message
    "chat.message": async (input, output) => {
      const parts = output?.parts;
      if (!Array.isArray(parts)) return;

      const imageIndexes = [];
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        if (p && p.type === "file" && isImageMime(p.mime)) imageIndexes.push(i);
      }
      if (imageIndexes.length === 0) return;

      const injectedPaths = [];
      for (const idx of imageIndexes) {
        const part = parts[idx];
        try {
          const saved = await saveImageFromPart(part);
          if (!saved) continue;
          const fullPath = persistImage(saved.buf, saved.mime, saved.ext, part.filename);
          injectedPaths.push({ idx, fullPath, mime: saved.mime, filename: part.filename });
        } catch (e) {
          // continue with other images
        }
      }
      if (injectedPaths.length === 0) return;

      // Find existing text part to append, or insert a new one
      const hint = injectedPaths
        .map(
          (i) =>
            `[SYSTEM: An image was attached to this message. The image file was auto-saved at: ${i.fullPath}. You CAN see this image by calling the vision_analyze (or vision_describe / vision_ocr) tool with that path — do NOT say you cannot see images. The image is a local file, not a base64 attachment. Call the tool now and answer the user's question about the image.]`
        )
        .join("\n");

      const lastTextIdx = (() => {
        for (let i = parts.length - 1; i >= 0; i--) {
          if (parts[i] && parts[i].type === "text") return i;
        }
        return -1;
      })();

      if (lastTextIdx >= 0) {
        const cur = parts[lastTextIdx];
        parts[lastTextIdx] = { ...cur, text: (cur.text ? cur.text + "\n\n" : "") + hint };
      } else {
        parts.push({
          type: "text",
          text: hint,
        });
      }
    },

    // Persistent system prompt: remind every model that the vision tools exist
    "experimental.chat.system.transform": async (_input, output) => {
      const reminder =
        "VISION CAPABILITY: You have access to vision_describe, vision_ocr, vision_analyze, and vision_recent_images tools. " +
        "These tools call Google Gemini Vision under the hood and return text descriptions. " +
        "When the user attaches or pastes an image, the opencode-vision-gemini plugin auto-saves it and injects the file path into the message. " +
        "You MUST call vision_analyze (or vision_describe / vision_ocr) on the injected path before responding. " +
        "Do NOT say 'I cannot see images' or 'no image was received' — the file is on local disk and the vision tool will read it for you.";
      if (Array.isArray(output.system) && !output.system.some((s) => typeof s === "string" && s.includes("VISION CAPABILITY"))) {
        output.system = [...output.system, reminder];
      } else if (typeof output.system === "string" && !output.system.includes("VISION CAPABILITY")) {
        output.system = output.system + "\n\n" + reminder;
      }
    },
  };
};
