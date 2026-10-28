/* Shared Mapbox defaults for the public chart and the administration chart. */
window.NoWaveMapCore = Object.freeze({
  overview(width = 1024, height = 768) {
    // Use a closer globe where space permits; narrow/short views keep their fit.
    const available = Math.max(1, Math.min(width - 40, height - 100));
    return {
      x: -20, y: 25,
      zoom: Math.max(0.5, Math.min(1.75, 1.5 + Math.log2(available / 600))),
      pitch: 0, bearing: 0,
    };
  },
  createMap(options) {
    const map = new window.mapboxgl.Map({
      style: 'mapbox://styles/mapbox/dark-v11',
      projection: 'globe',
      renderWorldCopies: false,
      maxBounds: [[-180, -85], [180, 85]],
      minZoom: 0.5, maxZoom: 12,
      pitch: 0, bearing: 0, maxPitch: 0,
      dragRotate: false, pitchWithRotate: false, touchPitch: false,
      ...options,
      attributionControl: false,
    });
    map.addControl(new window.mapboxgl.AttributionControl({ compact: false }), 'bottom-right');
    return map;
  },
});
