/* Contextual returns keep list pagination and the originating map selection. */
(function (root) {
  function safePath(value, origin) {
    if (typeof value !== "string" || !value || value.length > 6000) return null;
    try {
      const url = new URL(value, origin);
      if (
        url.origin !== origin ||
        url.username ||
        url.password ||
        !/^\/admin(?:$|\/(?:users|reports|audit|actions)(?:\/|$))/.test(
          url.pathname,
        )
      )
        return null;
      return url.pathname + url.search + url.hash;
    } catch {
      return null;
    }
  }
  function parentPath(current, origin) {
    const path = safePath(current, origin);
    return path
      ? safePath(new URL(path, origin).searchParams.get("return_to"), origin)
      : null;
  }
  function childPath(target, current, origin, pagination = false) {
    const next = safePath(target, origin),
      from = safePath(current, origin);
    if (!next || !from) return target;
    const url = new URL(next, origin);
    if (url.pathname === new URL(from, origin).pathname && !pagination) {
      const parent = parentPath(from, origin);
      if (parent) url.searchParams.set("return_to", parent);
      return url.pathname + url.search + url.hash;
    }
    const parent = pagination ? parentPath(from, origin) : from;
    if (parent && parent.length < 4000)
      url.searchParams.set("return_to", parent);
    return url.pathname + url.search + url.hash;
  }
  const api = { safePath, parentPath, childPath };
  if (typeof module !== "undefined") module.exports = api;
  root.NoWaveAdminNavigation = Object.freeze(api);
  if (!root.document) return;
  const origin = location.origin;
  function prepareBackLinks() {
    const parent = parentPath(location.href, origin);
    if (parent)
      document.querySelectorAll("[data-nav-back]").forEach((link) => {
        link.href = parent;
      });
  }
  prepareBackLinks();
  document.addEventListener("click", (event) => {
    const link = event.target.closest("a[href]");
    if (
      !link ||
      event.defaultPrevented ||
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      link.target ||
      link.hasAttribute("download")
    )
      return;
    if (link.hasAttribute("data-nav-back")) {
      const parent = parentPath(location.href, origin);
      if (!parent) return;
      link.href = parent;
      // The native stack also restores in-memory map state when available.
      if (
        history.length > 1 &&
        safePath(document.referrer, origin) === parent &&
        !document.querySelector("[data-action-complete]")
      ) {
        event.preventDefault();
        history.back();
      }
      return;
    }
    if (link.closest(".admin-header") || link.classList.contains("back-link"))
      return;
    link.href = childPath(
      link.href,
      location.href,
      origin,
      !!link.closest(".pagination"),
    );
  });
  const scrollKey = "nowave.admin.scroll";
  function saveScroll() {
    try {
      const positions = JSON.parse(sessionStorage.getItem(scrollKey) || "{}");
      positions[location.pathname + location.search + location.hash] = scrollY;
      sessionStorage.setItem(
        scrollKey,
        JSON.stringify(
          Object.fromEntries(Object.entries(positions).slice(-24)),
        ),
      );
    } catch {}
  }
  window.addEventListener("pagehide", saveScroll);
  window.addEventListener("pageshow", () => {
    prepareBackLinks();
    try {
      const positions = JSON.parse(sessionStorage.getItem(scrollKey) || "{}");
      const y = positions[location.pathname + location.search + location.hash];
      if (Number.isFinite(y)) scrollTo({ top: y, behavior: "instant" });
    } catch {}
  });
})(globalThis);
