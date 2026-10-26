import { createMaritimeMap } from "./maritime-map.js";
import { overview, harbor, globeDistance } from "./map-journey.js";
import { demoReports } from "./data.js";

export function createWorld() {
  let current = { ...overview };
  let introStrength = 1;
  let visible = !["#carte", "#alertes"].some((hash) =>
    location.hash.startsWith(hash),
  );
  const surface = document.querySelector("#journey-map");
  const anchors = [...document.querySelectorAll("[data-geo]")];
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
      element.style.setProperty("--map-y", `${projected.y}px`);
      const scene = element.closest(".map-spot");
      scene?.style.setProperty("--map-x", `${projected.x}px`);
      scene?.style.setProperty("--map-y", `${projected.y}px`);
      element.style.setProperty(
        "--map-scale",
        String(Math.min(1, Math.max(0.06, 2 ** ((map.getZoom() - 9) / 2)))),
      );
      element.classList.toggle("is-behind-globe", !front);
    }
  }
  function applyPose() {
    if (!chart?.map || !visible) return;
    const mobile = surface.clientWidth <= 760;
    const zoom = mobile
      ? current.zoom - Math.max(0, Math.min(1, (3 - current.zoom) / 2)) * 0.9
      : current.zoom;
    const padding = mobile
      ? {
          top: 145 + 180 * introStrength,
          bottom: 165 - 105 * introStrength,
          left: 0,
          right: 0,
        }
      : { top: 20, bottom: 100, left: surface.clientWidth * 0.28, right: 0 };
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
    guide(pose, intro = 0) {
      if (
        introStrength === intro &&
        Object.keys(pose).every((key) => pose[key] === current[key])
      )
        return;
      introStrength = intro;
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
