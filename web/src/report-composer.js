import "./report-composer.css";
import { categories } from "./report-categories.js";
const instances = new WeakMap();
let nextId = 0;

function icon(path) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;
}

// A local illustration of the composer. Nothing is sent or persisted.
export function createReportComposer(dialog) {
  if (dialog?.localName !== "dialog")
    throw new TypeError("A dialog element is required.");
  instances.get(dialog)?.destroy();
  const id = `report-composer-${++nextId}`;
  let selected = "obstruction";
  let destroyed = false;
  let opener = null;
  dialog.classList.add("report-composer");
  dialog.setAttribute("aria-labelledby", `${id}-title`);
  dialog.setAttribute("aria-describedby", `${id}-notice`);
  dialog.innerHTML = `
    <header class="report-composer__header">
      <h2 id="${id}-title" tabindex="-1">Nouveau signalement</h2>
      <button class="report-composer__close" type="button" aria-label="Fermer">${icon('<path d="m6 6 12 12M18 6 6 18"/>')}</button>
    </header>
    <p class="report-composer__notice" id="${id}-notice">Démonstration · aucun envoi</p>
    <form class="report-composer__form">
      <div class="report-composer__categories" role="group" aria-label="Catégorie du signalement">
        ${categories.map((category) => `<button class="report-composer__category" type="button" data-category="${category.value}" aria-pressed="${category.value === selected}"${category.value === selected ? " autofocus" : ""}>${icon(category.path)}<span>${category.label}</span></button>`).join("")}
      </div>
      <label class="report-composer__sr-only" for="${id}-comment">Ajouter un commentaire (facultatif)</label>
      <textarea id="${id}-comment" name="comment" maxlength="500" rows="4" placeholder="Ajouter un commentaire (facultatif)"></textarea>
      <button class="report-composer__primary" type="submit">Publier le signalement</button>
    </form>
    <section class="report-composer__confirmation" aria-label="Signalement créé" hidden>
      <span class="report-composer__check" aria-hidden="true">${icon('<path d="m6 12 4 4 8-8"/>')}</span>
      <p class="report-composer__confirmed-category"></p>
      <p class="report-composer__comment" hidden></p>
      <button class="report-composer__primary" type="button" data-restart>Recommencer</button>
    </section>
  `;
  const heading = dialog.querySelector("h2");
  const form = dialog.querySelector("form");
  const comment = dialog.querySelector("textarea");
  const confirmation = dialog.querySelector(".report-composer__confirmation");
  const confirmedCategory = dialog.querySelector(
    ".report-composer__confirmed-category",
  );
  const confirmedComment = dialog.querySelector(".report-composer__comment");
  const categoryButtons = [...dialog.querySelectorAll("[data-category]")];

  function choose(value) {
    if (!categories.some((category) => category.value === value)) return;
    selected = value;
    categoryButtons.forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.category === selected),
      ),
    );
  }
  function reset() {
    if (destroyed) return;
    choose("obstruction");
    comment.value = "";
    confirmedComment.textContent = "";
    confirmedComment.hidden = true;
    form.hidden = false;
    confirmation.hidden = true;
    heading.textContent = "Nouveau signalement";
    if (dialog.open)
      categoryButtons
        .find((button) => button.dataset.category === selected)
        .focus({ preventScroll: true });
  }
  function close() {
    if (!destroyed && dialog.open) dialog.close();
  }
  function onClose() {
    if (opener?.isConnected) opener.focus({ preventScroll: true });
    opener = null;
  }
  function onClick(event) {
    const button = event.target.closest?.("button");
    if (!button || !dialog.contains(button)) return;
    if (button.hasAttribute("data-category")) choose(button.dataset.category);
    else if (button.hasAttribute("data-restart")) reset();
    else if (button.classList.contains("report-composer__close")) close();
  }
  function onSubmit(event) {
    event.preventDefault();
    const text = comment.value.slice(0, 500).trim();
    confirmedCategory.textContent = categories.find(
      (category) => category.value === selected,
    ).label;
    confirmedComment.textContent = text;
    confirmedComment.hidden = !text;
    form.hidden = true;
    confirmation.hidden = false;
    heading.textContent = "Signalement créé";
    heading.focus({ preventScroll: true });
  }
  dialog.addEventListener("click", onClick);
  dialog.addEventListener("close", onClose);
  form.addEventListener("submit", onSubmit);
  const controller = {
    open() {
      if (destroyed || dialog.open) return;
      opener = dialog.ownerDocument.activeElement;
      reset();
      dialog.showModal();
    },
    close,
    reset,
    destroy() {
      if (destroyed) return;
      close();
      onClose();
      destroyed = true;
      dialog.removeEventListener("click", onClick);
      dialog.removeEventListener("close", onClose);
      form.removeEventListener("submit", onSubmit);
      dialog.replaceChildren();
      dialog.classList.remove("report-composer");
      dialog.removeAttribute("aria-labelledby");
      dialog.removeAttribute("aria-describedby");
      instances.delete(dialog);
    },
  };
  instances.set(dialog, controller);
  return controller;
}
