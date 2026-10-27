import { clamp, demoReports } from "./data.js";
import { easeCamera } from "./story-state.js";
import { alertExamples, demoGps } from "./alert-sonar.js";

// Offshore stops across Madeira, the Canaries and Cape Verde keep coastal arrivals.
// An illustrated island offshore from Madeira, clear of the real coastline.
export const harbor = [-17.029277, 32.93];
export const overview = {
  x: harbor[0] + 0.015,
  y: harbor[1],
  zoom: 10.6,
  pitch: 28,
  bearing: 0,
};
export const mapJourney = [
  {
    x: demoReports.whale.location[0],
    y: demoReports.whale.location[1],
    zoom: 10,
    pitch: 28,
    bearing: 0,
  },
  {
    x: demoReports.container.location[0],
    y: demoReports.container.location[1],
    zoom: 10.7,
    pitch: 28,
    bearing: -24,
  },
  {
    x: demoReports.duck.location[0],
    y: demoReports.duck.location[1],
    zoom: 10.6,
    pitch: 28,
    bearing: -12,
  },
  {
    x:
      (Math.min(
        demoGps[0],
        ...alertExamples.map((report) => report.location[0]),
      ) +
        Math.max(
          demoGps[0],
          ...alertExamples.map((report) => report.location[0]),
        )) /
      2,
    y:
      (Math.min(
        demoGps[1],
        ...alertExamples.map((report) => report.location[1]),
      ) +
        Math.max(
          demoGps[1],
          ...alertExamples.map((report) => report.location[1]),
        )) /
      2,
    zoom: 11.2,
    pitch: 0,
    bearing: 0,
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
export function cameraTravelDuration(from, to, steps = 1) {
  const distance = degrees(globeDistance(from, to));
  let duration;
  if (distance < 0.5)
    duration = clamp(
      1400 + Math.abs(to.zoom - from.zoom) * 200 + distance * 1000,
      1400,
      2200,
    );
  else if (distance < 25) duration = clamp(1800 + distance * 35, 1800, 2700);
  else duration = clamp(2600 + distance * 5, 2800, 3600);
  return Math.round(
    steps > 1 ? Math.max(1000, duration / Math.sqrt(steps)) : duration,
  );
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
    distance > 25 ? 4.2 : clamp(8.6 - Math.log2(distance), 5.6, 7.5);
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
