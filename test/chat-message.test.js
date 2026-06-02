// chat-message.test.js — tests the chat.message hook with synthetic FilePart input
import { VisionGeminiPlugin } from "../index.js";

const hooks = await VisionGeminiPlugin({});

let ok = true;

// Test 1: no FilePart → no hint injected
{
  const out = { parts: [{ type: "text", text: "hello" }] };
  await hooks["chat.message"]({}, out);
  const textParts = out.parts.filter((p) => p.type === "text");
  if (textParts.length !== 1 || textParts[0].text !== "hello") {
    console.error("FAIL: non-image message should not be modified");
    ok = false;
  } else {
    console.log("OK: non-image message unchanged");
  }
}

// Test 2: FilePart with image/png data URL → hint injected
{
  const tinyPngB64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
  const out = {
    parts: [
      { type: "text", text: "what is in this image?" },
      {
        type: "file",
        mime: "image/png",
        filename: "test.png",
        url: `data:image/png;base64,${tinyPngB64}`,
      },
    ],
  };
  await hooks["chat.message"]({}, out);
  const textPart = out.parts.find((p) => p.type === "text");
  if (!textPart?.text?.includes("[SYSTEM:") || !textPart?.text?.includes("vision_analyze")) {
    console.error("FAIL: image message should get SYSTEM hint");
    console.error("Got text:", textPart?.text);
    ok = false;
  } else {
    console.log("OK: image message got SYSTEM hint");
    console.log("    text starts with:", textPart.text.slice(0, 80) + "...");
  }
}

// Test 3: experimental.chat.system.transform → VISION CAPABILITY added
{
  const out = { system: ["You are a helpful assistant."] };
  await hooks["experimental.chat.system.transform"]({}, out);
  const joined = out.system.join("\n");
  if (!joined.includes("VISION CAPABILITY")) {
    console.error("FAIL: system transform did not inject VISION CAPABILITY");
    ok = false;
  } else {
    console.log("OK: system transform injected VISION CAPABILITY");
  }
}

process.exit(ok ? 0 : 1);
