import { clamp, demoReports } from "./data.js";
import { easeCamera } from "./story-state.js";

// Coastal examples in three oceans. Long transfers pull back to the globe.
// An illustrated headland just offshore from Ponta do Pargo, Madeira.
export const harbor = [-17.34, 32.8133];
export const overview = {
  x: harbor[0] + 0.015,
  y: harbor[1],
  zoom: 10.5,
  pitch: 38,
  bearing: -18,
};
export const mapJourney = [
  {
    x: demoReports.whale.location[0],
    y: demoReports.whale.location[1],
    zoom: 9.3,
    pitch: 32,
    bearing: -12,
  },
  {
    x: demoReports.container.location[0],
    y: demoReports.container.location[1],
    zoom: 10.5,
    pitch: 36,
    bearing: 12,
  },
  {
    x: demoReports.duck.location[0],
    y: demoReports.duck.location[1],
    zoom: 10.2,
    pitch: 32,
    bearing: -12,
  },
];
const radians = (value) => (value * Math.PI) / 180;
const degrees = (value) => (value * 180) / Math.PI;
const vector = (pose) => [
  Math.cos(radians(pose.y)) * Math.cos(radians(pose.x)),
  Math.cos(radians(pose.y)) * Math.sin(radians(pose.x)),
  Math.sin(radians(pose.y)),
];
export function globeDistance(from, to) {
  const a = vector(from),
    b = vector(to);
  return Math.acos(
    clamp(
      a.reduce((sum, value, i) => sum + value * b[i], 0),
      -1,
      1,
    ),
  );
}
export function globePoint(from, to, progress) {
  const angle = globeDistance(from, to),
    a = vector(from),
    b = vector(to);
  if (angle < 0.00001) return [from.x, from.y];
  // The actual routes are non-antipodal. Linear fallback avoids singular input.
  if (Math.abs(Math.sin(angle)) < 0.00001) {
    const delta = ((to.x - from.x + 540) % 360) - 180;
    return [
      ((from.x + delta * progress + 540) % 360) - 180,
      from.y + (to.y - from.y) * progress,
    ];
  }
  const left = Math.sin((1 - progress) * angle) / Math.sin(angle),
    right = Math.sin(progress * angle) / Math.sin(angle);
  const point = a.map((value, i) => value * left + b[i] * right);
  return [
    degrees(Math.atan2(point[1], point[0])),
    degrees(Math.atan2(point[2], Math.hypot(point[0], point[1]))),
  ];
}
export function cameraTravelDuration(from, to) {
  const distance = degrees(globeDistance(from, to));
  if (distance < 0.5)
    return Math.round(
      clamp(
        900 + Math.abs(to.zoom - from.zoom) * 280 + distance * 500,
        900,
        1800,
      ),
    );
  if (distance < 25) return Math.round(clamp(3600 + distance * 80, 3600, 5600));
  return Math.round(clamp(5200 + distance * 16, 5800, 8000));
}
export function cameraBetween(from, to, progress) {
  const t = clamp(progress, 0, 1);
  if (t === 0) return { ...from };
  if (t === 1) return { ...to };
  const distance = degrees(globeDistance(from, to));
  const pullBack = distance > 1 && Math.max(from.zoom, to.zoom) > 3;
  const orbit = pullBack
    ? easeCamera(clamp((t - 0.16) / 0.68, 0, 1))
    : easeCamera(t);
  const [x, y] = globePoint(from, to, orbit);
  if (!pullBack)
    return {
      x,
      y,
      zoom: from.zoom + (to.zoom - from.zoom) * orbit,
      pitch: from.pitch + (to.pitch - from.pitch) * orbit,
      bearing: from.bearing + (to.bearing - from.bearing) * orbit,
    };
  // Spend enough time pulling back before travelling, then approach the coast
  // gradually. Camera phases receive raw time, avoiding stacked acceleration.
  const departure = easeCamera(clamp(t / 0.45, 0, 1));
  const arrival = easeCamera(clamp((t - 0.55) / 0.45, 0, 1));
  const cruiseZoom =
    distance > 25 ? 2.6 : clamp(8.6 - Math.log2(distance), 5.6, 7.5);
  const globeZoom = Math.min(cruiseZoom, from.zoom, to.zoom);
  return {
    x,
    y,
    zoom:
      from.zoom +
      (globeZoom - from.zoom) * departure +
      (to.zoom - globeZoom) * arrival,
    pitch: from.pitch * (1 - departure) + to.pitch * arrival,
    bearing: from.bearing * (1 - departure) + to.bearing * arrival,
  };
}
