import { demoReports } from "./data.js";

const earthRadius = 6371008.8;
const radians = (degrees) => (degrees * Math.PI) / 180;
export const demoGps = [-22.934423, 16.563557];
export const emptySonar = { type: "FeatureCollection", features: [] };

// Same spherical destination calculation as mobile ReportReach.destination.
export function destination([longitude, latitude], bearing, meters) {
  const lat = radians(latitude),
    angle = meters / earthRadius;
  const nextLat = Math.asin(
    Math.sin(lat) * Math.cos(angle) +
      Math.cos(lat) * Math.sin(angle) * Math.cos(bearing),
  );
  const nextLng =
    radians(longitude) +
    Math.atan2(
      Math.sin(bearing) * Math.sin(angle) * Math.cos(lat),
      Math.cos(angle) - Math.sin(lat) * Math.sin(nextLat),
    );
  return [
    (((nextLng * 180) / Math.PI + 540) % 360) - 180,
    (nextLat * 180) / Math.PI,
  ];
}

export const alertExamples = [
  ["container", 1.2, 300],
  ["whale", 1.9, 235],
  ["duck", 2.6, 160],
].map(([key, miles, bearing], index) => ({
  ...demoReports[key],
  id: index,
  description:
    key === "container"
      ? "Un conteneur à la dérive au large de Sal."
      : demoReports[key].description,
  place: "Au large de Sal, Cap-Vert",
  distance: `${String(miles).replace(".", ",")} NM`,
  distanceMeters: miles * 1852,
  location: destination(demoGps, radians(bearing), miles * 1852),
}));

// Mobile AlertHaloPulse: three linear fronts, 6 seconds, opacity = 1 − progress.
export function sonarData(report, elapsedMs) {
  return {
    type: "FeatureCollection",
    features: Array.from({ length: 3 }, (_, index) => {
      const progress = ((elapsedMs + index * 2000) % 6000) / 6000;
      return {
        type: "Feature",
        properties: { opacity: 1 - progress },
        geometry: {
          type: "LineString",
          coordinates: Array.from({ length: 73 }, (_, step) =>
            destination(
              report.location,
              (step / 72) * Math.PI * 2,
              report.distanceMeters * progress,
            ),
          ),
        },
      };
    }),
  };
}
