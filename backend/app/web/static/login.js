(() => {
  const scene = document.querySelector('.login-scene');
  if (!scene) return;
  const password = document.getElementById('password');
  const toggle = document.getElementById('password-toggle');
  toggle.addEventListener('click', () => {
    password.type = password.type === 'password' ? 'text' : 'password';
    toggle.textContent = password.type === 'password' ? 'Afficher' : 'Masquer';
  });
  const status = document.getElementById('globe-status');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let focused = false, map = null, timer = null;
  function stop() { if (timer) clearTimeout(timer); timer = null; if (map) map.stop(); }
  function spin() {
    if (!map || timer || focused || reduced.matches) return;
    const center = map.getCenter();
    map.easeTo({center: [center.lng - 0.15, center.lat], duration: 1100, easing: t => t});
    timer = setTimeout(() => { timer = null; spin(); }, 1100);
  }
  for (const input of [document.getElementById('email'), password]) {
    input.addEventListener('focus', () => { focused = true; stop(); });
    input.addEventListener('blur', () => { focused = [document.getElementById('email'), password].includes(document.activeElement); if (!focused) spin(); });
  }
  reduced.addEventListener('change', () => { if (reduced.matches) stop(); else spin(); });
  if (!scene.dataset.token || !window.mapboxgl || !mapboxgl.supported()) {
    status.textContent = 'Globe indisponible. Le formulaire de connexion reste accessible.'; return;
  }
  mapboxgl.accessToken = scene.dataset.token;
  try {
    map = new mapboxgl.Map({container:'login-globe', style:'mapbox://styles/mapbox/dark-v11', projection:'globe', center:[-35,28], zoom:1.9, minZoom:1.4, maxZoom:2, interactive:false, attributionControl:false});
    map.on('style.load', () => { window.NoWaveMaritimeStyle.apply(map, {login: true}); spin(); });
    map.on('error', () => { status.textContent = 'Globe indisponible. Le formulaire reste accessible.'; });
  } catch (_) { status.textContent = 'Globe indisponible. Le formulaire reste accessible.'; }
})();
