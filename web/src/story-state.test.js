import test from "node:test";
import assert from "node:assert/strict";
import { journey } from "./story-data.js";
import {
  getStoryState,
  storyStops,
  followProgress,
  easeCamera,
} from "./story-state.js";

test("all eleven objects have a readable stop before the recap", () => {
  assert.equal(storyStops.length, 12);
  assert.deepEqual(
    storyStops.map((p) => getStoryState(p).step),
    Array.from({ length: 12 }, (_, i) => i),
  );
  storyStops.forEach((p) => assert.equal(getStoryState(p).opacity, 1));
  assert.equal(getStoryState(-1).step, 0);
  assert.equal(getStoryState(2).step, journey.length);
});
test("scrolling backwards follows the same continuous camera path", () => {
  const frames = Array.from({ length: 1001 }, (_, i) =>
    getStoryState(i / 1000),
  );
  frames.forEach((state, i) => {
    assert.deepEqual(state, getStoryState(i / 1000));
    assert.ok(
      Number.isFinite(state.blend) && state.blend >= 0 && state.blend <= 1,
    );
    assert.ok(state.opacity >= 0 && state.opacity <= 1);
    const cameraStep = state.from + (state.to - state.from) * state.blend;
    if (i) {
      const prior = frames[i - 1],
        previous = prior.from + (prior.to - prior.from) * prior.blend;
      assert.ok(cameraStep >= previous - 1e-10);
      assert.ok(
        cameraStep - previous < 0.04,
        "no discontinuity at a stop boundary",
      );
    }
  });
});
test("camera easing settles at stops without abrupt velocity", () => {
  assert.equal(easeCamera(0), 0);
  assert.equal(easeCamera(1), 1);
  assert.ok(easeCamera(0.001) < 0.000001);
  assert.ok(1 - easeCamera(0.999) < 0.000001);
});
test("damping has the same duration at 60 Hz and 120 Hz and stops at rest", () => {
  const simulate = (rate) => {
    let current = 0;
    for (let i = 0; i < rate / 2; i++)
      current = followProgress(current, 1, 1000 / rate);
    return current;
  };
  assert.ok(Math.abs(simulate(60) - simulate(120)) < 0.00001);
  let current = 1;
  for (let i = 0; i < 200; i++) current = followProgress(current, 0, 16);
  assert.equal(current, 0);
});
test("reduced motion switches scenes without interpolated travel", () => {
  for (let i = 0; i <= 1000; i++) {
    const state = getStoryState(i / 1000, true);
    assert.ok(state.blend === 0 || state.blend === 1);
    assert.equal(state.opacity, 1);
  }
});
