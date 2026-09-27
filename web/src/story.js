import { clamp } from "./data.js";
import { journey } from "./story-data.js";
import { createStepGesture } from "./step-gesture.js";
import {
  getStoryState,
  storyStops,
  followProgress,
  easeCamera,
  getTransitionState,
} from "./story-state.js";

export function createStory({ world, isMotionPaused }) {
  const $ = (selector) => document.querySelector(selector);
  const wrapper = $("#ocean-story"),
    hero = $("#ocean"),
    map = $("#world");
  const viewport = $("#map-viewport"),
    header = $(".site-header"),
    intro = $(".hero-copy");
  const markers = journey.map((scene) =>
    map.querySelector(`[data-spot="${scene.id}"]`),
  );
  const iceIndex = journey.findIndex((scene) => scene.id === "iceberg");
  const panels = journey.map((scene) => $(`#story-${scene.id}`));
  const nav = [...document.querySelectorAll(".story-steps button")];
  const previous = $("#previous-scene"),
    next = $("#next-scene");
  let suspended = false,
    frame = 0,
    poses = [],
    start = 0,
    distance = 1;
  let activeStep = -1,
    current = null,
    lastTime = 0,
    settling = null;
  let focused = new Set();
  let travelingTo = null;
  let scrollTravel = null;
  let pendingDirection = 0,
    pendingAt = 0;
  const wheelGesture = createStepGesture();

  function measure() {
    const width = hero.clientWidth,
      height = hero.clientHeight,
      compact = width <= 760;
    const previousProgress = (scrollY - start) / distance;
    const oldDistance = distance;
    start = wrapper.getBoundingClientRect().top + scrollY - header.offsetHeight;
    distance = Math.max(1, wrapper.offsetHeight - height);
    poses = [{ x: 0, y: 0, zoom: 1 }];
    markers.forEach((marker, index) => {
      let availableHeight = height;
      if (compact) {
        const panel = panels[index],
          wasHidden = panel.hidden;
        panel.hidden = false;
        availableHeight = Math.max(56, panel.offsetTop - 24);
        panel.hidden = wasHidden;
      }
      const distant = journey[index].id === "iceberg";
      const objectHeight = compact
        ? Math.max(36, Math.min(290, availableHeight - 20))
        : Math.min(480, height - 140);
      const zoom =
        Math.min(compact ? 2.5 : 3.2, objectHeight / marker.offsetHeight) *
        (distant ? 0.72 : 1);
      const targetX = width * (compact ? 0.52 : distant ? 0.76 : 0.73);
      const targetY = compact
        ? Math.min(height * 0.28, availableHeight / 2 + 8)
        : height * (distant ? 0.42 : 0.46);
      poses.push({
        x:
          targetX -
          map.offsetLeft -
          (marker.offsetLeft - map.offsetWidth / 2) * zoom,
        y:
          targetY -
          map.offsetTop -
          (marker.offsetTop - map.offsetHeight / 2) * zoom,
        zoom,
      });
    });
    // Keep the same scene on rotation or window resizing, without moving readers below the tour.
    if (
      !suspended &&
      oldDistance > 1 &&
      oldDistance !== distance &&
      previousProgress > 0 &&
      previousProgress < 1
    ) {
      window.scrollTo({
        top: start + previousProgress * distance,
        behavior: "instant",
      });
    }
    if (current === null) current = clamp((scrollY - start) / distance, 0, 1);
    requestUpdate();
  }

  function update(time) {
    frame = 0;
    if (
      suspended ||
      document.hidden ||
      !poses.length ||
      document.querySelector("dialog[open]")
    ) {
      lastTime = 0;
      return;
    }
    const isStepping = scrollTravel !== null;
    let transition = null;
    if (scrollTravel) {
      const phase = isMotionPaused()
        ? 1
        : clamp((time - scrollTravel.at) / scrollTravel.duration, 0, 1);
      transition = {
        state: getTransitionState(
          scrollTravel.fromStep,
          scrollTravel.toStep,
          phase,
          isMotionPaused(),
        ),
        fromPose: scrollTravel.fromPose,
      };
      window.scrollTo({
        top:
          scrollTravel.from +
          (scrollTravel.to - scrollTravel.from) * transition.state.blend,
        behavior: "instant",
      });
      if (phase === 1) scrollTravel = null;
    }
    const target = clamp((scrollY - start) / distance, 0, 1);
    current =
      isMotionPaused() || isStepping
        ? target
        : followProgress(current, target, lastTime ? time - lastTime : 16);
    lastTime = time;
    const state = transition?.state || getStoryState(current, isMotionPaused());
    const from = transition?.fromPose || poses[state.from],
      to = poses[state.to];
    let pose = {
      x: from.x + (to.x - from.x) * state.blend,
      y: from.y + (to.y - from.y) * state.blend,
      zoom: from.zoom + (to.zoom - from.zoom) * state.blend,
    };
    if (settling && !isMotionPaused()) {
      const phase = clamp((time - settling.at) / 450, 0, 1),
        weight = easeCamera(phase);
      pose = Object.fromEntries(
        Object.keys(pose).map((key) => [
          key,
          settling.pose[key] + (pose[key] - settling.pose[key]) * weight,
        ]),
      );
      if (phase === 1) settling = null;
    } else settling = null;
    world.guide(pose);
    hero.style.setProperty(
      "--intro-opacity",
      state.step === 0 ? state.opacity : 0,
    );
    hero.style.setProperty(
      "--story-opacity",
      state.step > 0 ? state.opacity : 0,
    );
    hero.style.setProperty("--copy-shift", `${(1 - state.opacity) * 7}px`);
    const fromFocus = Number(state.from > 0),
      toFocus = Number(state.to > 0);
    hero.style.setProperty(
      "--focus-strength",
      fromFocus + (toFocus - fromFocus) * state.blend,
    );
    const attention = new Map();
    if (state.from > 0) attention.set(state.from - 1, 1 - state.blend);
    if (state.to > 0)
      attention.set(
        state.to - 1,
        (attention.get(state.to - 1) || 0) + state.blend,
      );
    focused.forEach((index) => {
      if (!attention.has(index))
        markers[index].style.setProperty("--attention", 0);
    });
    attention.forEach((weight, index) =>
      markers[index].style.setProperty("--attention", weight),
    );
    markers.forEach((marker, index) =>
      marker.classList.toggle(
        "is-story-focus",
        (attention.get(index) || 0) > 0.999,
      ),
    );
    map.style.setProperty("--island-focus", attention.get(0) || 0);
    markers[iceIndex].style.setProperty(
      "--ice-reveal",
      easeCamera(clamp(((attention.get(iceIndex) || 0) - 0.4) / 0.6, 0, 1)),
    );
    focused = new Set(attention.keys());
    if (state.step !== activeStep) {
      activeStep = state.step;
      hero.dataset.storyStep = state.step;
      intro.inert = state.step !== 0;
      intro.setAttribute("aria-hidden", String(state.step !== 0));
      panels.forEach((panel, index) => {
        panel.hidden = index !== state.step - 1;
      });
      nav.forEach((button, index) => {
        if (index === state.step) button.setAttribute("aria-current", "step");
        else button.removeAttribute("aria-current");
      });
      $("#story-position").textContent =
        state.step === 0
          ? "L’archipel NoWave"
          : `${String(state.step).padStart(2, "0")} / ${journey.length} · ${journey[state.step - 1].label}`;
      previous.disabled = state.step === 0;
      next.setAttribute(
        "aria-label",
        state.step === journey.length
          ? "Voir le récapitulatif"
          : "Repère suivant",
      );
    }
    const activePanel = state.step > 0 ? panels[state.step - 1] : intro;
    activePanel.inert = state.opacity < 0.1;
    if (
      !scrollTravel &&
      state.step === travelingTo &&
      state.opacity === 1 &&
      current === target
    ) {
      travelingTo = null;
      pendingAt = time + 180;
    }
    if (pendingDirection && travelingTo === null && time >= pendingAt) {
      const direction = pendingDirection;
      pendingDirection = 0;
      scrollToStep(state.step + direction);
    }
    previous.disabled = state.step === 0 && travelingTo === null;
    next.disabled = false;
    previous.classList.toggle("is-queued", pendingDirection === -1);
    next.classList.toggle("is-queued", pendingDirection === 1);
    hero.dataset.moving = String(Boolean(scrollTravel || settling));
    hero.dataset.pending = String(pendingDirection);
    if (current !== target || settling || scrollTravel || pendingDirection)
      requestUpdate();
    else lastTime = 0;
  }
  function requestUpdate() {
    if (!frame && !suspended && !document.hidden)
      frame = requestAnimationFrame(update);
  }
  function scrollToStep(step, instant = false) {
    pendingDirection = 0;
    if (step > journey.length) {
      travelingTo = null;
      scrollTravel = null;
      $("#recap").scrollIntoView({
        behavior: instant || isMotionPaused() ? "instant" : "smooth",
      });
      $("#recap").focus({ preventScroll: true });
      return;
    }
    travelingTo = clamp(step, 0, journey.length);
    const destination = start + distance * storyStops[travelingTo];
    if (Math.abs(destination - scrollY) < 2) {
      scrollTravel = null;
      travelingTo = null;
      pendingAt = 0;
      requestUpdate();
      return;
    }
    if (instant || isMotionPaused()) {
      scrollTravel = null;
      window.scrollTo({ top: destination, behavior: "instant" });
      current = clamp((scrollY - start) / distance, 0, 1);
      world.guide(poses[clamp(step, 0, journey.length)]);
    } else {
      scrollTravel = {
        from: scrollY,
        to: destination,
        at: performance.now(),
        duration: 1500,
        fromStep: Math.max(0, activeStep),
        toStep: travelingTo,
        fromPose: world.pose(),
      };
    }
    requestUpdate();
  }
  function advance(direction) {
    if (travelingTo !== null || performance.now() < pendingAt) {
      pendingDirection = direction;
      requestUpdate();
    } else scrollToStep(activeStep + direction);
  }
  function inTour() {
    return (
      !suspended &&
      !document.querySelector("dialog[open]") &&
      scrollY >= start - 1 &&
      scrollY <= start + distance + 1
    );
  }
  previous.addEventListener("click", () => advance(-1));
  next.addEventListener("click", () => advance(1));
  document.addEventListener("click", (event) => {
    if (event.target.closest('a[href="#recap"], a[href="#"]')) {
      scrollTravel = null;
      travelingTo = null;
      pendingDirection = 0;
    }
  });
  window.addEventListener(
    "wheel",
    (event) => {
      if (
        !inTour() ||
        event.ctrlKey ||
        Math.abs(event.deltaX) > Math.abs(event.deltaY)
      )
        return;
      if (activeStep === 0 && event.deltaY < 0 && travelingTo === null) return;
      event.preventDefault();
      const unit =
        event.deltaMode === 1
          ? 16
          : event.deltaMode === 2
            ? hero.clientHeight
            : 1;
      const direction = wheelGesture.push(
        event.deltaY * unit,
        performance.now(),
      );
      if (direction) advance(direction);
    },
    { passive: false },
  );
  let touchStartY = null,
    touchConsumed = false;
  window.addEventListener(
    "touchstart",
    (event) => {
      touchStartY =
        inTour() && event.touches.length === 1
          ? event.touches[0].clientY
          : null;
      touchConsumed = false;
    },
    { passive: true },
  );
  window.addEventListener(
    "touchmove",
    (event) => {
      if (touchStartY === null || event.touches.length !== 1 || !inTour())
        return;
      const delta = touchStartY - event.touches[0].clientY;
      if (activeStep === 0 && delta < 0 && travelingTo === null) return;
      event.preventDefault();
      if (!touchConsumed && Math.abs(delta) >= 36) {
        touchConsumed = true;
        advance(Math.sign(delta));
      }
    },
    { passive: false },
  );
  window.addEventListener(
    "touchend",
    () => {
      touchStartY = null;
    },
    { passive: true },
  );
  window.addEventListener(
    "touchcancel",
    () => {
      touchStartY = null;
    },
    { passive: true },
  );
  window.addEventListener("keydown", (event) => {
    if (
      !inTour() ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.target.closest('input, textarea, select, [contenteditable="true"]')
    )
      return;
    if (event.key === " " && event.target.closest("button, a")) return;
    const direction = {
      ArrowDown: 1,
      PageDown: 1,
      ArrowUp: -1,
      PageUp: -1,
      " ": event.shiftKey ? -1 : 1,
    }[event.key];
    if (!direction || (activeStep === 0 && direction < 0)) return;
    event.preventDefault();
    if (!event.repeat) advance(direction);
  });
  let snapTimer;
  window.addEventListener(
    "scroll",
    () => {
      requestUpdate();
      clearTimeout(snapTimer);
      // Also settle scrollbar drags, browser history restoration and native touch momentum.
      snapTimer = setTimeout(() => {
        if (!inTour() || travelingTo !== null) return;
        const progress = clamp((scrollY - start) / distance, 0, 1);
        const nearest = storyStops.reduce(
          (best, stop, index) =>
            Math.abs(stop - progress) < Math.abs(storyStops[best] - progress)
              ? index
              : best,
          0,
        );
        if (Math.abs(storyStops[nearest] - progress) * distance > 2)
          scrollToStep(nearest);
      }, 220);
    },
    { passive: true },
  );
  document.addEventListener("visibilitychange", () => {
    cancelAnimationFrame(frame);
    frame = 0;
    lastTime = 0;
    if (!document.hidden) requestUpdate();
  });
  document
    .querySelectorAll("dialog")
    .forEach((dialog) => dialog.addEventListener("close", requestUpdate));
  const observer = new ResizeObserver(measure);
  [hero, map, header, ...markers].forEach((element) =>
    observer.observe(element),
  );
  document.fonts.ready.then(measure);
  viewport.inert = true;
  measure();
  return {
    refresh: requestUpdate,
    scrollToStep,
  };
}
