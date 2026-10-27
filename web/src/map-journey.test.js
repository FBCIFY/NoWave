import test from "node:test";
import assert from "node:assert/strict";
import {
  overview,
  mapJourney,
  cameraBetween,
  globePoint,
  globeDistance,
  cameraTravelDuration,
} from "./map-journey.js";
import { demoReports } from "./data.js";

test("long coastal transfers show a globe before arriving at the exact example", () => {
  const poses = [overview, ...mapJourney];
  for (let i = 1; i < poses.length; i++) {
    const from = poses[i - 1],
      to = poses[i];
    assert.deepEqual(cameraBetween(from, to, 0), from);
    assert.deepEqual(cameraBetween(from, to, 1), to);
    for (let n = 0; n <= 100; n++) {
      const view = cameraBetween(from, to, n / 100);
      assert.ok(Object.values(view).every(Number.isFinite));
      assert.ok(Math.abs(view.y) <= 85);
      assert.ok(view.zoom >= 0.5 && view.zoom <= 12);
    }
    if ((globeDistance(from, to) * 180) / Math.PI > 25)
      assert.ok(
        cameraBetween(from, to, 0.5).zoom >= 4.1 &&
          cameraBetween(from, to, 0.5).zoom <= 4.3,
      );
  }
});
test("the date line crossing takes the short arc", () => {
  const [lng, lat] = globePoint({ x: 170, y: 0 }, { x: -170, y: 0 }, 0.5);
  assert.ok(Math.abs(lng) > 179.9);
  assert.ok(Math.abs(lat) < 0.01);
});
test("scene destinations and illustrated report positions stay aligned", () => {
  ["whale", "container", "duck"].forEach((id, index) => {
    assert.deepEqual(
      [mapJourney[index].x, mapJourney[index].y],
      demoReports[id].location,
    );
  });
});
test("the journey spans several Atlantic islands with short regional transfers", () => {
  const poses = [overview, ...mapJourney];
  const legs = poses
    .slice(1)
    .map((to, index) => globeDistance(poses[index], to) * 6371008.8);
  assert.ok(legs.filter((meters) => meters > 100000).length >= 3);
  assert.ok(
    Math.max(...poses.map((pose) => pose.y)) -
      Math.min(...poses.map((pose) => pose.y)) >
      15,
  );
  assert.ok(
    Math.max(...poses.map((pose) => pose.x)) -
      Math.min(...poses.map((pose) => pose.x)) >
      8,
  );
  for (let i = 1; i < poses.length; i++) {
    const duration = cameraTravelDuration(poses[i - 1], poses[i]);
    assert.ok(duration >= 1400 && duration <= 2700);
    assert.ok(legs[i - 1] < 2000000);
    assert.ok(cameraBetween(poses[i - 1], poses[i], 0.5).zoom >= 5.5);
  }
  const distant = { ...overview, x: 104, y: 1 };
  assert.ok(cameraTravelDuration(overview, distant) <= 3600);
  assert.ok(cameraBetween(overview, distant, 0.5).zoom >= 4.1);
});
test("coastal camera travel limits zoom and angular speed and eases at both ends", () => {
  const poses = [overview, ...mapJourney];
  for (let i = 1; i < poses.length; i++) {
    const from = poses[i - 1],
      to = poses[i];
    const duration = cameraTravelDuration(from, to);
    const count = Math.ceil(duration / (1000 / 60));
    const secondsPerFrame = duration / count / 1000;
    let previous = cameraBetween(from, to, 0);
    for (let frame = 1; frame <= count; frame++) {
      const next = cameraBetween(from, to, frame / count);
      const zoomSpeed = Math.abs(next.zoom - previous.zoom) / secondsPerFrame;
      const angularSpeed =
        (globeDistance(previous, next) * 180) / Math.PI / secondsPerFrame;
      assert.ok(zoomSpeed < 16, `zoom speed ${zoomSpeed} on route ${i}`);
      assert.ok(
        angularSpeed < 170,
        `angular speed ${angularSpeed} on route ${i}`,
      );
      if (frame === 1 || frame === count) assert.ok(zoomSpeed < 0.02);
      previous = next;
    }
  }
  const regional = cameraBetween(overview, mapJourney[0], 0.5);
  assert.ok(
    regional.zoom >= 5.5 && regional.zoom < overview.zoom,
    "regional travel stays close to the coast while allowing a gentle pullback",
  );
});

test("jumping several slides shortens travel while retaining the selected destination", () => {
  const normal = cameraTravelDuration(overview, mapJourney[2]);
  const jump = cameraTravelDuration(overview, mapJourney[2], 3);
  assert.ok(jump < normal && jump >= 1000);
  assert.deepEqual(cameraBetween(overview, mapJourney[2], 1), mapJourney[2]);
});
