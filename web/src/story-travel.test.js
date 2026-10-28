import test from "node:test";
import assert from "node:assert/strict";
import { createTravelProgress } from "./story-travel.js";
import { getTransitionState } from "./story-state.js";
import { createStepGesture } from "./step-gesture.js";

test("additional scrolling speeds up an ongoing trip without jumping its position", () => {
  const normal = createTravelProgress(5000, 0);
  const boosted = createTravelProgress(5000, 0);
  assert.equal(boosted.sample(500), 0.1);
  boosted.accelerate(220, 500);
  assert.equal(boosted.sample(500), 0.1);
  assert.ok(boosted.sample(700) > normal.sample(700));
  assert.ok(boosted.sample(700) < 0.18, "acceleration ramps up gradually");
  assert.ok(boosted.sample(5000) === 1);
});
test("sustained scrolling stops exactly at one destination despite remaining momentum", () => {
  const travel = createTravelProgress(5000, 0);
  const gesture = createStepGesture();
  let previous = 0,
    steps = 0,
    arrival = null;
  for (let time = 0; time <= 5000; time += 16) {
    steps += gesture.push(time < 800 ? 80 : 6, time);
    travel.accelerate(time < 800 ? 80 : 6, time);
    const phase = travel.sample(time);
    assert.ok(phase >= previous && phase <= 1);
    if (phase === 1 && arrival === null) arrival = time;
    previous = phase;
  }
  assert.ok(arrival > 1500 && arrival < 5000);
  assert.equal(steps, 1, "momentum cannot select the following stop");
  const state = getTransitionState(1, 2, travel.sample(10000));
  assert.equal(state.step, 2);
  assert.equal(state.blend, 1);
  assert.equal(state.opacity, 1);
});
test("accelerated travel is independent of refresh rate and settles back to normal speed", () => {
  const simulate = (rate) => {
    const travel = createTravelProgress(5000, 0);
    travel.accelerate(440, 0);
    for (let frame = 1; frame <= rate; frame++)
      travel.sample((frame * 1000) / rate);
    return travel;
  };
  const slow = simulate(60),
    fast = simulate(120);
  assert.ok(Math.abs(slow.sample(1000) - fast.sample(1000)) < 1e-10);
  const from = slow.sample(3000),
    to = slow.sample(3100);
  assert.ok(Math.abs(to - from - 0.02) < 0.00001);
});

test("small trackpad momentum cannot accelerate the base trip", () => {
  const normal = createTravelProgress(5000, 0);
  const momentum = createTravelProgress(5000, 0);
  for (let time = 0; time <= 1600; time += 16) momentum.accelerate(6, time);
  assert.ok(Math.abs(momentum.sample(2000) - normal.sample(2000)) < 1e-10);
});
