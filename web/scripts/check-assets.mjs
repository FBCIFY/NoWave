import { access } from "node:fs/promises";
import { journey } from "../src/story-data.js";

const root = new URL("../", import.meta.url);
const expected = new Set([
  "/assets/lighthouse-v3.png",
  ...journey.map((scene) => scene.asset).filter(Boolean),
]);
for (const asset of expected) {
  await access(new URL("public" + asset, root));
}
console.log(`${expected.size} refreshed illustrations present.`);
