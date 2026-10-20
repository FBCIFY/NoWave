# NoWave buoy icons

Original: **Temaki `buoy`**, from the official Rapid Editor project:
https://github.com/rapideditor/temaki/blob/6d9ac860d1d615d4449aab049f630d25d036c19e/icons/buoy.svg

`buoy.svg` is the unmodified original. License: **CC0 1.0 Universal**,
included in `LICENSE-Temaki.md`. Retrieved 2026-10-16.

The eleven qualified PNG variants are NoWave adaptations: the same silhouette with a light
halo, a thin dark edge, and single colors or horizontal/vertical bands.
They are display symbols, not replicas of the feature's physical shape or
topmark. No light, light sector, label, or other seamark is drawn.

Regenerate locally (development dependency only):

```sh
python3 -m venv /tmp/buoy-icons
/tmp/buoy-icons/bin/pip install cairosvg
/tmp/buoy-icons/bin/python mobile/tool/make_buoy_icons.py
```

The `neutral.png` fallback is a plain dark dot (`#20262C`), without an outline
or a nautical silhouette. Its 12×12 canvas at density 3 is 4 logical pixels wide;
the disc itself is 3 logical pixels wide, before the existing zoom scale.
It uses the same qualification rules as the previous gray fallback.

Mapbox Flutter takes raster style images, so the qualified 72×72 PNGs are bundled
and registered at pixel ratio 3 (24 logical pixels at scale 1), without
an SVG runtime dependency. They are read once per `BuoyLayer` instance
and registered once per style, including after style reload.
