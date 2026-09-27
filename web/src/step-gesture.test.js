import test from "node:test";
import assert from "node:assert/strict";
import { createStepGesture } from "./step-gesture.js";

test("one long trackpad gesture and its momentum advance only one stop", () => {
  const gate = createStepGesture();
  const results = Array.from({ length: 80 }, (_, n) =>
    gate.push(n < 6 ? 160 : 6, n * 16),
  );
  assert.equal(
    results.reduce((sum, value) => sum + value, 0),
    1,
  );
  assert.equal(
    gate.push(70, 1600),
    1,
    "a new gesture after release can advance",
  );
});
test("small deltas accumulate; reversing within the same gesture cannot skip another stop", () => {
  const gate = createStepGesture();
  assert.equal(gate.push(8, 0), 0);
  assert.equal(gate.push(12, 16), 0);
  assert.equal(gate.push(12, 32), 1);
  assert.equal(gate.push(-120, 48), 0);
  assert.equal(gate.push(-120, 300), -1);
});
test("a fresh swipe can interrupt old momentum without waiting for camera travel", () => {
  const gate = createStepGesture();
  assert.equal(gate.push(100, 0), 1);
  assert.equal(gate.push(6, 100), 0);
  assert.equal(gate.push(6, 180), 0);
  assert.equal(gate.push(90, 290), 1);
  assert.equal(gate.push(60, 310), 0);
});
