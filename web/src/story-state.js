import { clamp } from "./data.js";
import { journey } from "./story-data.js";

const introHold = 0.018;
const segment = (1 - introHold) / journey.length;
const travelShare = 0.62;
const frames = [
  { at: 0, step: 0 },
  { at: introHold, step: 0 },
];
export const storyStops = [0];
journey.forEach((_, i) => {
  const start = introHold + i * segment;
  frames.push({ at: start + segment * travelShare, step: i + 1 });
  frames.push({ at: start + segment, step: i + 1 });
  storyStops.push(start + segment * 0.84);
});

// Zero velocity and acceleration at both ends prevent abrupt camera arrivals.
export const easeCamera = (t) =>
  clamp(t * t * t * (t * (t * 6 - 15) + 10), 0, 1);
export function getTransitionState(from, to, phase, reducedMotion = false) {
  const eased = easeCamera(clamp(phase, 0, 1));
  const blend = reducedMotion ? Number(eased >= 0.5) : eased;
  const step = blend < 0.5 ? from : to;
  const opacity =
    reducedMotion || from === to
      ? 1
      : blend < 0.5
        ? 1 - easeCamera(Math.min(1, blend / 0.48))
        : easeCamera(Math.max(0, (blend - 0.52) / 0.48));
  return { from, to, blend, step, opacity };
}
export function getStoryState(progress, reducedMotion = false) {
  const position = clamp(progress, 0, 1);
  const end = frames.findIndex(
    (frame, index) => index > 0 && position <= frame.at + Number.EPSILON,
  );
  const from = frames[end - 1];
  const to = frames[end];
  const phase = clamp((position - from.at) / (to.at - from.at), 0, 1);
  return getTransitionState(from.step, to.step, phase, reducedMotion);
}

// Frame-rate independent damping: the same motion on a 60 Hz or 120 Hz display.
export function followProgress(current, target, elapsedMs) {
  const next =
    current +
    (target - current) * (1 - Math.exp(-Math.min(elapsedMs, 64) / 85));
  return Math.abs(next - target) < 0.00001 ? target : next;
}
