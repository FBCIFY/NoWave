import "./src/style.css";
import { createMapView } from "./src/map-view.js";

// The authenticated backend renders this entry. The observation map itself is
// the same component as the public site; private actions keep their guards.
let detailRequest;
async function moderationDetail({ report, container }) {
  detailRequest?.abort();
  const current = (detailRequest = new AbortController());
  container
    .querySelectorAll(".map-view__admin-actions,.map-view__admin-status")
    .forEach((node) => node.remove());
  const note = document.createElement("p");
  note.className = "map-view__admin-status";
  note.setAttribute("role", "status");
  note.textContent = "Chargement de la modération…";
  container.append(note);
  try {
    const response = await fetch(
      `/admin/data/reports/${encodeURIComponent(report.id)}`,
      { signal: current.signal, credentials: "same-origin", cache: "no-store" },
    );
    if (
      response.redirected ||
      response.status === 401 ||
      response.status === 403
    )
      throw Error("Session expirée. Reconnectez-vous.");
    if (!response.ok) throw Error("Modération momentanément indisponible.");
    const data = await response.json();
    if (
      current !== detailRequest ||
      current.signal.aborted ||
      container.hidden ||
      container.dataset.reportId !== report.id
    )
      return;
    const author = data.author?.deleted
      ? "Compte supprimé"
      : data.author?.username;
    if (author)
      container.querySelector(".map-view__author").textContent = author;
    const actions = document.createElement("nav");
    actions.className = "map-view__admin-actions";
    actions.setAttribute("aria-label", "Modération du signalement");
    const link = (label, path) => {
      const item = document.createElement("a");
      item.textContent = label;
      item.href = path;
      actions.append(item);
    };
    link(
      "Fiche et historique",
      `/admin/reports/${encodeURIComponent(report.id)}`,
    );
    if (data.status === "removed")
      link(
        "Restaurer",
        `/admin/actions/reports/${encodeURIComponent(report.id)}/restore`,
      );
    else if (["active", "expired"].includes(data.status))
      link(
        "Retirer",
        `/admin/actions/reports/${encodeURIComponent(report.id)}/remove`,
      );
    if (data.photo?.url && !data.photo.hidden_at)
      link(
        "Masquer la photo",
        `/admin/actions/reports/${encodeURIComponent(report.id)}/hide-photo`,
      );
    note.textContent =
      { active: "Actif", expired: "Expiré", removed: "Retiré" }[data.status] ||
      "";
    container.append(actions);
  } catch (error) {
    if (
      error.name !== "AbortError" &&
      current === detailRequest &&
      !container.hidden &&
      container.dataset.reportId === report.id
    )
      note.textContent = error.message;
  }
}
const chart = createMapView({ admin: true, onSelectReport: moderationDetail });
chart.open();
const header = document.querySelector(".site-header");
new ResizeObserver(() =>
  document.documentElement.style.setProperty(
    "--header-height",
    `${header.offsetHeight}px`,
  ),
).observe(header);
const direct = new URL(location.href).searchParams.get("report");
if (direct && /^[0-9a-f-]{36}$/i.test(direct)) {
  fetch(`/admin/data/reports/${encodeURIComponent(direct)}`, {
    credentials: "same-origin",
    cache: "no-store",
  })
    .then((response) => {
      if (!response.ok || response.redirected)
        throw Error("Fiche indisponible.");
      return response.json();
    })
    .then((report) =>
      chart.showReport({
        id: String(report.id),
        category: report.category,
        location: report.final_position.coordinates,
        observedAt: report.observed_at,
        expiresAt: Date.parse(report.expires_at),
        description: report.description || "",
        author: report.author?.username || "",
      }),
    )
    .catch(() => {
      const status = document.querySelector("#navigation-status");
      status.textContent =
        "Fiche indisponible. Retrouvez les signalements dans Modération.";
    });
}
