import "./style.css";
import "./story.css";
import { demoReports, reportCategories } from "./data.js";
import { journey } from "./story-data.js";
import { createWorld } from "./world.js";
import { createStory } from "./story.js";
import { createMapView } from "./map-view.js";
import { createNotificationDemo } from "./notification-demo.js";
import { createReportComposer } from "./report-composer.js";

const $ = (selector) => document.querySelector(selector);
const motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
let motionPaused = motionPreference.matches;
let savedView = {};
try {
  const value = JSON.parse(
    sessionStorage.getItem("nowave.public-view") || "{}",
  );
  if (value && typeof value === "object") savedView = value;
} catch {
  /* Optional tab-local view memory. */
}

$("#ocean-story").style.setProperty(
  "--journey-distance",
  `${journey.length * 85}svh`,
);
function reportCard(id) {
  const report = demoReports[id];
  return `<button class="floating-report ${report.category}" data-report-demo="${id}"><span class="report-top"><span class="badge">${reportCategories[report.category]}</span><small>${report.place}</small></span><strong>${report.description}</strong><span class="report-byline"><span class="avatar">${report.author[0]}</span><span>${report.author}</span><time>${report.time}</time><span aria-hidden="true">↗</span></span></button>`;
}
$("#map-spots").innerHTML = journey
  .filter((scene) => scene.report)
  .map(
    (scene) =>
      `<div class="map-spot spot-${scene.id}" data-spot="${scene.id}" inert><div class="geo-anchor" data-geo="${scene.report}"><img class="scene-art" src="${scene.asset}" alt="" draggable="false" decoding="async" /><span class="geo-point"></span></div>${reportCard(scene.report)}</div>`,
  )
  .join("");
$("#story-narration").innerHTML = journey
  .map((scene) =>
    scene.id === "alerts"
      ? '<article id="story-alerts" hidden><section id="alertes" class="alerts-page" aria-labelledby="alerts-title"></section></article>'
      : `<article class="story-copy" id="story-${scene.id}" hidden><p class="eyebrow">${scene.theme}</p><h2>${scene.title.join("<br/>")}</h2>${scene.id === "obstacle" ? '<button class="text-link" data-compose>Signaler ↗</button>' : ""}</article>`,
  )
  .join("");
$(".story-steps").innerHTML = [{ label: "Accueil" }, ...journey]
  .map(
    (scene, i) =>
      `<button data-story-step="${i}" aria-label="${scene.label}" title="${scene.label}" ${i === 0 ? 'aria-current="step"' : ""}><span></span></button>`,
  )
  .join("");
const world = createWorld();
const alerts = createNotificationDemo($("#alertes"), {
  world,
  onFocus: (report) => story.focusReport(report),
});
const composer = createReportComposer($("#compose-dialog"));
const story = createStory({
  world,
  isMotionPaused: () => motionPaused,
  onStep: (state) => {
    const active = state.step === journey.length && state.opacity > 0.5;
    alerts.setVisible(active);
    document.title = active
      ? "Mes alertes · NoWave"
      : "NoWave — La mer, en commun.";
  },
});
const mapView = createMapView({ onReport: () => composer.open() });
let showingView = null;
let tourScroll = Number.isFinite(savedView.tourScroll)
  ? Math.max(0, savedView.tourScroll)
  : 0;
let alertsScroll = Number.isFinite(savedView.alertsScroll)
  ? Math.max(0, savedView.alertsScroll)
  : 0;
// The map hides the scrollable tour; restore its position after it is visible.
history.scrollRestoration = "manual";
function showView() {
  const nextView = location.hash.startsWith("#carte")
    ? "carte"
    : location.hash === "#alertes"
      ? "alertes"
      : "home";
  if (showingView === nextView) {
    if (nextView === "alertes") story.scrollToStep(journey.length);
    return;
  }
  if (showingView && showingView !== "carte") tourScroll = scrollY;
  if (showingView === "alertes") alertsScroll = $("#alertes").scrollTop;
  const previousView = showingView;
  showingView = nextView;
  story.setVisible(false);
  world.setVisible(false);
  if (nextView !== "carte") mapView.close();
  $("#ocean-story").hidden = nextView === "carte";
  $("#carte").hidden = nextView !== "carte";
  $(".footer").hidden = nextView === "carte";
  document.body.classList.toggle("map-page", nextView === "carte");
  scrollTo({
    top: nextView === "carte" ? 0 : tourScroll,
    behavior: "instant",
  });
  if (nextView === "carte") mapView.open();
  if (nextView !== "carte") {
    world.setVisible(true);
    story.setVisible(true);
  }
  $("#alertes").scrollTop = alertsScroll;
  if (nextView === "carte") alerts.setVisible(false);
  document.title =
    nextView === "alertes"
      ? "Mes alertes · NoWave"
      : "NoWave — La mer, en commun.";
  if (nextView === "alertes") story.scrollToStep(journey.length, !previousView);
  document.querySelectorAll(".main-nav a").forEach((link) => {
    const active =
      link.getAttribute("href") === (nextView === "carte" ? "#carte" : "#");
    if (active) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
  saveView();
}
function saveView() {
  if (showingView && showingView !== "carte") tourScroll = scrollY;
  if (showingView === "alertes") alertsScroll = $("#alertes").scrollTop;
  try {
    sessionStorage.setItem(
      "nowave.public-view",
      JSON.stringify({ tourScroll, alertsScroll }),
    );
  } catch {
    /* Navigation still works without storage. */
  }
}
let saveTimer;
function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveView, 120);
}
window.addEventListener("scroll", scheduleSave, { passive: true });
$("#alertes").addEventListener("scroll", scheduleSave, { passive: true });
window.addEventListener("pagehide", saveView);
function navigate(view) {
  const hash = view === "home" ? "#" : `#${view}`;
  if (location.hash !== hash && !(hash === "#" && location.hash === ""))
    history.pushState({}, "", hash);
  showView();
}
window.addEventListener("hashchange", showView);
window.addEventListener("popstate", showView);
showView();

document.addEventListener("click", (event) => {
  const anchor = event.target.closest(
    'a[href="#carte"], a[href="#alertes"], a[href="#"]',
  );
  if (anchor) {
    event.preventDefault();
    const href = anchor.getAttribute("href");
    navigate(href === "#" ? "home" : href.slice(1));
    if (href === "#") story.scrollToStep(0);
    return;
  }
  if (event.target.closest("[data-resume-tour]")) {
    navigate("home");
    return;
  }
  const step = event.target.closest("button[data-story-step]");
  if (step) {
    if (showingView !== "home") navigate("home");
    story.scrollToStep(Number(step.dataset.storyStep));
    return;
  }
  const report = event.target.closest("[data-report-demo]");
  if (report) {
    openReportDemo(report.dataset.reportDemo);
    return;
  }
  if (event.target.closest("[data-compose]")) composer.open();
  if (event.target.closest("[data-close]"))
    event.target.closest("dialog").close();
});
document.querySelectorAll("dialog").forEach((dialog) =>
  dialog.addEventListener("click", (event) => {
    if (event.target !== dialog) return;
    const rect = dialog.getBoundingClientRect();
    if (
      event.clientX < rect.left ||
      event.clientX > rect.right ||
      event.clientY < rect.top ||
      event.clientY > rect.bottom
    )
      dialog.close();
  }),
);
function openReportDemo(id) {
  const report = demoReports[id];
  if (!report) return;
  $("#report-category").textContent = reportCategories[report.category];
  $("#report-category").className = `badge ${report.category}`;
  $("#report-comment").textContent = report.description;
  $("#report-author").textContent = report.author;
  $("#report-time").textContent = report.time;
  $("#report-place").textContent = report.place;
  $("#report-history").textContent =
    `${report.time} · Publié par ${report.author}`;
  $("#report-dialog").showModal();
}
function updateMotion() {
  document.documentElement.classList.toggle("motion-paused", motionPaused);
  story.refresh();
}
motionPreference.addEventListener("change", (event) => {
  motionPaused = event.matches;
  updateMotion();
});
document.addEventListener("visibilitychange", () =>
  document.documentElement.classList.toggle("page-hidden", document.hidden),
);
updateMotion();
