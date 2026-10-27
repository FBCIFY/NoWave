import "./notification-demo.css";
import { reportCategories } from "./data.js";
import { categories, categoryIcon as glyph } from "./report-categories.js";
import { alertExamples as examples } from "./alert-sonar.js";
import { createNotificationMap } from "./notification-map.js";

const categoryIcon = (report) =>
  `<span class="alerts-category" data-category="${report.category}">${glyph(categories.find((item) => item.value === report.category))}</span>`;
const bell =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg>';
const arrow =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m12 5-7 7 7 7M5 12h15"/></svg>';
const pin =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M19 10c0 5-7 11-7 11S5 15 5 10a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2.5"/></svg>';

export function createNotificationDemo(root, { world, onFocus }) {
  root.dataset.view = "list";
  root.innerHTML = `
    <div class="alerts-layout">
      <header class="alerts-heading">
        <div class="alerts-titlebar"><h2 id="alerts-title" tabindex="-1">Mes alertes</h2><span class="alerts-radius" aria-label="Rayon des alertes : 10 milles nautiques" title="Rayon des alertes">${bell}<strong>10 NM</strong></span></div>
        <p class="alerts-summary">Un signalement proche,<br><strong>une notification.</strong></p>
      </header>
      <ul class="alerts-history" aria-label="Exemples d’alertes à proximité">${examples.map((report, index) => `<li><button class="alerts-row" type="button" data-alert-action="open" data-alert-index="${index}">${categoryIcon(report)}<span class="alerts-row__copy"><strong>${reportCategories[report.category]}</strong><time datetime="${report.time}" aria-label="Aujourd’hui à ${report.time}">${report.time}</time></span><span class="alerts-row__distance">${report.distance}</span><span class="alerts-row__arrow" aria-hidden="true">›</span></button></li>`).join("")}</ul>
      <article class="alerts-detail" aria-labelledby="alerts-content-title" hidden></article>
    </div>`;
  const $ = (selector) => root.querySelector(selector);
  const list = $(".alerts-history"),
    detail = $(".alerts-detail"),
    header = $(".alerts-heading");
  let selected = null,
    opener = null,
    listScroll = 0;
  const chart = createNotificationMap((index) => openReport(index), world);

  function openReport(index, source) {
    const report = examples[index];
    if (!report) return;
    if (!list.hidden) listScroll = root.scrollTop;
    selected = index;
    opener = source || list.querySelector(`[data-alert-index="${index}"]`);
    header.hidden = true;
    list.hidden = true;
    detail.hidden = false;
    root.dataset.view = "detail";
    root.dataset.category = report.category;
    root.setAttribute("aria-labelledby", "alerts-content-title");
    detail.innerHTML = `
      <div class="alerts-detail__topbar"><button class="alerts-back" type="button" data-alert-action="back" aria-label="Retour aux alertes">${arrow}</button>
      <div class="alerts-detail__hero">${categoryIcon(report)}<h3 id="alerts-content-title" tabindex="-1">${reportCategories[report.category]}</h3></div></div>
      <p class="alerts-detail__description">${report.description}</p>
      <dl class="alerts-detail__facts">
        <div><dt>Aujourd’hui à</dt><dd><time datetime="${report.time}">${report.time}</time></dd></div>
        <div><dt>Distance</dt><dd>${report.distance}</dd></div>
        <div class="alerts-detail__location"><dt>Lieu</dt><dd>${pin}<span>${report.place}</span></dd></div>
      </dl>`;
    root.scrollTop = 0;
    chart.select(report);
    onFocus(report);
    $("#alerts-content-title").focus({ preventScroll: true });
  }
  function showExamples() {
    header.hidden = false;
    list.hidden = false;
    detail.hidden = true;
    root.dataset.view = "list";
    delete root.dataset.category;
    root.setAttribute("aria-labelledby", "alerts-title");
    onFocus();
    root.scrollTop = listScroll;
    const source = opener?.isConnected
      ? opener
      : list.querySelector(`[data-alert-index="${selected ?? 0}"]`);
    source?.focus({ preventScroll: true });
  }
  root.addEventListener("click", (event) => {
    const button = event.target.closest("[data-alert-action]");
    if (!button || !root.contains(button)) return;
    if (button.dataset.alertAction === "open")
      openReport(Number(button.dataset.alertIndex), button);
    if (button.dataset.alertAction === "back") showExamples();
  });
  root.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || detail.hidden) return;
    event.preventDefault();
    event.stopPropagation();
    showExamples();
  });
  return { setVisible: (value) => chart.setVisible(value) };
}
