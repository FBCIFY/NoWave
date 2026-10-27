import { clamp } from "./data.js";

// Smooth speed changes rather than restarting the camera easing on every input.
// Integrate the damping exactly so 60 Hz and 120 Hz displays travel alike.
export function createTravelProgress(duration, startedAt) {
  const smoothingMs = 220;
  let phase = 0,
    speed = 1,
    targetSpeed = 1,
    lastAt = startedAt,
    activeUntil = startedAt;

  function integrate(time, target) {
    const elapsed = time - lastAt;
    if (elapsed <= 0) return;
    const decay = Math.exp(-elapsed / smoothingMs);
    const distance =
      target * elapsed + (speed - target) * smoothingMs * (1 - decay);
    phase = clamp(phase + distance / duration, 0, 1);
    speed = target + (speed - target) * decay;
    lastAt = time;
  }
  function sample(time) {
    if (lastAt < activeUntil)
      integrate(Math.min(time, activeUntil), targetSpeed);
    integrate(time, 1);
    return phase;
  }
  return {
    sample,
    accelerate(delta, time) {
      sample(time);
      if (phase === 1 || !Number.isFinite(delta) || Math.abs(delta) <= 12)
        return;
      if (time >= activeUntil) targetSpeed = 1;
      targetSpeed = clamp(targetSpeed + (Math.abs(delta) - 12) / 400, 1, 1.35);
      activeUntil = time + 200;
    },
  };
}
