export const reportCategories = {
  obstruction: "Obstacle",
  marine_animal: "Animal marin",
  pollution: "Pollution",
};

// Demonstration data only. Never submitted to the API.
export const demoReports = {
  container: {
    category: "obstruction",
    author: "Alex",
    description: "Un conteneur à la dérive au large de Singapour.",
    place: "Détroit de Singapour",
    time: "14:30",
    coordinates: "1° 12′ 36″ N · 103° 57′ 00″ E",
    location: [103.95, 1.21],
  },
  whale: {
    category: "marine_animal",
    author: "Léa",
    description: "Une baleine observée au large, en direction de l’est.",
    place: "Au large des Açores",
    time: "14:08",
    coordinates: "38° 19′ 48″ N · 28° 42′ 00″ O",
    location: [-28.7, 38.33],
  },
  duck: {
    category: "pollution",
    author: "Camille",
    description: "Débris plastiques dispersés en surface.",
    place: "Îles Fidji",
    time: "13:52",
    coordinates: "18° 17′ 24″ S · 178° 24′ 00″ E",
    location: [178.4, -18.29],
  },
};
export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
