export function createWorld({ world }) {
  let current = { x: 0, y: 0, zoom: 1 };
  return {
    guide(pose) {
      current = { ...pose };
      const { x, y, zoom } = current;
      // Rasterize at the displayed scale to keep the archipelago crisp.
      world.style.transform = `translate(calc(-50% + ${x}px), calc(-50% + ${y}px)) scale(${zoom})`;
    },
    pose() {
      return { ...current };
    },
  };
}
