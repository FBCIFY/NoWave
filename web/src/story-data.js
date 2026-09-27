// A continuous loop through the archipelago. Each stop explains an actual NoWave use.
export const journey = [
  {
    id: "lighthouse",
    label: "Le phare",
    theme: "LA VIGILANCE PARTAGÉE",
    title: ["Une même mer.", "Des regards qui comptent."],
    body: "On ne voit pas tous la même chose depuis son bateau. Une observation partagée aide à mieux comprendre ce qui nous entoure.",
    utility:
      "NoWave réunit les obstacles, les animaux marins et les pollutions observés sur une carte, avec une position et une heure.",
  },
  {
    id: "pirate",
    label: "L’épave",
    theme: "REPÉRER UN OBSTACLE",
    title: ["Un objet sur la route ?", "Un repère à partager."],
    body: "Épave, débris, cargaison perdue : un obstacle visible par un équipage peut échapper au suivant.",
    utility:
      "Choisissez « Obstacle » et situez ce que vous avez vu. Une description simple aide les autres à comprendre l’observation.",
    source: "containers",
  },
  {
    id: "duck",
    label: "Le plastique",
    theme: "SIGNALER UNE POLLUTION",
    title: ["Un canard pour sourire.", "Des déchets à signaler."],
    body: "Ce clin d’œil aux objets qui dérivent rappelle un enjeu bien réel : la présence de déchets en mer.",
    utility:
      "La catégorie « Pollution » permet de localiser une observation et de décrire les déchets ou traces visibles.",
    source: "pollution",
  },
  {
    id: "nautilus",
    label: "Le Nautilus",
    theme: "DÉCRIRE CE QUI EST VISIBLE",
    title: ["Ce qui affleure", "mérite un repère."],
    body: "Ce sous-marin est imaginaire. Dans la réalité, une petite partie visible peut appartenir à un obstacle plus important.",
    utility:
      "Décrivez ce que vous voyez. Si la nature de l’objet est incertaine, précisez-le dans votre commentaire.",
    source: "containers",
  },
  {
    id: "bottle",
    label: "Le message",
    theme: "UNE DESCRIPTION UTILE",
    title: ["Quelques mots.", "Un message clair."],
    body: "Pas besoin d’un roman pour partager une observation. Les détails concrets sont les plus utiles.",
    utility:
      "Ajoutez un commentaire de 250 caractères maximum : aspect, nombre d’objets, éléments visibles. La position et l’heure complètent le signalement.",
  },
  {
    id: "container",
    label: "Le conteneur",
    theme: "CONTENEURS À LA DÉRIVE",
    title: ["Localiser un obstacle.", "Partager sa présence."],
    body: "Un conteneur à la dérive présente un risque de collision, en particulier pour les petites embarcations.",
    utility:
      "Signalez-le dans « Obstacle », avec sa position, l’heure de l’observation et une description factuelle.",
    source: "containers",
  },
  {
    id: "whale",
    label: "La baleine",
    theme: "PRÉSENCE DE CÉTACÉS",
    title: ["Observer la faune.", "Partager la mer."],
    body: "Les collisions avec les navires peuvent blesser les cétacés. Signaler leur présence contribue à une vigilance partagée.",
    utility:
      "Choisissez « Animal marin ». Partagez le lieu et l’heure de l’observation, sans supposer les déplacements de l’animal.",
    source: "whales",
  },
  {
    id: "orca",
    label: "L’orque",
    theme: "RESTER FACTUEL",
    title: ["Une rencontre.", "Des faits à décrire."],
    body: "Certaines orques interagissent avec des embarcations. Observer une présence et décrire un contact sont deux informations différentes.",
    utility:
      "Précisez les faits observés dans « Animal marin ». Les recommandations officielles locales restent la référence pour la navigation.",
    source: "orcas",
  },
  {
    id: "kraken",
    label: "L’observation",
    theme: "BIEN CHOISIR SA CATÉGORIE",
    title: ["Pas besoin de huit bras.", "Juste des faits utiles."],
    body: "Notre clin d’œil aux légendes marines invite à rester précis : en mer, on partage ce que l’on a réellement observé.",
    utility:
      "Obstacle, animal marin ou pollution : choisissez la catégorie adaptée. Si vous ne connaissez pas l’espèce, décrivez-la sans l’inventer.",
  },
  {
    id: "observatory",
    label: "L’observatoire",
    theme: "GARDER LE CONTEXTE",
    title: ["La mer change.", "L’heure compte."],
    body: "Un objet peut dériver, un animal se déplacer. Une position se comprend toujours avec l’heure de l’observation.",
    utility:
      "NoWave date chaque signalement. Sa validité est de 24 heures dans le projet actuel ; cela ne signifie pas que le risque a disparu.",
  },
  {
    id: "iceberg",
    label: "Les glaces",
    theme: "COMPLÉTER LES INFORMATIONS OFFICIELLES",
    title: ["Voir la pointe.", "Garder une vue d’ensemble."],
    body: "Un iceberg rappelle que tout n’est pas visible à la surface. Une observation isolée ne décrit pas toute une zone.",
    utility:
      "Un signalement « Obstacle » apporte un repère daté. Il complète les informations officielles, sans remplacer les bulletins sur les glaces.",
    source: "ice",
  },
];
