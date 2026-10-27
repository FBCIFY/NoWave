// Shared category items for the tour, public filters and administration.
export const categories = Object.freeze([
  {
    value: "marine_animal",
    label: "Animal marin",
    path: '<path d="M3 13c3-5 7-7 11-4l3 3 4-1-1 4-3-1c-4 4-9 4-13 1l-2 1 1-3Z"/><path d="m10 8 2-3 2 4M9 16l-1 3 4-2"/>',
  },
  {
    value: "obstruction",
    label: "Obstacle",
    path: '<path d="m10.3 4.6-8 13.8A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-2.6l-8-13.8a2 2 0 0 0-3.4 0Z"/><path d="M12 9v5m0 3h.01"/>',
  },
  {
    value: "pollution",
    label: "Pollution",
    path: '<path d="M12 3c-2 4-7 8-7 12a7 7 0 0 0 14 0c0-4-5-8-7-12Z"/><path d="M9 15a3 3 0 0 0 3 3"/>',
  },
]);
export const categoryIcon = (category) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${category.path}</svg>`;
