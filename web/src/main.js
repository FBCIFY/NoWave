import "./style.css";
import "./story.css";
import { spots, sources, reportCategories } from "./data.js";
import { journey } from "./story-data.js";
import { createWorld } from "./world.js";
import { createStory } from "./story.js";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
let motionPaused = motionPreference.matches;
let activeSpot = spots[0];
let exploreTrigger;

$("#ocean-story").style.setProperty(
  "--journey-distance",
  `${journey.length * 72}svh`,
);
$("#map-spots").innerHTML = spots
  .map(
    (spot) =>
      `<button class="map-spot asset-spot spot-${spot.id}" data-spot="${spot.id}" style="--x:${spot.x}%;--y:${spot.y}%;--size:${spot.size}px;--delay:-${Number(spot.number) * 0.8}s" aria-label="Découvrir : ${spot.label}"><img src="/assets/${spot.asset || spot.id}.webp" alt="" width="600" height="600" draggable="false" decoding="async" /></button>`,
  )
  .join("");
$("#story-narration").innerHTML = journey
  .map(
    (scene, i) =>
      `<article class="story-copy" id="story-${scene.id}" hidden><p class="eyebrow">${String(i + 1).padStart(2, "0")} / ${scene.theme}</p><h2>${scene.title.join("<br/>")}</h2><p>${scene.body}</p><p class="story-utility"><strong>Avec NoWave</strong>${scene.utility}</p><div class="story-links"><button data-report-demo="${scene.id}">Voir un exemple de signalement ↗</button>${scene.source ? `<a href="${sources[scene.source].url}" target="_blank" rel="noopener noreferrer">${sources[scene.source].label.split(" · ")[0]} ↗</a>` : ""}</div></article>`,
  )
  .join("");
$(".story-steps").innerHTML = [
  { id: "overview", label: "Vue d’ensemble" },
  ...journey,
]
  .map(
    (scene, i) =>
      `<button data-story-step="${i}" aria-label="${i === 0 ? "" : `Repère ${i} : `}${scene.label}" title="${scene.label}" ${i === 0 ? 'aria-current="step"' : ""}><span aria-hidden="true">${i === 0 ? "○" : String(i).padStart(2, "0")}</span></button>`,
  )
  .join("");
$("#recap-route").innerHTML = journey
  .map((scene, i) => {
    const spot = spots.find((s) => s.id === scene.id);
    return `<button data-story-step="${i + 1}"><img src="/assets/${spot.asset || spot.id}.webp" alt="" width="56" height="56" loading="lazy"/><span>${scene.label}</span><span aria-hidden="true">↗</span></button>`;
  })
  .join("");

function showSpot(id) {
  const spot = spots.find((item) => item.id === id);
  const scene = journey.find((item) => item.id === id);
  if (!spot || !scene) return;
  activeSpot = spot;
  $("#discovery-image").src = `/assets/${spot.asset || spot.id}.webp`;
  $("#discovery-image").alt = scene.label;
  $("#discovery-image").classList.toggle("island-art", id === "lighthouse");
  $("#discovery-art").style.backgroundColor = spot.color;
  $("#discovery-coordinates").textContent = "ILLUSTRATION NOWAVE";
  $("#discovery-category").textContent = scene.theme;
  $("#discovery-title").textContent = scene.title.join(" ");
  $("#discovery-description").textContent = scene.body;
  $("#discovery-reference").textContent = spot.reference;
  $("#discovery-takeaway").textContent = scene.utility;
  $("#discovery-sources").innerHTML = (spot.sources || [])
    .map(
      (key) =>
        `<a href="${sources[key].url}" target="_blank" rel="noopener noreferrer">${sources[key].label} ↗</a>`,
    )
    .join("");
  $("#discovery-progress").textContent =
    `${journey.indexOf(scene) + 1} / ${journey.length} repères`;
  if (!$("#discovery-dialog").open) $("#discovery-dialog").showModal();
}

function enterExplore(focus = true) {
  const wasExploring = $("#ocean").classList.contains("is-exploring");
  const bounds = $("#ocean").getBoundingClientRect();
  const outside =
    bounds.bottom < innerHeight / 2 || bounds.top > innerHeight / 2;
  if (outside) story.scrollToStep(0, true);
  if (!wasExploring) {
    exploreTrigger = document.activeElement;
    story.suspend(true);
    $("#ocean").classList.add("is-exploring");
    $("#exit-explore").hidden = false;
    $("#explore-heading").hidden = false;
    $(".hero-copy").inert = true;
    world.explore(true);
  }
  if (outside || (!wasExploring && $("#ocean").dataset.storyStep === "0"))
    world.overview();
  if (focus) $("#map-viewport").focus({ preventScroll: true });
}
function exitExplore() {
  $("#ocean").classList.remove("is-exploring");
  $("#exit-explore").hidden = true;
  $("#explore-heading").hidden = true;
  world.explore(false);
  story.suspend(false);
  const target =
    exploreTrigger?.isConnected && !exploreTrigger.closest("[inert]")
      ? exploreTrigger
      : $(".story-steps [aria-current]");
  target?.focus({ preventScroll: true });
}
const world = createWorld({
  viewport: $("#map-viewport"),
  world: $("#world"),
  onExplore: enterExplore,
  isMotionPaused: () => motionPaused,
});
const story = createStory({ world, isMotionPaused: () => motionPaused });

document.addEventListener("click", (event) => {
  const stepButton = event.target.closest("button[data-story-step]");
  if (stepButton) {
    if ($("#ocean").classList.contains("is-exploring")) exitExplore();
    story.scrollToStep(Number(stepButton.dataset.storyStep));
    if (!stepButton.closest("#ocean, .site-header")) {
      $(
        `.story-steps button[data-story-step="${stepButton.dataset.storyStep}"]`,
      )?.focus({ preventScroll: true });
    }
    return;
  }
  const reportButton = event.target.closest("[data-report-demo]");
  if (reportButton) {
    openReportDemo(reportButton.dataset.reportDemo);
    return;
  }
  const spotButton = event.target.closest("[data-spot]");
  if (spotButton) {
    showSpot(spotButton.dataset.spot);
    return;
  }
  if (event.target.closest("[data-explore]")) enterExplore();
  if (event.target.closest("[data-project]")) $("#project-dialog").showModal();
  if (event.target.closest("[data-close]"))
    event.target.closest("dialog").close();
});
$$("dialog").forEach((dialog) =>
  dialog.addEventListener("click", (event) => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (
      event.clientX < bounds.left ||
      event.clientX > bounds.right ||
      event.clientY < bounds.top ||
      event.clientY > bounds.bottom
    )
      dialog.close();
  }),
);
$("#exit-explore").addEventListener("click", exitExplore);
document.addEventListener("keydown", (event) => {
  if (
    event.key === "Escape" &&
    !document.querySelector("dialog[open]") &&
    $("#ocean").classList.contains("is-exploring")
  )
    exitExplore();
});
$("#next-discovery").addEventListener("click", () => {
  const index = journey.findIndex((scene) => scene.id === activeSpot.id);
  showSpot(journey[(index + 1) % journey.length].id);
});
$("#credits-button").addEventListener("click", () =>
  $("#credits-dialog").showModal(),
);
$("#project-explore").addEventListener("click", () => {
  $("#project-dialog").close();
  enterExplore();
});
function openReportDemo(id = activeSpot.id) {
  activeSpot = spots.find((spot) => spot.id === id) || activeSpot;
  $("#discovery-dialog").close();
  $("#report-form").hidden = false;
  $("#report-result").hidden = true;
  $("#report-category").value = activeSpot.reportCategory;
  $("#report-comment").value = "";
  $("#report-coordinates").textContent = activeSpot.coordinates;
  $("#report-dialog").showModal();
}
$("#open-report-demo").addEventListener("click", () => openReportDemo());
$("#report-form").addEventListener("submit", (event) => {
  event.preventDefault();
  $("#report-result-category").textContent =
    reportCategories[$("#report-category").value];
  $("#report-result-comment").textContent =
    $("#report-comment").value.trim() || "Aucun commentaire ajouté.";
  $("#report-result-coordinates").textContent =
    `Position fictive : ${activeSpot.coordinates} · Heure de l’exemple : ${new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}`;
  $("#report-form").hidden = true;
  $("#report-result").hidden = false;
  $("#report-edit").focus();
});
$("#report-edit").addEventListener("click", () => {
  $("#report-form").hidden = false;
  $("#report-result").hidden = true;
  $("#report-category").focus();
});
function updateMotion() {
  document.documentElement.classList.toggle("motion-paused", motionPaused);
  const button = $("#toggle-motion");
  button.setAttribute("aria-pressed", String(motionPaused));
  button.setAttribute(
    "aria-label",
    motionPaused ? "Activer les animations" : "Réduire les animations",
  );
  button.title = button.getAttribute("aria-label");
  button.innerHTML = motionPaused
    ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4l13 8-13 8z"/></svg>'
    : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14M16 5v14"/></svg>';
  story.refresh();
}
$("#toggle-motion").addEventListener("click", () => {
  motionPaused = !motionPaused;
  updateMotion();
});
motionPreference.addEventListener("change", (event) => {
  motionPaused = event.matches;
  updateMotion();
});
document.addEventListener("visibilitychange", () =>
  document.documentElement.classList.toggle("page-hidden", document.hidden),
);
updateMotion();
