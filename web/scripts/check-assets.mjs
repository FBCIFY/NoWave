import { readFile, access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { spots } from "../src/data.js";

const root = new URL("../", import.meta.url);
const manifest = JSON.parse(
  await readFile(new URL("assets-manifest.json", root), "utf8"),
);
const expected = new Set([
  "archipelago",
  ...spots.map((spot) => spot.asset || spot.id),
]);
for (const id of expected) {
  const asset = manifest.assets.find((entry) => entry.id === id);
  if (!asset) throw new Error(`Missing asset manifest entry: ${id}`);
  await access(new URL(asset.file, root));
}
console.log(
  `${expected.size} CGI assets present in ${fileURLToPath(root)}public/assets/`,
);
