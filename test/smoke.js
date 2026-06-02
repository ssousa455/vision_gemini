// smoke.js — sanity test for the plugin (no network, no API key needed)
// Run: npm test
import { VisionGeminiPlugin } from "../index.js";

const hooks = await VisionGeminiPlugin({});

const expectedTools = ["vision_describe", "vision_ocr", "vision_analyze", "vision_recent_images"];
const expectedHooks = ["chat.message", "experimental.chat.system.transform"];

let ok = true;
for (const name of expectedTools) {
  const fn = hooks.tool?.[name];
  if (typeof fn !== "function" && typeof fn?.execute !== "function") {
    console.error(`FAIL: tool ${name} not registered`);
    ok = false;
  }
}
for (const name of expectedHooks) {
  if (typeof hooks[name] !== "function") {
    console.error(`FAIL: hook ${name} not registered`);
    ok = false;
  }
}

if (ok) {
  console.log(`OK: ${expectedTools.length} tools + ${expectedHooks.length} hooks registered`);
  for (const name of expectedTools) console.log(`  - ${name}: ${typeof hooks.tool[name]}`);
  for (const name of expectedHooks) console.log(`  - ${name}: ${typeof hooks[name]}`);
  process.exit(0);
} else {
  process.exit(1);
}
