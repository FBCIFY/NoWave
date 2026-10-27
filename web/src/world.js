import { createMaritimeMap } from "./maritime-map.js";
import { overview, harbor, globeDistance, mapJourney } from "./map-journey.js";
import { journey } from "./story-data.js";
import { demoReports } from "./data.js";

export function createWorld() {
  let current = { ...overview };
  let introStrength = 1,
    alertsStrength = 0;
  const readyListeners = new Set();
  let visible = !location.hash.startsWith("#carte");
  const surface = document.querySelector("#journey-map");
  const anchors = [...document.querySelectorAll("[data-geo]")];
  const harborElement = anchors.find(
    (element) => element.dataset.geo === "harbor",
  );
  const referenceZooms = new Map([
    ["harbor", overview.zoom],
    ...journey.flatMap((scene, index) =>
      scene.report ? [[scene.report, mapJourney[index].zoom]] : [],
    ),
  ]);
  let chart;
  function ensureChart() {
    if (chart) return;
    chart = createMaritimeMap({
      container: "journey-map",
      status: document.querySelector("#journey-map-status"),
      interactive: false,
      demonstration: false,
      onReady(map) {
        map.on("render", positionArtifacts);
        readyListeners.forEach((callback) => callback(map));
        layout();
      },
    });
  }
  function layout() {
    if (!chart?.map || !visible) return;
    chart.map.resize();
    applyPose();
  }
  function positionArtifacts() {
    const map = chart?.map;
    if (!map || !visible) return;
    const center = map.getCenter();
    for (const element of anchors) {
      const position =
        element.dataset.geo === "harbor"
          ? harbor
          : demoReports[element.dataset.geo].location;
      const projected = map.project(position);
      const front =
        globeDistance(
          { x: center.lng, y: center.lat },
          { x: position[0], y: position[1] },
        ) <
          Math.PI * 0.48 || map.getZoom() > 4.5;
      element.style.setProperty("--map-x", `${projected.x}px`);

      const scene = element.closest(".map-spot");
      scene?.style.setProperty("--map-x", `${projected.x}px`);
      scene?.style.setProperty("--map-y", `${projected.y}px`);
      // Keep the illustration's footprint on the sea during camera pullbacks.
      const referenceZoom =
        (referenceZooms.get(element.dataset.geo) ?? overview.zoom) -
        (surface.clientWidth <= 760 ? 0.6 : 0);
      let scale = Math.min(1, 2 ** (map.getZoom() - referenceZoom));
      let imageY = projected.y;
      if (element === harborElement && surface.clientWidth > 760) {
        // Keep the coastline still; fit the lighthouse below the header.
        const ceiling =
          (document.querySelector(".site-header")?.offsetHeight || 80) + 12;
        scale = Math.min(
          scale,
          Math.max(
            0.45,
            (projected.y + 30 - ceiling) / (element.offsetHeight * 0.8),
          ),
        );
        imageY += Math.min(
          30,
          Math.max(
            0,
            ceiling - (projected.y - element.offsetHeight * 0.8 * scale),
          ),
        );
      }
      element.style.setProperty("--map-y", `${imageY}px`);
      element.style.setProperty("--map-scale", String(scale));
      element.classList.toggle("is-behind-globe", !front);
    }
  }
  function applyPose() {
    if (!chart?.map || !visible) return;
    const mobile = surface.clientWidth <= 760;
    const zoom = mobile
      ? current.zoom -
        0.6 -
        Math.max(0, Math.min(1, (3 - current.zoom) / 2)) * 0.9
      : current.zoom;
    const padding = mobile
      ? {
          top: 145 + 180 * introStrength - alertsStrength * 70,
          bottom: 165 - 105 * introStrength + alertsStrength * 280,
          left: 0,
          right: 0,
        }
      : {
          top: 20,
          bottom: 100,
          left: surface.clientWidth * 0.2,
          right: 0,
        };
    chart.map.jumpTo({
      center: [current.x, current.y],
      zoom,
      pitch: current.pitch,
      bearing: current.bearing,
      padding,
    });
    positionArtifacts();
  }
  const observer = new ResizeObserver(layout);
  observer.observe(surface);
  if (visible) ensureChart();
  return {
    whenReady(callback) {
      readyListeners.add(callback);
      if (chart?.ready) callback(chart.map);
    },
    guide(pose, intro = 0, alerts = 0) {
      if (
        introStrength === intro &&
        alertsStrength === alerts &&
        Object.keys(pose).every((key) => pose[key] === current[key])
      )
        return;
      introStrength = intro;
      alertsStrength = alerts;
      current = { ...pose };
      applyPose();
    },
    pose() {
      return { ...current };
    },
    setVisible(value) {
      visible = value;
      if (visible) {
        ensureChart();
        layout();
      } else chart?.map?.stop();
    },
  };
}
