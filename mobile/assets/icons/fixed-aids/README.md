# Icônes d’aides fixes

La palette NoWave comprend 19 balises, cinq phares et cinq feux isolés.
Les PNG sont transparents, au format 72 × 72 px. Le ratio Mapbox vaut 3 pour
les balises et phares, 6 pour les feux isolés. Une balise non qualifiée reprend
le symbole neutre des bouées avec un ratio de 18.

`FixedAidLayer` applique les règles IALA A/B et conserve les couleurs et voyants
publiés. Le gris reste distinct du blanc. Une couleur de feu absente ou multiple
sélectionne l’icône par défaut ; le dessin ne définit aucun secteur lumineux.

`MarineIconImage` transmet les PNG encodés aux ponts natifs Mapbox 2.30.1.
Les images sont mises en cache par instance et restaurées après rechargement
du style. Un chargement en échec peut être relancé.

[LICENSE-CC0.md](LICENSE-CC0.md) couvre les anciens dessins géométriques NoWave.
`mobile/tool/make_fixed_aid_icons.py` recrée ces dessins, pas la palette actuelle.
