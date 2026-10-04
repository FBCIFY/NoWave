# NoWave — POC MapLibre

Application Flutter autonome du fond marin jour, sans compte ni clé API.
Voir [le guide de lancement et de test](../cartography/README.md).

Le relief provient du DEM réel externe Mapzen/AWS ; la bathymétrie, la côte
et les objets nautiques de démo restent fictifs. Le bandeau indique cette séparation.
Le serveur cartographique doit être lancé avant l'app.

```bash
# Terminal 1, depuis la racine du dépôt
python3 cartography/server.py --host 0.0.0.0

# Terminal 2
cd map_poc
flutter pub get
flutter run -d chrome --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

Android Emulator : remplacer 127.0.0.1 par 10.0.2.2 ; téléphone : IP du poste.
HTTP local autorisé pour le POC. Pas de GPS, cap, signalements ou Firebase.

Aperçu du relief réel autour de Cassis : lancer le serveur avec
`--relief-preview --center 5.53 43.205 --zoom 12`, puis la même app.
La mer de cet aperçu est unie, sans bathymétrie ; aucun objet fictif n'est déplacé.
Internet est requis pour les tuiles DEM. Crédits dans le style et dans le guide.

Le chargement MapLibre Web actif reste `MapLibreJsSource.cdn()` ; cette passe ne le modifie pas.
Les six scènes et le bilan graphique figurent dans [VISUAL_REVIEW.md](../cartography/VISUAL_REVIEW.md).
