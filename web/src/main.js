import "./style.css";
import "./story.css";
import { spots, reportCategories } from "./data.js";
import { journey } from "./story-data.js";
import { createWorld } from "./world.js";
import { createStory } from "./story.js";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
let motionPaused = motionPreference.matches;
let activeSpot = spots[0];

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
      `<article class="story-copy" id="story-${scene.id}" hidden><p class="eyebrow">${String(i + 1).padStart(2, "0")} / ${scene.theme}</p><h2>${scene.title.join("<br/>")}</h2><p>${scene.body}</p><p class="story-utility"><strong>Avec NoWave</strong>${scene.utility}</p><div class="story-links"><button data-report-demo="${scene.id}">Voir un exemple de signalement</button></div></article>`,
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
    return `<button data-story-step="${i + 1}"><img src="/assets/${spot.asset || spot.id}.webp" alt="" width="56" height="56" loading="lazy"/><span>${scene.label}</span></button>`;
  })
  .join("");

const world = createWorld({ world: $("#world") });
const story = createStory({ world, isMotionPaused: () => motionPaused });

document.addEventListener("click", (event) => {
  const stepButton = event.target.closest("button[data-story-step]");
  if (stepButton) {
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
$("#project-journey").addEventListener("click", () => {
  $("#project-dialog").close();
  story.scrollToStep(1);
});
function openReportDemo(id = activeSpot.id) {
  activeSpot = spots.find((spot) => spot.id === id) || activeSpot;
  const examples = {
    obstruction:
      "Objet flottant aperçu à proximité de la zone de navigation. Rester vigilant à l’approche.",
    marine_animal:
      "Présence d’un animal marin observée dans le secteur. Garder ses distances et ralentir.",
    pollution:
      "Déchets flottants observés en surface, dispersés dans le secteur.",
  };
  $("#report-category").textContent =
    reportCategories[activeSpot.reportCategory];
  $("#report-comment").textContent = examples[activeSpot.reportCategory];
  $("#report-coordinates").textContent = activeSpot.coordinates;
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
