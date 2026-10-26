import "./map-view.css";
import { reportCategories } from "./data.js";
import { categories, categoryIcon } from "./report-categories.js";
import { createMaritimeMap } from "./maritime-map.js";
import {
  normalizeObservation,
  observationsUrl,
  observationPageSize,
} from "./map-observations.js";

const icons = {
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${icons[name]}</svg>`;
const reducedMotion = () =>
  matchMedia("(prefers-reduced-motion: reduce)").matches;
const dateFormat = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});
const timeFormat = new Intl.DateTimeFormat("fr-FR", {
  hour: "2-digit",
  minute: "2-digit",
});
function observationTime(value) {
  const date = new Date(value);
  return date.toDateString() === new Date().toDateString()
    ? timeFormat.format(date)
    : dateFormat.format(date);
}

// The public and administrative views render the same category glyphs.
function markerImages() {
  const images = {};
  window.NoWaveMarkerIcons.install({
    addImage(name, image) {
      const canvas = document.createElement("canvas");
      canvas.width = image.width;
      canvas.height = image.height;
      canvas.getContext("2d").putImageData(image, 0, 0);
      images[name] = canvas.toDataURL();
    },
  });
  return images;
}

export function createMapView({
  admin = false,
  onSelectReport = () => {},
} = {}) {
  const root = document.querySelector("#carte");
  root.innerHTML = `
    <div id="navigation-map" class="map-view__surface" aria-label="Carte maritime"></div>
    <div class="map-view__topbar">
      <button type="button" class="map-view__list-toggle" aria-expanded="true" aria-controls="map-observation-list" hidden>${icon("list")}<span>Observations</span></button>
    </div>
    <p class="map-view__source-label">Observations actives</p>
    <div class="map-view__controls" role="group" aria-label="Commandes de la carte">
      <button type="button" data-map-control="in" aria-label="Zoom avant" title="Zoom avant" disabled>+</button>
      <button type="button" data-map-control="out" aria-label="Zoom arrière" title="Zoom arrière" disabled>−</button>
      <button type="button" data-map-control="reset" aria-label="Revenir à la vue du globe" title="Vue du globe" disabled hidden>${icon("globe")}</button>
    </div>
    <div class="map-view__panel map-view__workspace">
    <aside id="map-observation-list" class="map-view__feed" aria-labelledby="map-list-title">
      <div class="map-view__panel-head"><h2 id="map-list-title" tabindex="-1">Observations <span class="map-view__count" aria-live="polite" aria-atomic="true" hidden></span></h2><button type="button" class="map-view__close" data-map-close="list" aria-label="Masquer les observations">${icon("close")}</button></div>
      <details class="map-view__filter-menu"><summary>Filtrer</summary><div class="map-view__filters">
        <input id="map-report-search" type="search" maxlength="120" aria-label="Rechercher une observation par description ou pseudo" placeholder="Rechercher une observation" autocomplete="off">
        <input id="map-report-category" type="hidden" value="">
        <div class="map-view__category-items" role="group" aria-label="Filtrer par catégorie">${categories.map((category) => `<button type="button" data-map-category="${category.value}" aria-pressed="false">${categoryIcon(category)}<span>${category.label}</span></button>`).join("")}</div>
      </div></details>
      <p class="map-view__result-status" role="status" aria-live="polite"></p>
      <ul class="map-view__list" aria-label="Observations actives, des plus récentes aux plus anciennes"></ul>
      <nav class="map-view__pagination" aria-label="Pages des observations" hidden><button type="button" data-map-page="previous">Précédent</button><span class="map-view__page-number" aria-live="polite"></span><button type="button" data-map-page="next">Suivant</button></nav>
      <button type="button" class="map-view__retry" hidden>Réessayer</button>
    </aside>
    <article class="map-view__detail" aria-labelledby="map-report-title" hidden>
      <div class="map-view__panel-head"><button type="button" class="map-view__back" data-map-back>← Observations</button></div>
      <h2 id="map-report-title" tabindex="-1"></h2>
      <p class="map-view__description"></p>
      <div class="map-view__byline"><span class="map-view__author"></span><time></time></div>
    </article>
    </div>
    <p class="map-view__data-status" role="status" aria-live="polite"></p>
    <p id="navigation-status" class="map-view__status" role="status" aria-live="polite"></p>`;

  const $ = (selector) => root.querySelector(selector);
  const workspace = $(".map-view__workspace");
  const listPanel = $("#map-observation-list"),
    detail = $(".map-view__detail");
  const listToggle = $(".map-view__list-toggle"),
    status = $("#navigation-status");
  const searchInput = $("#map-report-search"),
    categoryInput = $("#map-report-category");
  const controls = [...root.querySelectorAll("[data-map-control]")];
  let chart,
    images,
    returnFocus,
    selectedReport = null;
  let active = false,
    overviewMode = true,
    followSelection = false;
  let measuredWidth = 0,
    measuredHeight = 0;
  let reports = new Map(),
    markers = [];
  let request,
    requestVersion = 0,
    queryTimer,
    refreshTimer;
  let queryUrl = "",
    nextCursor = null,
    hasMore = false,
    loading = false,
    failed = false,
    preview = false;
  let pageIndex = 0,
    pageCursors = [null];

  function globeView() {
    const padding = mapPadding();
    return {
      ...window.NoWaveMapCore.overview(
        root.clientWidth - padding.left,
        root.clientHeight,
      ),
      padding,
    };
  }
  function mapPadding() {
    return {
      top: 0,
      right: 0,
      bottom: 0,
      left:
        root.clientWidth > 760 && !workspace.hidden
          ? Math.min(
              workspace.getBoundingClientRect().right + 24,
              root.clientWidth / 2,
            )
          : 0,
    };
  }
  function leaveOverview() {
    overviewMode = false;
    followSelection = false;
    $('[data-map-control="reset"]').hidden = false;
  }
  function updateMarkers() {
    if (!chart?.ready) return;
    const map = chart.map,
      center = map.getCenter(),
      radians = Math.PI / 180;
    const latitude = center.lat * radians;
    for (const { id, marker, location } of markers) {
      const element = marker.getElement(),
        pointLatitude = location[1] * radians;
      const dot =
        Math.sin(latitude) * Math.sin(pointLatitude) +
        Math.cos(latitude) *
          Math.cos(pointLatitude) *
          Math.cos((location[0] - center.lng) * radians);
      element.hidden = map.getZoom() < 6 && dot <= 0;
      element.setAttribute(
        "aria-pressed",
        String(selectedReport?.id === id && !detail.hidden),
      );
    }
  }
  function closeDetail(restoreFocus = true) {
    const reopen = restoreFocus || !detail.hidden;
    detail.hidden = true;
    delete detail.dataset.reportId;
    followSelection = false;
    if (reopen) listPanel.hidden = false;
    workspace.hidden = listPanel.hidden;
    listToggle.hidden = !listPanel.hidden;
    listToggle.setAttribute("aria-expanded", String(!listPanel.hidden));
    layout(true);
    updateMarkers();
    if (restoreFocus) {
      renderState();
      const target =
        returnFocus?.isConnected && !returnFocus.closest("[hidden]")
          ? returnFocus
          : $("#map-list-title");
      target.focus({ preventScroll: true });
    }
  }
  function setList(open) {
    listPanel.hidden = !open;
    listToggle.setAttribute("aria-expanded", String(open));
    listToggle.hidden = open || !detail.hidden;
    if (open) closeDetail(false);
    workspace.hidden = listPanel.hidden && detail.hidden;
    layout(true);
  }
  function flyToReport(report, animate = true) {
    if (!chart?.ready || !report?.location) return;
    chart.map.resize();
    const mobile = root.clientWidth <= 760,
      immediate = !animate || reducedMotion();
    const pointY = Math.max(40, workspace.getBoundingClientRect().top - 48);
    chart.map[immediate ? "easeTo" : "flyTo"]({
      center: report.location,
      zoom: 7.2,
      pitch: 0,
      bearing: 0,
      padding: mapPadding(),
      offset: mobile ? [0, pointY - root.clientHeight / 2] : [0, 0],
      duration: immediate ? 0 : 1400,
      essential: false,
    });
  }
  function selectReport(id, trigger, suppliedReport) {
    const report = suppliedReport || reports.get(id);
    if (!report || (!admin && report.expiresAt <= Date.now())) return;
    selectedReport = report;
    leaveOverview();
    followSelection = true;
    returnFocus = trigger;
    setList(false);
    $("#map-report-title").textContent = reportCategories[report.category];
    $(".map-view__description").textContent =
      report.description || "Aucune précision ajoutée.";
    $(".map-view__author").textContent = report.author || "Communauté NoWave";
    $(".map-view__byline time").textContent = dateFormat.format(
      new Date(report.observedAt),
    );
    $(".map-view__byline time").dateTime = report.observedAt;
    detail.hidden = false;
    detail.dataset.reportId = report.id;
    workspace.hidden = false;
    listToggle.hidden = true;
    updateMarkers();
    flyToReport(report);
    $("#map-report-title").focus({ preventScroll: true });
    onSelectReport({ report, container: detail });
  }

  function renderReports() {
    const list = $(".map-view__list"),
      fragment = document.createDocumentFragment();
    for (const report of reports.values()) {
      const item = document.createElement("li"),
        button = document.createElement("button");
      button.type = "button";
      button.dataset.mapReport = report.id;
      button.dataset.category = report.category;
      const label = document.createElement("span");
      label.className = "map-view__list-category";
      label.textContent = reportCategories[report.category];
      const time = document.createElement("time");
      time.dateTime = report.observedAt;
      time.textContent = observationTime(report.observedAt);
      time.title = dateFormat.format(new Date(report.observedAt));
      const meta = document.createElement("span");
      meta.className = "map-view__list-meta";
      meta.append(label, time);
      const description = document.createElement("strong");
      description.textContent =
        report.description || "Observation sans précision";
      button.append(meta, description);
      button.addEventListener("click", () => selectReport(report.id, button));
      item.append(button);
      fragment.append(item);
    }
    list.replaceChildren(fragment);
    markers.forEach(({ marker }) => marker.remove());
    markers = [];
    if (chart?.ready && images)
      for (const report of reports.values()) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "map-view__marker";
        button.dataset.mapReport = report.id;
        button.setAttribute(
          "aria-label",
          `${reportCategories[report.category]}${report.description ? ` · ${report.description}` : ""}`,
        );
        // All loaded observations are keyboard accessible through the list.
        button.tabIndex = -1;
        const image = document.createElement("img");
        image.src = images[`report-${report.category}`];
        image.alt = "";
        image.draggable = false;
        button.append(image);
        button.addEventListener("click", () => selectReport(report.id, button));
        const marker = new window.mapboxgl.Marker({
          element: button,
          anchor: "center",
          occludedOpacity: 0,
        })
          .setLngLat(report.location)
          .addTo(chart.map);
        markers.push({ id: report.id, marker, location: report.location });
      }
    updateMarkers();
    renderState();
  }
  function renderState() {
    const count = reports.size;
    $(".map-view__count").textContent = String(count);
    $(".map-view__count").hidden = (loading || failed) && !count;
    $(".map-view__count").setAttribute(
      "aria-label",
      `${count} observations sur cette page`,
    );
    $(".map-view__source-label").textContent = preview
      ? "Aperçu · Données fictives"
      : "Observations actives";
    const message = loading
      ? "Chargement des observations…"
      : failed
        ? "Les observations sont momentanément indisponibles."
        : !count
          ? "Aucune observation active."
          : "";
    $(".map-view__result-status").textContent = message;
    $(".map-view__data-status").textContent =
      !listPanel.hidden || count ? "" : message;
    $(".map-view__pagination").hidden = pageIndex === 0 && !hasMore;
    $('[data-map-page="previous"]').disabled = loading || pageIndex === 0;
    $('[data-map-page="next"]').disabled = loading || !hasMore || failed;
    $(".map-view__page-number").textContent = `Page ${pageIndex + 1}`;
    const filters =
      Number(Boolean(searchInput.value.trim())) +
      Number(Boolean(categoryInput.value));
    $(".map-view__filter-menu summary").textContent = filters
      ? `Filtrer (${filters})`
      : "Filtrer";
    root
      .querySelectorAll("[data-map-category]")
      .forEach((button) =>
        button.setAttribute(
          "aria-pressed",
          String(button.dataset.mapCategory === categoryInput.value),
        ),
      );
    $(".map-view__retry").hidden = !failed;
    $(".map-view__retry").disabled = loading;
    $(".map-view__list").setAttribute("aria-busy", String(loading));
  }
  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    if (!active) return;
    const nextExpiry = Math.min(
      ...[...reports.values()].map((report) => report.expiresAt),
      Date.now() + 60000,
    );
    refreshTimer = setTimeout(
      () => {
        for (const [id, report] of reports)
          if (report.expiresAt <= Date.now()) reports.delete(id);
        if (!admin && selectedReport?.expiresAt <= Date.now())
          closeDetail(false);
        renderReports();
        loadObservations();
      },
      Math.max(100, nextExpiry - Date.now()),
    );
  }
  async function loadObservations() {
    if (!active) return;
    clearTimeout(queryTimer);
    clearTimeout(refreshTimer);
    request?.abort();
    const version = ++requestVersion;
    const controller = new AbortController();
    request = controller;
    const timeout = setTimeout(() => controller.abort(), 10000);
    const url = observationsUrl({
      category: categoryInput.value,
      query: searchInput.value,
      cursor: pageCursors[pageIndex],
    });
    if (url !== queryUrl) {
      reports = new Map();
      nextCursor = null;
      hasMore = false;
      renderReports();
    }
    queryUrl = url;
    loading = true;
    failed = false;
    renderState();
    try {
      const response = await fetch(url, {
        credentials: "omit",
        cache: "no-store",
        signal: controller.signal,
      });
      if (!response.ok) throw new Error("Observations unavailable");
      const data = await response.json();
      if (version !== requestVersion || !active) return;
      if (!Array.isArray(data.items)) throw new Error("Invalid observations");
      const next = new Map();
      // A bounded page keeps both the list and its markers lightweight.
      // The API's keyset order is already newest first.
      for (const item of data.items.slice(0, observationPageSize)) {
        const report = normalizeObservation(item);
        if (report) next.set(report.id, report);
      }
      reports = next;
      preview = response.headers.has("X-NoWave-Preview");
      nextCursor =
        typeof data.next_cursor === "string" ? data.next_cursor : null;
      hasMore = Boolean(data.has_more && nextCursor);
      if (
        !admin &&
        selectedReport &&
        !detail.hidden &&
        !reports.has(selectedReport.id)
      )
        closeDetail(false);
      renderReports();
    } catch {
      if (version !== requestVersion || !active) return;
      failed = true;
    } finally {
      clearTimeout(timeout);
      if (version === requestVersion && active) {
        loading = false;
        renderState();
        scheduleRefresh();
      }
    }
  }
  function scheduleQuery() {
    if (!active) return;
    request?.abort();
    ++requestVersion;
    pageIndex = 0;
    pageCursors = [null];
    loading = true;
    renderState();
    clearTimeout(queryTimer);
    queryTimer = setTimeout(() => loadObservations(), 350);
  }

  function init() {
    if (chart) return;
    chart = createMaritimeMap({
      container: "navigation-map",
      status,
      interactive: true,
      demonstration: false,
      initialView: globeView,
      projection: "globe",
      onLoading() {
        controls.forEach((button) => {
          button.disabled = true;
        });
        markers.forEach(({ marker }) => marker.remove());
        markers = [];
      },
      onReady(map) {
        images = markerImages();
        renderReports();
        map.on("render", updateMarkers);
        controls.forEach((button) => {
          button.disabled = false;
        });
        map
          .getCanvas()
          .setAttribute(
            "aria-label",
            "Carte maritime. Flèches pour déplacer, plus et moins pour zoomer. Observations accessibles dans la liste.",
          );
        chart.setInteractive(active);
        map.on("movestart", (event) => {
          if (event.originalEvent) leaveOverview();
        });
        layout(true);
        status.textContent = "";
      },
    });
  }
  listToggle.addEventListener("click", () => {
    setList(listPanel.hidden);
    renderState();
    if (!listPanel.hidden)
      ($(".map-view__list button") || $("#map-list-title")).focus({
        preventScroll: true,
      });
  });
  searchInput.addEventListener("input", scheduleQuery);
  categoryInput.addEventListener("change", () => {
    closeDetail(false);
    pageIndex = 0;
    pageCursors = [null];
    loadObservations();
  });
  $('[data-map-page="previous"]').addEventListener("click", () => {
    if (loading || pageIndex === 0) return;
    pageIndex--;
    loadObservations();
  });
  $('[data-map-page="next"]').addEventListener("click", () => {
    if (loading || !hasMore || !nextCursor) return;
    pageCursors = [...pageCursors.slice(0, pageIndex + 1), nextCursor];
    pageIndex++;
    loadObservations();
  });
  $(".map-view__retry").addEventListener("click", () => loadObservations());
  root.addEventListener("click", (event) => {
    const category = event.target.closest("[data-map-category]");
    if (category) {
      categoryInput.value =
        category.dataset.mapCategory !== categoryInput.value
          ? category.dataset.mapCategory
          : "";
      categoryInput.dispatchEvent(new Event("change"));
      renderState();
    }
    if (event.target.closest("[data-map-back]")) closeDetail();
    const close = event.target.closest("[data-map-close]");
    if (close?.dataset.mapClose === "list") {
      setList(false);
      renderState();
      listToggle.focus({ preventScroll: true });
    } else if (close) closeDetail();
    const action =
      event.target.closest("[data-map-control]")?.dataset.mapControl;
    if (!action || !chart?.ready) return;
    const duration = reducedMotion() ? 0 : 300;
    if (action === "in" || action === "out") leaveOverview();
    if (action === "in") chart.map.zoomIn({ duration });
    if (action === "out") chart.map.zoomOut({ duration });
    if (action === "reset") {
      selectedReport = null;
      closeDetail(false);
      overviewMode = true;
      $('[data-map-control="reset"]').hidden = true;
      chart.map.getCanvas().focus({ preventScroll: true });
      const view = globeView();
      chart.map.flyTo({
        center: [view.x, view.y],
        zoom: view.zoom,
        pitch: 0,
        bearing: 0,
        padding: view.padding,
        duration: reducedMotion() ? 0 : 1200,
      });
    }
  });
  root.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (!detail.hidden) closeDetail();
    else if (!listPanel.hidden) {
      setList(false);
      renderState();
      listToggle.focus({ preventScroll: true });
    } else return;
    event.preventDefault();
    event.stopPropagation();
  });
  function layout(force = false) {
    if (!active || !chart?.map) return;
    const width = root.clientWidth,
      height = root.clientHeight;
    if (!force && width === measuredWidth && height === measuredHeight) return;
    measuredWidth = width;
    measuredHeight = height;
    chart.map.resize();
    if (!chart.ready) return;
    if (overviewMode) {
      const view = globeView();
      chart.map.jumpTo({
        center: [view.x, view.y],
        zoom: view.zoom,
        pitch: 0,
        bearing: 0,
        padding: view.padding,
      });
    } else if (followSelection && selectedReport && !detail.hidden)
      flyToReport(selectedReport, false);
    else chart.map.jumpTo({ padding: mapPadding() });
  }
  new ResizeObserver(() => layout()).observe(root);
  return {
    showReport(report) {
      selectReport(report.id, null, report);
    },
    open() {
      active = true;
      init();
      chart.setInteractive(true);
      layout(true);
      loadObservations();
    },
    close() {
      active = false;
      ++requestVersion;
      request?.abort();
      clearTimeout(queryTimer);
      clearTimeout(refreshTimer);
      chart?.map?.stop();
      chart?.setInteractive(false);
    },
  };
}
