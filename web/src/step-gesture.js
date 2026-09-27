// A trackpad swipe can emit momentum events long after the fingers have stopped.
// Ignore its momentum, but recognize a fresh impulse while the camera is moving.
export function createStepGesture({ threshold = 28, quietMs = 200 } = {}) {
  let lastAt = -Infinity;
  let consumed = false;
  let total = 0;
  let lastMagnitude = 0;
  let triggeredAt = -Infinity;
  return {
    push(delta, at) {
      if (!Number.isFinite(delta)) return 0;
      const magnitude = Math.abs(delta);
      const freshImpulse =
        consumed &&
        at - triggeredAt > 240 &&
        lastMagnitude < 24 &&
        magnitude >= 42 &&
        magnitude > lastMagnitude * 2.8;
      if (at - lastAt > quietMs || freshImpulse) {
        consumed = false;
        total = 0;
      }
      lastAt = at;
      lastMagnitude = magnitude;
      if (consumed) return 0;
      if (Math.sign(delta) !== Math.sign(total)) total = 0;
      total += delta;
      if (Math.abs(total) < threshold) return 0;
      consumed = true;
      triggeredAt = at;
      return Math.sign(total);
    },
  };
}
