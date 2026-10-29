import {
  alertExamples,
  demoGps,
  emptySonar,
  sonarData,
} from "./alert-sonar.js";

export function createNotificationMap(onSelect, world) {
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  let chart,
    visible = false,
    enabled = true,
    selected = alertExamples[0];
  let frame = 0,
    lastPaint = 0,
    startedAt = performance.now();

  function frameData(time) {
    frame = 0;
    if (
      !visible ||
      !enabled ||
      motion.matches ||
      document.hidden ||
      !chart?.ready
    )
      return;
    if (time - lastPaint >= 32) {
      chart.map
        .getSource("alerts-sonar")
        .setData(sonarData(selected, time - startedAt));
      lastPaint = time;
    }
    frame = requestAnimationFrame(frameData);
  }
  function sync() {
    cancelAnimationFrame(frame);
    frame = 0;
    if (!chart?.ready || !layersReady) return;
    if (visible && enabled && !motion.matches && !document.hidden)
      frame = requestAnimationFrame(frameData);
    else chart.map.getSource("alerts-sonar").setData(emptySonar);
  }
  let layersReady = false;
  function ensureLayers() {
    if (!chart?.ready || layersReady) return;
    const map = chart.map;
    layersReady = true;
    window.NoWaveMarkerIcons.install(map);
    map.addSource("alerts-sonar", { type: "geojson", data: emptySonar });
    map.addSource("alerts-points", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: alertExamples.map((report) => ({
          type: "Feature",
          properties: { index: report.id, category: report.category },
          geometry: { type: "Point", coordinates: report.location },
        })),
      },
    });
    map.addSource("alerts-gps", {
      type: "geojson",
      data: {
        type: "Feature",
        properties: {},
        geometry: { type: "Point", coordinates: demoGps },
      },
    });
    map.addLayer({
      id: "alerts-sonar-glow",
      type: "line",
      source: "alerts-sonar",
      paint: {
        "line-color": "#ff2028",
        "line-width": 7,
        "line-blur": 2.5,
        "line-opacity": ["*", ["get", "opacity"], 0.22],
      },
    });
    map.addLayer({
      id: "alerts-sonar-front",
      type: "line",
      source: "alerts-sonar",
      paint: {
        "line-color": "#ff2028",
        "line-width": 3,
        "line-blur": 0.3,
        "line-opacity": ["get", "opacity"],
      },
    });
    map.addLayer({
      id: "alerts-gps-halo",
      type: "circle",
      source: "alerts-gps",
      paint: {
        "circle-radius": 19,
        "circle-color": "#38bdf8",
        "circle-opacity": 0.2,
      },
    });
    map.addLayer({
      id: "alerts-gps-point",
      type: "circle",
      source: "alerts-gps",
      paint: {
        "circle-radius": 7,
        "circle-color": "#38bdf8",
        "circle-stroke-width": 2,
        "circle-stroke-color": "#fff",
      },
    });
    map.addLayer({
      id: "alerts-gps-label",
      type: "symbol",
      source: "alerts-gps",
      layout: {
        "text-field": "Vous",
        "text-size": 11,
        "text-offset": [0, 1.7],
        "text-anchor": "top",
        "text-allow-overlap": true,
      },
      paint: {
        "text-color": "#c0e3ed",
        "text-halo-color": "#0b2533",
        "text-halo-width": 2,
      },
    });
    map.addLayer({
      id: "alerts-report-markers",
      type: "symbol",
      source: "alerts-points",
      layout: {
        "icon-image": ["concat", "report-", ["get", "category"]],
        "icon-size": 0.75,
        "icon-allow-overlap": true,
        "icon-ignore-placement": true,
      },
    });
    // The list provides keyboard access; the chart remains a scroll-friendly illustration.
    map.on("click", "alerts-report-markers", (event) =>
      onSelect(Number(event.features[0].properties.index)),
    );
    map.on("mouseenter", "alerts-report-markers", () => {
      map.getCanvas().style.cursor = "pointer";
    });
    map.on("mouseleave", "alerts-report-markers", () => {
      map.getCanvas().style.cursor = "";
    });
  }
  world.whenReady((map) => {
    chart = { map, ready: true };
    if (visible) ensureLayers();
    updateVisibility();
  });
  function updateVisibility() {
    if (!layersReady) return;
    for (const id of [
      "alerts-sonar-glow",
      "alerts-sonar-front",
      "alerts-gps-halo",
      "alerts-gps-point",
      "alerts-gps-label",
      "alerts-report-markers",
    ])
      chart.map.setLayoutProperty(
        id,
        "visibility",
        visible ? "visible" : "none",
      );
    sync();
  }
  motion.addEventListener("change", sync);
  document.addEventListener("visibilitychange", sync);
  return {
    select(report) {
      selected = report;
      startedAt = performance.now();
      sync();
    },
    setEnabled(value) {
      enabled = value;
      sync();
    },
    setVisible(value) {
      if (visible === value) return;
      visible = value;
      if (visible) ensureLayers();
      updateVisibility();
    },
  };
}
