import test from "node:test";
import assert from "node:assert/strict";
import { demoReports, reportCategories, clamp } from "./data.js";
import { journey } from "./story-data.js";
import { mapJourney } from "./map-journey.js";

test("every screen has a valid camera stop within the shared maritime map bounds", () => {
  assert.equal(mapJourney.length, journey.length);
  assert.equal(new Set(journey.map((scene) => scene.id)).size, journey.length);
  for (const pose of mapJourney) {
    assert.ok(Number.isFinite(pose.x) && Math.abs(pose.x) <= 180);
    assert.ok(Number.isFinite(pose.y) && Math.abs(pose.y) <= 85);
    assert.ok(
      Number.isFinite(pose.zoom) && pose.zoom >= 0.5 && pose.zoom <= 12,
    );
    assert.ok(
      Number.isFinite(pose.pitch) && pose.pitch >= 0 && pose.pitch <= 60,
    );
    assert.ok(Number.isFinite(pose.bearing) && Math.abs(pose.bearing) <= 180);
  }
});
test("refreshed illustrations and current report examples cover the product journey", () => {
  assert.equal(journey.filter((scene) => scene.asset).length, journey.length);
  assert.equal(journey.length, 3);
  assert.ok(journey.every((scene) => scene.report));
  for (const scene of journey) {
    if (scene.asset) assert.ok(scene.asset.startsWith("/assets/"));
    if (scene.report) assert.ok(demoReports[scene.report]);
  }
  assert.deepEqual(
    new Set(Object.values(demoReports).map((report) => report.category)),
    new Set(Object.keys(reportCategories)),
  );
  for (const report of Object.values(demoReports)) {
    assert.ok(report.author && report.time && report.place);
  }
});
test("zoom and pan bounds constrain input", () => {
  assert.equal(clamp(-5, 0, 1), 0);
  assert.equal(clamp(5, 0, 1), 1);
  assert.equal(clamp(0.5, 0, 1), 0.5);
});
