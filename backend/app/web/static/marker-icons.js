/* Canvas adaptation of Flutter ReportCategoryGlyph, rendered once per style. */
window.NoWaveMarkerIcons = {
  install(map) {
    const colors={marine_animal:'#06B6D4',obstruction:'#F97316',pollution:'#7C3AED',unknown:'#64748B'};
    for (const [kind,color] of Object.entries(colors)) {
      const canvas=document.createElement('canvas');canvas.width=96;canvas.height=112;
      const c=canvas.getContext('2d');if(!c)return false;
      c.scale(2,2);
      c.shadowColor='rgba(0,0,0,.4)';c.shadowBlur=5;c.shadowOffsetY=2;
      c.beginPath();c.arc(24,28,18,0,Math.PI*2);c.fillStyle=color;c.fill();
      c.shadowColor='transparent';c.strokeStyle='rgba(255,255,255,.95)';c.lineWidth=1;c.stroke();
      c.save();c.translate(12,16);c.strokeStyle='#fff';c.fillStyle='#fff';
      c.lineWidth=1.8;c.lineJoin='round';c.lineCap='round';
      if(kind==='marine_animal') {
        // Same profile and control points as Flutter's _dolphin path.
        c.beginPath();c.moveTo(22.5,12.6);
        for(const p of [[21.5,12,20.5,11.9,19.8,11.6],[19.2,9.6,17.6,8.6,15.2,8.5],
          [14.4,7.2,13.2,5.6,11.4,5],[11.9,6.2,11.9,7.6,11.6,8.7],
          [8.6,9.3,6,11,4.4,13.6],[3.6,12.8,2.4,12.2,1.2,12.3],
          [2,13.6,2.8,14.6,3.6,15],[3,16,2.6,17.2,2.6,18.3],
          [3.9,17.6,4.9,16.6,5.4,15.4],[8.2,13.6,11.5,13.4,14.6,14.2],
          [14.2,15.4,13.4,16.6,12.4,17.2],[14.2,17.2,15.8,16.2,16.8,14.6],
          [18.8,14.4,20.8,13.6,22.5,12.6]])c.bezierCurveTo(...p);
        c.closePath();c.fill();c.beginPath();c.arc(18.4,11.2,.7,0,Math.PI*2);c.fillStyle=color;c.fill();
      } else if(kind==='obstruction') {
        c.beginPath();c.moveTo(12,3);c.lineTo(22,21);c.lineTo(2,21);c.closePath();c.stroke();
        c.beginPath();c.moveTo(12,9);c.lineTo(12,14);c.stroke();
        c.beginPath();c.arc(12,18,.9,0,Math.PI*2);c.fill();
      } else if(kind==='pollution') {
        c.beginPath();c.moveTo(12,2);c.bezierCurveTo(9,7,5,12,5,15);
        c.arc(12,15,7,Math.PI,0,true);c.bezierCurveTo(19,12,15,7,12,2);c.stroke();
      }
      if(kind==='unknown') { c.beginPath();c.arc(12,12,5,0,Math.PI*2);c.stroke(); }
      c.restore();map.addImage(`report-${kind}`,c.getImageData(0,0,96,112),{pixelRatio:2});
    }
    return true;
  },
};
