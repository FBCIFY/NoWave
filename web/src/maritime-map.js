import { overview } from "./map-journey.js";
import { demoReports } from "./data.js";

const explorerOverview = { x: -30, y: 24, zoom: 2.4 };
const demonstrationReports = {
  type: "FeatureCollection",
  features: Object.entries(demoReports)
    .filter(([, report]) => report.location)
    .map(([id, report]) => ({
      type: "Feature",
      id: `demo-${id}`,
      properties: { category: report.category, exemple: true },
      geometry: { type: "Point", coordinates: report.location },
    })),
};

let runtime;
function script(src) {
  return new Promise((resolve, reject) => {
    const element = document.createElement("script");
    const timeout = setTimeout(() => fail(), 12000);
    function fail() {
      clearTimeout(timeout);
      element.remove();
      reject(new Error("Cartographie momentanément indisponible."));
    }
    element.src = src;
    element.onload = () => {
      clearTimeout(timeout);
      resolve();
    };
    element.onerror = fail;
    document.head.append(element);
  });
}

async function loadRuntime() {
  if (!runtime)
    runtime = (async () => {
      const response = await fetch("/api/v1/map/web-config", {
        credentials: "omit",
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok)
        throw new Error("Cartographie momentanément indisponible.");
      const config = await response.json();
      if (!config.mapbox_token?.startsWith("pk."))
        throw new Error("La carte n’est pas disponible pour le moment.");
      if (!document.querySelector("link[data-maritime-map]")) {
        const css = document.createElement("link");
        css.rel = "stylesheet";
        css.href = "/admin-static/mapbox-gl.css";
        css.dataset.maritimeMap = "";
        document.head.append(css);
      }
      if (!window.mapboxgl) await script("/admin-static/mapbox-gl.js");
      if (!window.NoWaveMapCore) await script("/admin-static/map-core.js");
      if (!window.NoWaveMaritimeStyle)
        await script("/admin-static/maritime-style.js");
      if (!window.NoWaveMarkerIcons)
        await script("/admin-static/marker-icons.js");
      if (!window.mapboxgl.supported())
        throw new Error("Ce navigateur ne peut pas afficher la carte.");
      window.mapboxgl.accessToken = config.mapbox_token;
      return window.mapboxgl;
    })().catch((error) => {
      runtime = null;
      throw error;
    });
  return runtime;
}

function addDemonstrationReports(map) {
  if (!map.getSource("demo-reports")) {
    map.addSource("demo-reports", {
      type: "geojson",
      data: demonstrationReports,
    });
  }
  if (map.getLayer("demo-report-markers")) {
    map.setLayoutProperty("demo-report-markers", "visibility", "visible");
    return;
  }
  let iconsReady = map.hasImage("report-obstruction");
  if (!iconsReady) {
    try {
      iconsReady = window.NoWaveMarkerIcons.install(map);
    } catch {
      // Keep the same category colors if the icon canvas is unavailable.
    }
  }
  const layer = {
    id: "demo-report-markers",
    source: "demo-reports",
    minzoom: 8,
  };
  if (iconsReady) {
    map.addLayer({
      ...layer,
      type: "symbol",
      layout: {
        "icon-image": [
          "coalesce",
          ["image", ["concat", "report-", ["get", "category"]]],
          ["image", "report-unknown"],
        ],
        "icon-size": ["interpolate", ["linear"], ["zoom"], 8, 0.65, 12, 0.85],
        "icon-anchor": "center",
        "icon-allow-overlap": true,
        "icon-ignore-placement": true,
      },
    });
  } else {
    map.addLayer({
      ...layer,
      type: "circle",
      paint: {
        "circle-color": [
          "match",
          ["get", "category"],
          "obstruction",
          "#F97316",
          "marine_animal",
          "#06B6D4",
          "pollution",
          "#7C3AED",
          "#64748B",
        ],
        "circle-radius": 6,
        "circle-stroke-color": "#fff",
        "circle-stroke-width": 1,
      },
    });
  }
}

// Same engine, style and GEBCO source as the admin. No administrative data is requested.
export function createMaritimeMap({
  container,
  status,
  interactive,
  demonstration = !interactive,
  initialView,
  projection = interactive ? "mercator" : "globe",
  onLoading,
  onReady,
}) {
  const controller = { map: null, ready: false };
  const surface = document.getElementById(container);
  const showDemonstration = demonstration && !interactive;
  controller.setInteractive = (active) => {
    const map = controller.map;
    if (!map) return;
    const enabled = Boolean(active && interactive && controller.ready);
    for (const handler of [
      "dragPan",
      "scrollZoom",
      "boxZoom",
      "doubleClickZoom",
      "keyboard",
      "touchZoomRotate",
    ])
      map[handler][enabled ? "enable" : "disable"]();
    map.touchZoomRotate.disableRotation();
    map.keyboard.disableRotation();
    map.getCanvas().setAttribute("tabindex", enabled ? "0" : "-1");
    map.getCanvas().style.touchAction = enabled ? "none" : "pan-y pinch-zoom";
  };
  let starting = false;
  let startupTimer;
  function fail() {
    clearTimeout(startupTimer);
    onLoading?.();
    const map = controller.map;
    controller.map = null;
    controller.ready = false;
    map?.remove();
    surface.classList.remove("is-ready");
    starting = false;
    // A corrected or renewed public token must be fetched on the next attempt.
    runtime = null;
    const message = document.createElement("span");
    message.textContent = "La carte n’est pas disponible pour le moment.";
    const retry = document.createElement("button");
    retry.type = "button";
    retry.textContent = "Réessayer";
    retry.addEventListener("click", start);
    status.replaceChildren(message, retry);
  }
  async function start() {
    if (starting) return;
    starting = true;
    controller.ready = false;
    onLoading?.();
    status.textContent = "Chargement de la carte…";
    try {
      await loadRuntime();
      const initial =
        typeof initialView === "function"
          ? initialView()
          : (initialView ?? (interactive ? explorerOverview : overview));
      controller.map?.remove();
      const map = (controller.map = window.NoWaveMapCore.createMap({
        container,
        projection,
        // Each view owns its measured layout, including while hidden by routing.
        trackResize: false,
        center: [initial.x, initial.y],
        zoom: initial.zoom,
        pitch: initial.pitch ?? 0,
        bearing: initial.bearing ?? 0,
        interactive,
        dragPan: false,
        scrollZoom: false,
        boxZoom: false,
        doubleClickZoom: false,
        keyboard: false,
        touchZoomRotate: false,
        maxPitch: interactive ? 0 : 60,
      }));
      let styled = false;
      startupTimer = setTimeout(fail, 20000);
      map.touchZoomRotate.disableRotation();
      map.keyboard.disableRotation();
      map.getCanvas().setAttribute("tabindex", "-1");
      map.getCanvas().style.touchAction = "pan-y pinch-zoom";
      map.on("style.load", () => {
        if (controller.map !== map) return;
        try {
          window.NoWaveMaritimeStyle.apply(map, {
            login: projection === "globe",
          });
          if (showDemonstration && controller.ready)
            addDemonstrationReports(map);
          styled = true;
        } catch {
          fail();
        }
      });
      map.on("load", () => {
        if (controller.map !== map) return;
        if (showDemonstration) {
          try {
            addDemonstrationReports(map);
          } catch {
            fail();
            return;
          }
        }
        clearTimeout(startupTimer);
        starting = false;
        controller.ready = true;
        status.textContent = "";
        surface.classList.add("is-ready");
        onReady?.(map);
      });
      map.on("error", (event) => {
        if (controller.map !== map) return;
        // Initial style/token failures need a fresh attempt. A missing marine
        // tile must not destroy a working map or interrupt the guided journey.
        if (!styled && !event.sourceId) fail();
        else if (controller.ready)
          status.textContent = "Certains fonds de carte sont indisponibles.";
      });
    } catch {
      fail();
    }
  }
  start();
  return controller;
}
