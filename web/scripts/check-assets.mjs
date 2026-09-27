import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { spots } from "../src/data.js";

const root = new URL("../", import.meta.url);
const expected = new Set([
  "archipelago",
  ...spots.map((spot) => spot.asset || spot.id),
]);
for (const id of expected) {
  await access(new URL(`public/assets/${id}.webp`, root));
}
console.log(
  `${expected.size} CGI assets present in ${fileURLToPath(root)}public/assets/`,
);
