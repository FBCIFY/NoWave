import "./notification-demo.css";
import { demoReports, reportCategories } from "./data.js";

// An interactive illustration of the current app. No push permission, account
// preference or server history is changed by this public demonstration.
const examples = [
  ["container", "1,2 NM"],
  ["whale", "2,4 NM"],
  ["duck", "3,8 NM"],
].map(([key, distance]) => ({
  ...demoReports[key],
  distance,
  description:
    key === "container"
      ? "Un conteneur à la dérive au large de Madère."
      : demoReports[key].description,
}));
const paths = {
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M9 21h6"/>',
  obstruction:
    '<path d="m7 5 10-1 1 10-10 1zM3 19c2-2 4 2 6 0s4 2 6 0 4 2 6 0"/>',
  marine_animal:
    '<path d="M3 10c2-3 5-4 8-3 4 1 5 5 7 5 1-3 3-3 4-2-1 1-1 4-4 5-5 3-12 2-15-2zM11 7V4m0 0 2-1"/>',
  pollution:
    '<path d="M12 3c-2 4-6 7-6 11a6 6 0 0 0 12 0c0-4-4-7-6-11zM9 14c0 2 1 3 3 3"/>',
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
const categoryIcon = (report) =>
  `<span class="alerts-category" data-category="${report.category}">${icon(report.category)}</span>`;

export function createNotificationDemo(root) {
  root.innerHTML = `
    <div class="alerts-sonar" aria-hidden="true">
      <svg viewBox="0 0 800 600" fill="none">
        <path d="m630 0 18 60-35 40 30 46-12 45 45 24 24-30 55 20 45-17V0Z" fill="#284453" opacity=".3"/>
        <path d="m410 220 185 105" stroke="#9bb6c4" stroke-opacity=".15" stroke-dasharray="3 8"/>
        <g class="sonar-waves" stroke="#c48383" stroke-width="1"><circle class="sonar-wave" cx="410" cy="220" r="52"/><circle class="sonar-wave" cx="410" cy="220" r="52"/><circle class="sonar-wave" cx="410" cy="220" r="52"/></g>
        <circle cx="410" cy="220" r="5" fill="#c48383"/>
        <circle class="sonar-user-ring" cx="595" cy="325" r="18" stroke="#8bbac6"/>
        <circle cx="595" cy="325" r="5" fill="#8bbac6"/>
        <text x="410" y="198" text-anchor="middle">Signalement</text><text x="595" y="357" text-anchor="middle">Vous</text>
      </svg>
    </div>
    <div class="alerts-layout">
      <button class="alerts-return" type="button" data-resume-tour>← Retour au parcours</button>
      <header class="alerts-heading"><h1 id="alerts-title" tabindex="-1">Mes alertes</h1><div class="alerts-activation"><p>Recevoir les alertes dans un rayon de <strong>10 NM</strong></p><button class="alerts-switch" type="button" role="switch" aria-label="Recevoir les alertes" aria-checked="true" aria-describedby="alerts-setting-status" data-alert-action="toggle"><span></span></button></div><p class="alerts-setting-status" id="alerts-setting-status" role="status">Alertes activées</p></header>
      <div class="alerts-columns">
        <section class="alerts-content" aria-labelledby="alerts-content-title">
          <header class="alerts-content__heading"><button class="alerts-back" type="button" data-alert-action="back" aria-label="Retour à l’historique" hidden>←</button><h2 id="alerts-content-title" tabindex="-1">Historique</h2><span class="alerts-history-count">3</span></header>
          <ul class="alerts-history" aria-label="Historique des alertes, les plus récentes en premier">${examples.map((report, index) => `<li><button class="alerts-row" type="button" data-alert-action="open" data-alert-index="${index}">${categoryIcon(report)}<span class="alerts-row__copy"><strong>${reportCategories[report.category]}</strong><span>${report.description}</span><small>Aujourd’hui à ${report.time}</small></span><span class="alerts-row__distance">${report.distance}</span><span class="alerts-row__arrow" aria-hidden="true">›</span></button></li>`).join("")}</ul>
          <article class="alerts-detail" hidden></article>
        </section>
      </div>
      <p class="alerts-demo-note">Démonstration · aucun envoi</p>
    </div>`;
  const $ = (selector) => root.querySelector(selector);
  const toggle = $(".alerts-switch"),
    status = $(".alerts-setting-status");
  const history = $(".alerts-history"),
    detail = $(".alerts-detail"),
    heading = $("#alerts-content-title"),
    back = $(".alerts-back");
  let enabled = true,
    selected = null,
    opener = null;
  function openReport(index, source) {
    const report = examples[index];
    if (!report) return;
    selected = index;
    opener = source;
    history.hidden = true;
    detail.hidden = false;
    back.hidden = false;
    $(".alerts-history-count").hidden = true;
    heading.textContent = reportCategories[report.category];
    detail.innerHTML = `<div class="alerts-detail__intro">${categoryIcon(report)}<p>Observé aujourd’hui à ${report.time}</p><span class="alerts-row__distance">${report.distance}</span></div><p class="alerts-detail__description">${report.description}</p><p class="alerts-detail__place">Au large de Madère</p><div class="alerts-detail__author"><span class="alerts-avatar" aria-hidden="true">${report.author[0]}</span><span>${report.author}</span></div>`;
    heading.focus({ preventScroll: true });
    if (matchMedia("(max-width: 760px)").matches)
      heading.scrollIntoView({ block: "start", behavior: "instant" });
  }
  function showHistory() {
    history.hidden = false;
    detail.hidden = true;
    back.hidden = true;
    $(".alerts-history-count").hidden = false;
    heading.textContent = "Historique";
    const source =
      opener?.isConnected && !opener.closest("[hidden]")
        ? opener
        : history.querySelector(`[data-alert-index="${selected ?? 0}"]`);
    source?.focus({ preventScroll: true });
  }
  root.addEventListener("click", (event) => {
    const button = event.target.closest("[data-alert-action]");
    if (!button || !root.contains(button)) return;
    switch (button.dataset.alertAction) {
      case "toggle":
        enabled = !enabled;
        root.classList.toggle("alerts-enabled", enabled);
        toggle.setAttribute("aria-checked", String(enabled));
        status.textContent = enabled
          ? "Alertes activées"
          : "En pause · historique conservé";
        break;
      case "open":
        openReport(Number(button.dataset.alertIndex), button);
        break;
      case "back":
        showHistory();
        break;
    }
  });
  root.classList.add("alerts-enabled");
  return {
    setVisible(visible) {
      root.classList.toggle("is-visible", visible);
    },
  };
}
