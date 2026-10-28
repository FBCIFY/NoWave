import test from "node:test";
import assert from "node:assert/strict";
import {
  alertExamples,
  demoGps,
  destination,
  sonarData,
} from "./alert-sonar.js";

function distance([lng1, lat1], [lng2, lat2]) {
  const rad = Math.PI / 180;
  const a =
    Math.sin(((lat2 - lat1) * rad) / 2) ** 2 +
    Math.cos(lat1 * rad) *
      Math.cos(lat2 * rad) *
      Math.sin(((lng2 - lng1) * rad) / 2) ** 2;
  return 6371008.8 * 2 * Math.asin(Math.sqrt(a));
}
test("all nearby examples use one GPS position and their displayed nautical distance", () => {
  for (const report of alertExamples) {
    assert.ok(
      Math.abs(distance(demoGps, report.location) - report.distanceMeters) <
        0.001,
    );
    assert.equal(report.place, "Au large de Sal, Cap-Vert");
    assert.ok(report.distanceMeters < 10 * 1852);
  }
});
test("mobile sonar fronts are closed geographic rings with a six-second linear fade", () => {
  const report = alertExamples[1];
  assert.deepEqual(sonarData(report, 0), sonarData(report, 6000));
  for (const feature of sonarData(report, 1000).features) {
    const progress = 1 - feature.properties.opacity;
    const coordinates = feature.geometry.coordinates;
    assert.equal(coordinates.length, 73);
    for (const point of coordinates)
      assert.ok(
        Math.abs(
          distance(report.location, point) - report.distanceMeters * progress,
        ) < 0.001,
      );
    assert.ok(distance(coordinates[0], coordinates.at(-1)) < 0.001);
  }
});
test("the final wave radius reaches the GPS distance independent of map zoom", () => {
  for (const report of alertExamples) {
    const edge = destination(report.location, Math.PI, report.distanceMeters);
    assert.ok(
      Math.abs(
        distance(report.location, edge) - distance(report.location, demoGps),
      ) < 0.001,
    );
  }
});
