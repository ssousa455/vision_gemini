// manual-test.js — calls the plugin's hook directly with a fake FilePart
// Usage: node examples/manual-test.js [path-to-image.png]
import { VisionGeminiPlugin } from "../index.js";

const imagePath = process.argv[2];
if (!imagePath) {
  console.error("Usage: node examples/manual-test.js <image-path>");
  process.exit(1);
}

const hooks = await VisionGeminiPlugin({});

// Test 1: chat.message hook
const output = {
  parts: [
    {
      type: "file",
      mime: "image/png",
      filename: imagePath.split(/[\\/]/).pop(),
      url: `data:image/png;base64,${(await import("node:fs")).readFileSync(imagePath).toString("base64")}`,
    },
  ],
};
await hooks["chat.message"]({}, output);
console.log("After chat.message hook:");
for (const p of output.parts) {
  console.log(`  [${p.type}] ${p.text || p.url?.slice(0, 50) + "..."}`);
}

// Test 2: list tools
console.log("\nRegistered tools:");
for (const [name, def] of Object.entries(hooks.tool || {})) {
  console.log(`  - ${name}`);
}

// Test 3: call a tool (if GOOGLE_API_KEY is set)
if (process.env.GOOGLE_API_KEY) {
  console.log("\nCalling vision_analyze (this hits Gemini)...");
  const result = await hooks.tool.vision_analyze.execute({ image_path: imagePath });
  console.log("\nResult:\n" + result);
} else {
  console.log("\n(Set GOOGLE_API_KEY to also exercise the live Gemini call)");
}
