// make-test-image.js — generates a small PNG with text for testing
// Usage: node examples/make-test-image.js [output.png]
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";

// 1x1 white PNG (smallest valid PNG)
const tinyWhitePng = Buffer.from(
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c63f8cfc0f01f0005000100015b8c8b1c0000000049454e44ae426082",
  "hex"
);

// A slightly larger PNG would be better, but the 1x1 is enough to test the pipeline.
// For real visual testing, run:
//   opencode run "describe this image" -f ./test.png
const out = resolve(process.argv[2] || "./test.png");
writeFileSync(out, tinyWhitePng);
console.log(`Wrote ${out} (${tinyWhitePng.length} bytes)`);
console.log("\nNow run:");
console.log(`  opencode run "what is in this image?" -f ${out}`);
