import test from "node:test";
import assert from "node:assert/strict";
import { spots, sources, reportCategories, clamp } from "./data.js";
import { journey } from "./story-data.js";

test("the tour covers every object exactly once, with a visible asset and a supported report category", () => {
  assert.equal(journey.length, 11);
  assert.deepEqual(
    new Set(journey.map((s) => s.id)),
    new Set(spots.map((s) => s.id)),
  );
  assert.equal(new Set(journey.map((s) => s.id)).size, journey.length);
  spots.forEach((spot) => {
    assert.ok(
      spot.size > 0,
      `${spot.id} must be an illustration, not a plus marker`,
    );
    assert.ok(reportCategories[spot.reportCategory]);
  });
  journey.forEach((scene) => {
    if (scene.source)
      assert.ok(sources[scene.source]?.url.startsWith("https://"));
  });
});
test("zoom and pan bounds constrain input", () => {
  assert.equal(clamp(-5, 0, 1), 0);
  assert.equal(clamp(5, 0, 1), 1);
  assert.equal(clamp(0.5, 0, 1), 0.5);
});
