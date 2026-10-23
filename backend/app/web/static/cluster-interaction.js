window.NoWaveClusterInteraction = {
  expand(map, feature, reducedMotion = false) {
    const clusterId = feature?.properties?.cluster_id;
    const center = feature?.geometry?.coordinates;
    if (!Number.isInteger(clusterId) || !Array.isArray(center)) return;
    map.getSource('reports').getClusterExpansionZoom(clusterId, (error, zoom) => {
      if (error || !Number.isFinite(zoom)) return;
      map.easeTo({center, zoom, duration: reducedMotion ? 0 : 600});
    });
  },
};
