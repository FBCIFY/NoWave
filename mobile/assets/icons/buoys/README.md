# Icônes de bouées

Les douze PNG NoWave sont transparents, au format 72 × 72 px.
Les onze symboles qualifiés utilisent un ratio Mapbox de 3, soit 24 points
avant le redimensionnement au zoom. Le symbole neutre utilise un ratio de 18,
soit 4 points.

`BuoyLayer.imageExpression()` choisit les couleurs, voyants et bandes selon
les règles IALA A/B. Une classification absente ou contradictoire garde le
symbole neutre.

`MarineIconImage` transmet les PNG encodés et leurs dimensions aux ponts natifs
Mapbox 2.30.1. Les images sont chargées une fois par instance, réinstallées après
un changement de style et réessayées en cas d’échec.

Le fichier historique `buoy.svg` vient de
[Temaki](https://github.com/rapideditor/temaki), sous CC0 ; sa licence est dans
[LICENSE-Temaki.md](LICENSE-Temaki.md). `mobile/tool/make_buoy_icons.py` recrée
les anciens dessins, pas les PNG actuels.
