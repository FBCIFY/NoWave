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
    description: "Un conteneur à la dérive au large de Grande Canarie.",
    place: "Au large d’Agaete, Grande Canarie",
    time: "14:30",
    coordinates: "28° 04′ 48″ N · 15° 48′ 49″ O",
    location: [-15.813501, 28.080103],
  },
  whale: {
    category: "marine_animal",
    author: "Léa",
    description: "Une baleine observée au large, en direction de l’est.",
    place: "Au large de Tenerife",
    time: "14:08",
    coordinates: "28° 29′ 00″ N · 16° 49′ 59″ O",
    location: [-16.833086, 28.483415],
  },
  duck: {
    category: "pollution",
    author: "Camille",
    description: "Débris plastiques dispersés en surface.",
    place: "Au large de Santo Antão, Cap-Vert",
    time: "13:52",
    coordinates: "17° 13′ 32″ N · 25° 15′ 22″ O",
    location: [-25.256032, 17.225652],
  },
};
export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
