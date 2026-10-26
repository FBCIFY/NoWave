import { clamp } from "./data.js";
import { journey } from "./story-data.js";
import { createStepGesture } from "./step-gesture.js";
import {
  mapJourney,
  overview,
  cameraBetween,
  cameraTravelDuration,
} from "./map-journey.js";
import {
  getStoryState,
  storyStops,
  followProgress,
  getTransitionState,
  settledStep,
} from "./story-state.js";

export function createStory({ world, isMotionPaused, onComplete }) {
  const $ = (selector) => document.querySelector(selector);
  const wrapper = $("#ocean-story"),
    hero = $("#ocean"),
    header = $(".site-header");
  const intro = $(".hero-copy");
  const markers = journey.map((scene) =>
    document.querySelector(`[data-spot="${scene.id}"]`),
  );
  const panels = journey.map((scene) => $(`#story-${scene.id}`));
  const nav = [...document.querySelectorAll(".story-steps button")];
  const previous = $("#previous-scene"),
    next = $("#next-scene");
  const poses = [overview, ...mapJourney];
  const wheelGesture = createStepGesture();
  let frame = 0,
    lastTime = 0,
    current = null,
    activeStep = 0,
    restingStep = 0,
    settleTimer = 0,
    touching = false;
  let start = 0,
    distance = 1,
    travel = null;
  let enabled = !["#carte", "#alertes"].some((hash) =>
    location.hash.startsWith(hash),
  );

  function measure() {
    if (!enabled) return;
    const previousProgress = (scrollY - start) / distance,
      oldDistance = distance;
    start = wrapper.getBoundingClientRect().top + scrollY;
    distance = Math.max(1, wrapper.offsetHeight - hero.offsetHeight);
    if (
      oldDistance > 1 &&
      oldDistance !== distance &&
      previousProgress > 0 &&
      previousProgress < 1
    ) {
      travel = null;
      window.scrollTo({
        top: start + previousProgress * distance,
        behavior: "instant",
      });
    }
    current ??= clamp((scrollY - start) / distance, 0, 1);
    requestUpdate();
  }
  function update(time) {
    frame = 0;
    if (!enabled || document.hidden || document.querySelector("dialog[open]")) {
      lastTime = 0;
      return;
    }
    let transition;
    if (travel) {
      const phase = isMotionPaused()
        ? 1
        : clamp((time - travel.at) / travel.duration, 0, 1);
      transition = {
        state: getTransitionState(
          travel.fromStep,
          travel.toStep,
          phase,
          isMotionPaused(),
        ),
        pose: travel.pose,
      };
      window.scrollTo({
        top: travel.from + (travel.to - travel.from) * transition.state.blend,
        behavior: "instant",
      });
      if (phase === 1) {
        restingStep = travel.toStep;
        travel = null;
      }
    }
    const target = clamp((scrollY - start) / distance, 0, 1);
    current =
      isMotionPaused() || transition
        ? target
        : followProgress(current, target, lastTime ? time - lastTime : 16);
    lastTime = time;
    const state = transition?.state || getStoryState(current, isMotionPaused());
    const from = transition?.pose || poses[state.from],
      to = poses[state.to];
    world.guide(
      cameraBetween(from, to, state.phase),
      (state.from === 0 ? 1 - state.blend : 0) +
        (state.to === 0 ? state.blend : 0),
    );
    hero.style.setProperty(
      "--intro-opacity",
      state.step === 0 ? state.opacity : 0,
    );
    hero.style.setProperty(
      "--story-opacity",
      state.step > 0 ? state.opacity : 0,
    );
    hero.style.setProperty(
      "--focus-strength",
      current > 0.05 ? 1 : current / 0.05,
    );
    hero.style.setProperty("--progress", current);
    hero.style.setProperty("--copy-shift", `${(1 - state.opacity) * 9}px`);
    markers.forEach((marker, index) => {
      const weight =
        (state.from === index + 1 ? 1 - state.blend : 0) +
        (state.to === index + 1 ? state.blend : 0);
      marker.style.setProperty(
        "--attention",
        index === state.step - 1 ? state.opacity : 0,
      );
      marker.style.setProperty(
        "--detail-opacity",
        index === state.step - 1 ? state.opacity : 0,
      );
      marker.inert = index !== state.step - 1 || state.opacity < 0.8;
      marker.setAttribute("aria-hidden", String(marker.inert));
      marker.classList.toggle("is-story-focus", weight > 0.99);
    });
    activeStep = state.step;
    hero.dataset.storyStep = state.step;
    hero.dataset.moving = String(Boolean(travel) || current !== target);
    intro.inert = state.step !== 0 || state.opacity < 0.1;
    intro.setAttribute("aria-hidden", String(state.step !== 0));
    panels.forEach((panel, index) => {
      panel.hidden = index !== state.step - 1;
      panel.inert = panel.hidden || state.opacity < 0.1;
    });
    nav.forEach((button, index) => {
      button.disabled = Boolean(travel);
      if (index === state.step) button.setAttribute("aria-current", "step");
      else button.removeAttribute("aria-current");
    });
    previous.disabled = state.step === 0 || Boolean(travel);
    next.disabled = Boolean(travel);
    next.setAttribute(
      "aria-label",
      state.step === journey.length
        ? "Découvrir les alertes à proximité"
        : "Repère suivant",
    );
    next.querySelector("span").textContent =
      state.step === journey.length ? "Mes alertes" : "Continuer";
    if (current !== target || travel) requestUpdate();
    else lastTime = 0;
  }
  function requestUpdate() {
    if (enabled && !frame && !document.hidden)
      frame = requestAnimationFrame(update);
  }
  function scrollToStep(step, instant = false) {
    clearTimeout(settleTimer);
    if (travel && !instant) return;
    if (step > journey.length) {
      travel = null;
      onComplete();
      return;
    }
    const toStep = clamp(step, 0, journey.length),
      to = start + distance * storyStops[toStep];
    if (instant || isMotionPaused()) {
      travel = null;
      restingStep = toStep;
      window.scrollTo({ top: to, behavior: "instant" });
      current = clamp((scrollY - start) / distance, 0, 1);
    } else {
      const pose = world.pose();
      travel = {
        from: scrollY,
        to,
        at: performance.now(),
        fromStep: activeStep,
        toStep,
        pose,
        duration: cameraTravelDuration(pose, poses[toStep]),
      };
    }
    requestUpdate();
  }
  previous.addEventListener("click", () => scrollToStep(activeStep - 1));
  next.addEventListener("click", () => scrollToStep(activeStep + 1));
  // Scrollbar dragging can still end between stops. Settle that fallback too.
  function scheduleSettle() {
    clearTimeout(settleTimer);
    if (
      !enabled ||
      travel ||
      touching ||
      document.querySelector("dialog[open]")
    )
      return;
    settleTimer = setTimeout(() => {
      const progress = (scrollY - start) / distance;
      if (
        progress < 0 ||
        progress > 1 ||
        (restingStep === journey.length && progress > storyStops.at(-1) + 0.025)
      )
        return;
      const step = settledStep(progress, restingStep);
      if (Math.abs(progress - storyStops[step]) > 0.0005) scrollToStep(step);
      else restingStep = step;
    }, 160);
  }
  function canGuide(target, direction) {
    if (!enabled || document.querySelector("dialog[open]")) return false;
    if (target.closest?.("input, textarea, select, [contenteditable]"))
      return false;
    const progress = (scrollY - start) / distance;
    if (progress < -0.001 || progress > storyStops.at(-1) + 0.015) return false;
    if (!travel && restingStep === 0 && direction < 0) return false;
    return true;
  }
  function advance(direction) {
    if (direction && !travel) scrollToStep(restingStep + direction);
  }
  window.addEventListener(
    "wheel",
    (event) => {
      if (
        event.ctrlKey ||
        Math.abs(event.deltaX) > Math.abs(event.deltaY) ||
        !canGuide(event.target, event.deltaY)
      )
        return;
      event.preventDefault();
      const delta =
        event.deltaY *
        (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? innerHeight : 1);
      advance(wheelGesture.push(delta, performance.now()));
    },
    { passive: false },
  );
  let touch = null;
  window.addEventListener(
    "touchstart",
    (event) => {
      if (event.touches.length !== 1) return;
      touching = true;
      const point = event.touches[0];
      touch = {
        x: point.clientX,
        y: point.clientY,
        target: event.target,
        delta: 0,
        guided: false,
      };
    },
    { passive: true },
  );
  window.addEventListener(
    "touchmove",
    (event) => {
      if (!touch || event.touches.length !== 1) return;
      const point = event.touches[0],
        delta = touch.y - point.clientY;
      if (
        Math.abs(point.clientX - touch.x) > Math.abs(delta) ||
        !canGuide(touch.target, delta)
      )
        return;
      if (event.cancelable) event.preventDefault();
      touch.delta = delta;
      touch.guided = true;
    },
    { passive: false },
  );
  window.addEventListener(
    "touchend",
    () => {
      touching = false;
      if (touch?.guided && Math.abs(touch.delta) >= 36)
        advance(Math.sign(touch.delta));
      else scheduleSettle();
      touch = null;
    },
    { passive: true },
  );
  window.addEventListener(
    "touchcancel",
    () => {
      touching = false;
      touch = null;
      scheduleSettle();
    },
    { passive: true },
  );
  window.addEventListener("keydown", (event) => {
    const direction = ["ArrowDown", "PageDown", " "].includes(event.key)
      ? event.shiftKey && event.key === " "
        ? -1
        : 1
      : ["ArrowUp", "PageUp"].includes(event.key)
        ? -1
        : 0;
    if (
      !direction ||
      event.target.closest?.("button, a, summary") ||
      !canGuide(event.target, direction)
    )
      return;
    event.preventDefault();
    if (!event.repeat) advance(direction);
  });
  window.addEventListener(
    "scroll",
    () => {
      requestUpdate();
      scheduleSettle();
    },
    { passive: true },
  );
  document.addEventListener("visibilitychange", () => {
    cancelAnimationFrame(frame);
    frame = 0;
    lastTime = 0;
    travel = null;
    clearTimeout(settleTimer);
    if (!document.hidden) requestUpdate();
  });
  document
    .querySelectorAll("dialog")
    .forEach((dialog) => dialog.addEventListener("close", requestUpdate));
  const observer = new ResizeObserver(measure);
  [hero, header].forEach((element) => observer.observe(element));
  document.fonts.ready.then(measure);
  measure();
  return {
    refresh: requestUpdate,
    scrollToStep,
    setVisible(value) {
      enabled = value;
      travel = null;
      clearTimeout(settleTimer);
      cancelAnimationFrame(frame);
      frame = 0;
      lastTime = 0;
      if (enabled) measure();
      if (enabled) {
        current = clamp((scrollY - start) / distance, 0, 1);
        restingStep = storyStops.reduce(
          (best, stop, index) =>
            Math.abs(stop - current) < Math.abs(storyStops[best] - current)
              ? index
              : best,
          0,
        );
      }
    },
  };
}
