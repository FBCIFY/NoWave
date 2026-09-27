import { clamp } from "./data.js";

export function createWorld({ viewport, world, onExplore }) {
  let zoom = 1;
  let x = 0;
  let y = 0;
  let exploring = false;
  const pointers = new Map();
  let previousPinch = 0;
  let moved = false;
  let frame = 0;
  const output = document.querySelector("#zoom-level");
  const iceberg = world.querySelector('[data-spot="iceberg"]');
  const apply = () => {
    // Let the browser rasterize at the displayed scale instead of enlarging a cached GPU texture.
    world.style.transform = `translate(calc(-50% + ${x}px), calc(-50% + ${y}px)) scale(${zoom})`;
    if (exploring) {
      const reveal = clamp((iceberg.offsetWidth * zoom - 165) / 120, 0, 1);
      iceberg.style.setProperty(
        "--ice-reveal",
        reveal * reveal * (3 - 2 * reveal),
      );
    }
  };
  const render = () => {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      if (exploring) {
        const bounds = viewport.getBoundingClientRect();
        x = clamp(x, -bounds.width * zoom * 0.8, bounds.width * zoom * 0.8);
        y = clamp(y, -bounds.height * zoom, bounds.height * zoom);
      }
      apply();
      output.value = `${Math.round(zoom * 100)}%`;
      document.querySelector("#zoom-out").disabled = zoom <= 0.35;
      document.querySelector("#zoom-in").disabled = zoom >= 3.2;
    });
  };
  const setZoom = (next) => {
    zoom = clamp(next, 0.35, 3.2);
    render();
  };
  viewport.addEventListener("pointerdown", (event) => {
    if (!exploring || event.button > 0 || event.target.closest("button"))
      return;
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    viewport.setPointerCapture(event.pointerId);
    moved = false;
    viewport.classList.add("is-dragging");
  });
  viewport.addEventListener("pointermove", (event) => {
    const previous = pointers.get(event.pointerId);
    if (!previous) return;
    const dx = event.clientX - previous.x;
    const dy = event.clientY - previous.y;
    if (Math.abs(dx) + Math.abs(dy) > 2) moved = true;
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      const distance = Math.hypot(a.x - b.x, a.y - b.y);
      if (previousPinch) setZoom((zoom * distance) / previousPinch);
      previousPinch = distance;
    } else {
      x += dx;
      y += dy;
      render();
    }
  });
  const release = (event) => {
    pointers.delete(event.pointerId);
    previousPinch = 0;
    if (!pointers.size) viewport.classList.remove("is-dragging");
  };
  viewport.addEventListener("pointerup", release);
  viewport.addEventListener("pointercancel", release);
  viewport.addEventListener("lostpointercapture", release);
  viewport.addEventListener(
    "click",
    (event) => {
      if (moved) {
        event.preventDefault();
        event.stopPropagation();
        moved = false;
      }
    },
    true,
  );
  viewport.addEventListener(
    "wheel",
    (event) => {
      if (!exploring) return;
      event.preventDefault();
      setZoom(zoom * Math.exp(-event.deltaY * 0.0015));
    },
    { passive: false },
  );
  viewport.addEventListener("keydown", (event) => {
    if (!exploring || event.target !== viewport) return;
    const step = event.shiftKey ? 120 : 50;
    const actions = {
      ArrowLeft: () => {
        x += step;
      },
      ArrowRight: () => {
        x -= step;
      },
      ArrowUp: () => {
        y += step;
      },
      ArrowDown: () => {
        y -= step;
      },
      "+": () => setZoom(zoom + 0.15),
      "=": () => setZoom(zoom + 0.15),
      "-": () => setZoom(zoom - 0.15),
      0: overview,
    };
    if (actions[event.key]) {
      event.preventDefault();
      actions[event.key]();
      render();
    }
  });
  window.addEventListener("resize", () => {
    if (exploring) render();
  });
  document.querySelector("#zoom-in").addEventListener("click", () => {
    onExplore(false);
    setZoom(zoom + 0.15);
  });
  document.querySelector("#zoom-out").addEventListener("click", () => {
    onExplore(false);
    setZoom(zoom - 0.15);
  });
  function overview() {
    zoom = Math.min(
      1,
      (viewport.clientWidth / world.offsetWidth) * 0.94,
      (viewport.clientHeight / world.offsetHeight) * 0.92,
    );
    x = viewport.clientWidth / 2 - world.offsetLeft;
    y = viewport.clientHeight / 2 - world.offsetTop;
    render();
  }
  document.querySelector("#reset-map").addEventListener("click", overview);
  render();
  return {
    overview,
    guide(pose) {
      if (exploring) return;
      cancelAnimationFrame(frame);
      frame = 0;
      ({ x, y, zoom } = pose);
      apply();
    },
    explore(value) {
      exploring = value;
      pointers.clear();
      previousPinch = 0;
      moved = false;
      viewport.classList.remove("is-dragging");
      render();
    },
    pose() {
      return { x, y, zoom };
    },
    focus(spot) {
      const marker = world.querySelector(`[data-spot="${spot.id}"]`);
      x = world.offsetWidth / 2 - marker.offsetLeft;
      y = world.offsetHeight / 2 - marker.offsetTop;
      zoom = 1;
      render();
    },
  };
}
