/* Shared place search. Results stay transient and are only shown on Mapbox. */
(() => {
  let sequence = 0;
  const svg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></svg>';
  function mount({ container, map, token, onSelect = () => {} }) {
    const root = typeof container === 'string' ? document.querySelector(container) : container;
    if (!root || !map) return { destroy() {} };
    const id = `chart-place-${++sequence}`;
    root.classList.add('chart-search');
    root.innerHTML = `<form class="chart-search__form" role="search"><input type="search" maxlength="120" placeholder="Rechercher un lieu" aria-label="Rechercher un lieu" autocomplete="off" spellcheck="false" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="${id}"><button type="submit" aria-label="Rechercher">${svg}</button></form><div class="chart-search__results" hidden><ul id="${id}" role="listbox" aria-label="Lieux trouvés"></ul><p role="status" aria-live="polite"></p><small>© Mapbox</small></div>`;
    const form = root.querySelector('form'), input = root.querySelector('input');
    const results = root.querySelector('.chart-search__results'), list = root.querySelector('ul'), status = root.querySelector('[role="status"]');
    let timer, request, destroyed = false, features = [], active = -1;
    function close() {
      cancel();
      results.hidden = true;
      input.setAttribute('aria-expanded', 'false');
      input.removeAttribute('aria-activedescendant');
      active = -1;
    }
    function show() { results.hidden = false; input.setAttribute('aria-expanded', 'true'); }
    function cancel() { clearTimeout(timer); request?.abort(); request = null; }
    function choose(index) {
      const feature = features[index];
      if (!feature) return;
      cancel(); close(); input.value = feature.label;
      onSelect(feature);
      const duration = matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 900;
      map.stop();
      if (feature.bbox) map.fitBounds([[feature.bbox[0], feature.bbox[1]], [feature.bbox[2], feature.bbox[3]]], { padding: 60, maxZoom: 11.5, duration });
      else map.flyTo({ center: feature.center, zoom: 10, bearing: 0, pitch: 0, duration });
      input.focus({ preventScroll: true });
    }
    function highlight(index) {
      if (!features.length) return;
      active = (index + features.length) % features.length;
      [...list.children].forEach((node, i) => node.setAttribute('aria-selected', String(i === active)));
      input.setAttribute('aria-activedescendant', list.children[active].id);
      list.children[active].scrollIntoView({ block: 'nearest' });
    }
    async function search() {
      cancel();
      const query = input.value.trim().replaceAll(';', ' ').split(/\s+/).slice(0, 20).join(' ');
      features = []; active = -1; list.replaceChildren();
      input.removeAttribute('aria-activedescendant');
      if (query.length < 3) { close(); return; }
      show(); status.textContent = 'Recherche…';
      if (!token?.startsWith('pk.')) { status.textContent = 'Recherche indisponible.'; return; }
      const current = request = new AbortController();
      const timeout = setTimeout(() => current.abort(), 8000);
      try {
        const url = new URL('https://api.mapbox.com/search/geocode/v6/forward');
        url.search = new URLSearchParams({ q: query, access_token: token, language: 'fr', limit: '5', autocomplete: 'true' });
        const response = await fetch(url, { signal: current.signal, credentials: 'omit' });
        if (!response.ok) throw Error('Unavailable');
        const data = await response.json();
        if (destroyed || request !== current) return;
        features = (Array.isArray(data?.features) ? data.features : []).flatMap(feature => {
          if (!feature || typeof feature !== 'object') return [];
          const center = feature.geometry?.coordinates;
          if (feature.geometry?.type !== 'Point' || !Array.isArray(center) || center.length < 2 || !center.every(Number.isFinite) || Math.abs(center[0]) > 180 || Math.abs(center[1]) > 85) return [];
          const p = feature.properties || {};
          const label = p.full_address || [p.name, p.place_formatted].filter(Boolean).join(', ');
          if (typeof label !== 'string' || !label) return [];
          const raw = feature.bbox;
          const bbox = Array.isArray(raw) && raw.length === 4 && raw.every(Number.isFinite) && raw[0] < raw[2] && raw[1] < raw[3] && Math.abs(raw[0]) <= 180 && Math.abs(raw[2]) <= 180 && Math.abs(raw[1]) <= 85 && Math.abs(raw[3]) <= 85 ? raw : null;
          return [{ center: center.slice(0, 2), label, bbox }];
        }).slice(0, 5);
        features.forEach((feature, index) => {
          const row = document.createElement('li');
          row.id = `${id}-${index}`; row.setAttribute('role', 'option'); row.setAttribute('aria-selected', 'false');
          row.textContent = feature.label;
          row.addEventListener('pointerdown', event => event.preventDefault());
          row.addEventListener('click', () => choose(index));
          list.append(row);
        });
        status.textContent = features.length ? '' : 'Aucun lieu trouvé.';
      } catch {
        if (!destroyed && request === current) status.textContent = 'Recherche indisponible. Réessayez.';
      } finally { clearTimeout(timeout); }
    }
    const onInput = () => { cancel(); close(); features = []; list.replaceChildren(); timer = setTimeout(search, 400); };
    const onSubmit = event => { event.preventDefault(); if (active >= 0) choose(active); else search(); };
    const onKey = event => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); cancel(); close(); }
      else if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && features.length) { event.preventDefault(); show(); highlight(active + (event.key === 'ArrowDown' ? 1 : -1)); }
    };
    const outside = event => { if (!root.contains(event.target)) { cancel(); close(); } };
    input.addEventListener('input', onInput); input.addEventListener('keydown', onKey);
    form.addEventListener('submit', onSubmit);
    document.addEventListener('pointerdown', outside);
    const blur = event => { if (!root.contains(event.relatedTarget)) { cancel(); close(); } };
    root.addEventListener('focusout', blur);
    return { close, destroy() { destroyed = true; cancel(); input.removeEventListener('input', onInput); input.removeEventListener('keydown', onKey); form.removeEventListener('submit', onSubmit); root.removeEventListener('focusout', blur); document.removeEventListener('pointerdown', outside); root.replaceChildren(); } };
  }
  window.NoWaveMapSearch = Object.freeze({ mount });
})();
