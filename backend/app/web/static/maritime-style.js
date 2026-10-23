/* Palette and real land classes adapted from Flutter GlobeStyle/MarinePalette. */
window.NoWaveMaritimeStyle = {
  apply(map, {login = false} = {}) {
    map.setFog(login ? {
      color: '#84D6F2', 'high-color': 'rgba(40,145,210,0.70)',
      'space-color': '#020711', 'horizon-blend': 0.012, 'star-intensity': 0,
    } : null);
    const layers = map.getStyle().layers;
    for (const layer of layers) {
      if (layer.type === 'symbol' || layer.type === 'line' ||
          (layer.type === 'fill' && layer['source-layer'] !== 'water')) {
        map.setLayoutProperty(layer.id, 'visibility', 'none');
      }
      if (layer.type === 'background') map.setPaintProperty(layer.id, 'background-color', '#c8bc9f');
      if (layer.type === 'fill' && layer['source-layer'] === 'water') {
        map.setPaintProperty(layer.id, 'fill-color', '#002D51');
        map.setPaintProperty(layer.id, 'fill-outline-color', 'rgba(0,0,0,0)');
      }
    }
    const firstWater = layers.find(layer => layer.type === 'fill' && layer['source-layer'] === 'water');
    if (!map.getSource('nowave-landcover')) map.addSource('nowave-landcover', {
      type:'vector', url:'mapbox://mapbox.mapbox-terrain-v2', maxzoom:14,
    });
    if (!map.getLayer('nowave-landcover')) map.addLayer({
      id:'nowave-landcover',type:'fill',source:'nowave-landcover','source-layer':'landcover',
      paint:{'fill-color':['match',['get','class'],'wood','#48634c','scrub','#748469',
        'grass','#8b9978','crop','#a6ad8d','snow','#ECEDE5','rgba(0,0,0,0)']},
    },firstWater?.id);
    if (!map.getLayer('nowave-land-relief')) map.addLayer({
      id:'nowave-land-relief',type:'fill',source:'nowave-landcover','source-layer':'hillshade',
      paint:{'fill-color':['match',['get','class'],'shadow','#766344','highlight','#E2CCA0','rgba(0,0,0,0)'],
        'fill-opacity':0.4},
    },firstWater?.id);
    if (!map.getSource('nowave-seafloor')) map.addSource('nowave-seafloor', {
      type:'raster',tiles:['/api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp'],
      tileSize:256,minzoom:0,maxzoom:6,attribution:'GEBCO 2026',
    });
    if (!map.getLayer('nowave-seafloor')) {
      const waterIndex=layers.findIndex(layer=>layer.id===firstWater?.id);
      map.addLayer({id:'nowave-seafloor',type:'raster',source:'nowave-seafloor',maxzoom:8,
        paint:{'raster-opacity':['interpolate',['linear'],['zoom'],0,1,6,1,8,0],
          'raster-fade-duration':250,'raster-resampling':'linear'}},layers[waterIndex+1]?.id);
    }
    if (map.getStyle().sources.composite?.type==='vector' && !map.getLayer('nowave-coastline')) {
      map.addLayer({id:'nowave-coastline',type:'line',source:'composite','source-layer':'water',
        paint:{'line-color':'#d8e4ed','line-width':['interpolate',['linear'],['zoom'],1,0.45,8,0.7],'line-opacity':0.45}});
    }
  },
};
