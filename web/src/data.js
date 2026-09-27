export const sources = {
  containers: {
    label: "OMI · Conteneurs perdus en mer",
    url: "https://www.imo.org/en/mediacentre/hottopics/pages/container-default.aspx",
  },
  whales: {
    label: "NOAA · Collisions avec les animaux marins",
    url: "https://www.fisheries.noaa.gov/national/endangered-species-conservation/vessel-strikes",
  },
  ice: {
    label: "US Coast Guard · International Ice Patrol",
    url: "https://www.navcen.uscg.gov/international-ice-patrol-about-us",
  },
  orcas: {
    label: "MITECO · Recommandations 2026",
    url: "https://www.miteco.gob.es/es/prensa/ultimas-noticias/2026/marzo/-disminuyen-en-espana-las-interacciones-con-orcas--excepto-en-el.html",
  },
  orcaBehavior: {
    label: "MITECO · Comprendre ces interactions",
    url: "https://www.miteco.gob.es/es/prensa/ultimas-noticias/2024/mayo/miteco-y-mitma-ofrecen-recomendaciones-a-los-navegantes-en-caso-.html",
  },
  pollution: {
    label: "OMI · Déchets marins",
    url: "https://www.imo.org/en/mediacentre/hottopics/pages/marinelitter-default.aspx",
  },
};

// These are illustrative scenes, never real observations or navigation data.
// Report categories mirror the mobile application and backend enum.
export const spots = [
  {
    id: "lighthouse",
    asset: "archipelago",
    number: "01",
    title: "Voir plus loin. Ensemble.",
    label: "La veille partagée",
    category: "LA MISSION NOWAVE",
    reportCategory: "obstruction",
    x: 62,
    y: 28,
    size: 185,
    color: "#d9edc3",
    coordinates: "43° 17′ N · 05° 22′ E",
    description:
      "Un phare ne voit pas tout. Un navigateur non plus. NoWave est un projet de carte maritime collaborative : partager ce que chacun observe pour donner aux autres une meilleure lecture de leur environnement.",
    reference:
      "Dans l’application : trois catégories — obstacle, animal marin et pollution — associées à une position, une heure et un commentaire.",
    takeaway:
      "Une observation utile est située, datée et décrite. Les signalements communautaires complètent la vigilance ; ils ne remplacent pas les informations officielles.",
  },
  {
    id: "nautilus",
    number: "02",
    title: "Tout ne se voit pas en surface.",
    label: "Ce qui affleure",
    category: "OBSTACLES · REGARDER AU-DELÀ DU DÉCOR",
    reportCategory: "obstruction",
    x: 32,
    y: 65,
    size: 160,
    color: "#efedb5",
    coordinates: "43° 15′ N · 05° 19′ E",
    description:
      "Le Nautilus est un clin d’œil à Jules Verne. Dans la vraie vie, un objet qui affleure peut être bien moins sympathique : cargaison perdue, débris ou obstacle à la navigation. Une petite silhouette peut cacher un risque important.",
    reference:
      "Le sous-marin est imaginaire. Le risque posé par les conteneurs perdus, lui, est documenté par l’Organisation maritime internationale.",
    takeaway:
      "Dans NoWave, la catégorie « Obstacle » permet de décrire ce qui a été observé et de le situer.",
    sources: ["containers"],
  },
  {
    id: "kraken",
    number: "03",
    title: "Pas besoin de huit bras.",
    label: "L’œil de l’équipage",
    category: "UN BON SIGNALEMENT EN QUELQUES GESTES",
    reportCategory: "marine_animal",
    x: 88,
    y: 59,
    size: 175,
    color: "#f2c4a8",
    coordinates: "43° 13′ N · 05° 28′ E",
    description:
      "Ce kraken est notre seul monstre imaginaire. Son rôle est très concret : rappeler qu’un signalement n’a pas besoin d’être un roman. Un animal observé, une position, une heure et une description factuelle donnent déjà des repères.",
    reference:
      "Un clin d’œil aux légendes de marins pour parler d’une vraie fonction : le signalement « Animal marin ». Ne signalez que ce que vous avez réellement observé.",
    takeaway:
      "Décrivez les faits sans inventer l’espèce, la taille ou l’intention de l’animal. En cas de doute, dites-le.",
  },
  {
    id: "pirate",
    number: "04",
    title: "Le trésor, c’est de le voir à temps.",
    label: "Épaves & débris",
    category: "OBSTACLES · LE DÉCOR PEUT TROMPER",
    reportCategory: "obstruction",
    x: 22,
    y: 32,
    size: 155,
    color: "#dfdcc2",
    coordinates: "43° 20′ N · 05° 17′ E",
    description:
      "Le bateau pirate fait partie du décor. Une épave, une cargaison ou un objet perdu peut en revanche présenter un danger pour la navigation et l’environnement. Un repère visible par un équipage peut échapper au suivant.",
    reference:
      "L’OMI traite les risques liés aux épaves et aux objets perdus depuis les navires, dont les conteneurs.",
    takeaway:
      "L’intérêt de NoWave : transformer une observation isolée en information géolocalisée, avec une description de ce qui est réellement visible.",
    sources: ["containers"],
  },
  {
    id: "duck",
    number: "05",
    title: "En mer, ce n’est pas un jouet.",
    label: "Plastiques à la dérive",
    category: "POLLUTION · PETIT OBJET, VRAI SUJET",
    reportCategory: "pollution",
    x: 16,
    y: 51,
    size: 145,
    color: "#b9e1e5",
    coordinates: "43° 16′ N · 05° 15′ E",
    description:
      "Notre canard géant fait sourire. Les déchets plastiques qui dérivent en mer ont leur place dans une tout autre histoire. La pollution marine fait partie des situations que NoWave permet de signaler.",
    reference:
      "Le canard est une métaphore visuelle, pas un animal à signaler. Les déchets marins sont un enjeu suivi par l’Organisation maritime internationale.",
    takeaway:
      "Choisissez « Pollution » et décrivez ce que vous observez. La démonstration ci-dessous reprend les catégories de l’application.",
    sources: ["pollution"],
  },
  {
    id: "whale",
    number: "06",
    title: "Majestueuse. Et vulnérable.",
    label: "Baleines & collisions",
    category: "ANIMAUX MARINS · PARTAGER LA MER",
    reportCategory: "marine_animal",
    x: 60,
    y: 82,
    size: 210,
    color: "#bbdce6",
    coordinates: "43° 11′ N · 05° 22′ E",
    description:
      "Une baleine n’est pas un obstacle ordinaire. Les collisions avec les bateaux peuvent blesser ou tuer des animaux marins. Ils restent difficiles à repérer et ne peuvent pas toujours éviter un navire qui approche.",
    reference:
      "Le risque documenté ici est la collision, pas une supposée agressivité des baleines. Les interactions avec certaines orques sont présentées dans une fiche distincte.",
    takeaway:
      "Une observation de cétacé se classe dans « Animal marin ». Consultez les consignes locales d’observation et de navigation pour préserver les animaux et les équipages.",
    sources: ["whales"],
  },
  {
    id: "bottle",
    number: "07",
    title: "Le bon message. Au bon endroit.",
    label: "Transmettre l’observation",
    category: "DU REGARD AU SIGNALEMENT",
    reportCategory: "pollution",
    x: 39,
    y: 94,
    size: 100,
    color: "#d3e7c6",
    coordinates: "43° 12′ N · 05° 18′ E",
    description:
      "La bouteille à la mer est poétique. Pour une observation utile, on préfère une position et une heure. C’est le cœur de NoWave : choisir une catégorie, préciser le lieu et ajouter un commentaire concis.",
    reference:
      "Le signalement manuel de l’application associe une catégorie, une position, une heure d’observation et un commentaire de 250 caractères maximum.",
    takeaway:
      "Essayez un exemple ci-dessous. La démonstration reste dans votre navigateur : aucun signalement n’est envoyé.",
  },
  {
    id: "observatory",
    asset: "observatory",
    number: "08",
    title: "Un repère n’est pas une certitude.",
    label: "L’observatoire",
    category: "COMPRENDRE LA CARTE",
    reportCategory: "obstruction",
    x: 87,
    y: 28,
    size: 155,
    color: "#c9d5ed",
    coordinates: "43° 21′ N · 05° 29′ E",
    description:
      "La mer bouge. Ce qui a été vu à un endroit peut avoir dérivé depuis. La date d’une observation compte autant que sa position. NoWave associe les signalements à une heure pour conserver ce contexte.",
    reference:
      "Dans la version actuelle du projet, les signalements ont une durée de validité de 24 heures. Cela ne garantit ni leur exactitude ni la disparition du danger.",
    takeaway:
      "Une carte sans signalement ne prouve pas l’absence de danger. La carte présentée ici est une illustration pédagogique.",
  },
  {
    id: "container",
    number: "09",
    title: "Livraison perdue. Danger bien réel.",
    label: "Conteneur à la dérive",
    category: "OBSTACLES · CONTENEURS PERDUS",
    reportCategory: "obstruction",
    x: 48,
    y: 69,
    size: 180,
    color: "#e8c5ab",
    coordinates: "43° 14′ N · 05° 20′ E",
    description:
      "Un conteneur tombé à la mer peut devenir un danger pour les navires, notamment les petites embarcations, et pour l’environnement. Celui-ci illustre un obstacle peu visible à la surface.",
    reference:
      "L’Organisation maritime internationale documente ces risques et encadre la déclaration des conteneurs perdus.",
    takeaway:
      "Dans NoWave : « Obstacle », une position, une heure et une description factuelle. Un signalement dans l’application ne remplace pas l’alerte aux autorités maritimes.",
    sources: ["containers"],
  },
  {
    id: "iceberg",
    number: "10",
    title: "La pointe ne raconte pas tout.",
    label: "Icebergs & glaces",
    category: "OBSTACLES · SOUS LA LIGNE DE FLOTTAISON",
    reportCategory: "obstruction",
    x: 77,
    y: 12,
    size: 120,
    color: "#c5e4ed",
    coordinates: "48° 10′ N · 48° 20′ O",
    description:
      "Notre coupe de glace rend visible ce qu’un regard en surface ne montre pas. Les icebergs représentent un risque de collision ; l’International Ice Patrol surveille leur présence dans l’Atlantique Nord et diffuse des informations aux navigateurs.",
    reference:
      "L’iceberg est placé dans cet archipel à titre pédagogique. Il ne s’agit pas d’une observation en Méditerranée ni d’une carte réelle de présence de glace.",
    takeaway:
      "Pour une navigation réelle en zone de glace, consultez les bulletins et avertissements officiels actualisés. NoWave ne remplace pas ces informations.",
    sources: ["ice"],
  },
  {
    id: "orca",
    number: "11",
    title: "Une rencontre qui se prépare.",
    label: "Orques & embarcations",
    category: "ANIMAUX MARINS · COMPRENDRE LES INTERACTIONS",
    reportCategory: "marine_animal",
    x: 78,
    y: 79,
    size: 190,
    color: "#c5deda",
    coordinates: "36° 03′ N · 05° 34′ O",
    description:
      "Certaines orques interagissent avec des embarcations dans les eaux ibériques. Ces contacts peuvent présenter des risques pour les bateaux et les personnes à bord. Ils ne justifient pas de présenter tous les cétacés comme agressifs.",
    reference:
      "Le MITECO distingue ces interactions d’une agression. Ses recommandations 2026 concernent notamment le détroit de Gibraltar, la Galice et la mer Cantabrique.",
    takeaway:
      "Consultez les zones et consignes officielles à jour avant de naviguer. Signaler une observation ne signifie ni s’approcher des animaux ni intervenir sur leur comportement.",
    sources: ["orcas", "orcaBehavior"],
  },
];

export const reportCategories = {
  obstruction: "Obstacle",
  marine_animal: "Animal marin",
  pollution: "Pollution",
};
export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
