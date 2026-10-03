# NoWave — POC MapLibre

Application Flutter autonome du fond marin jour, sans compte ni clé API.
Voir [le guide de lancement et de test](../cartography/README.md).

La scène fournie est entièrement fictive et porte un bandeau permanent.
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
