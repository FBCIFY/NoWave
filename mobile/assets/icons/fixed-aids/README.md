# NoWave fixed aids

The supplied NoWave maritime palette contains 19 beacon variants, five
lighthouses and five isolated-light variants. All PNGs are transparent 72×72
images. Beacons and lighthouses use pixel ratio 3 (24 logical pixels before
zoom scaling); isolated lights use pixel ratio 6 (12 logical pixels).
The unqualified beacon fallback reuses the buoy neutral image at ratio 18
(4 logical pixels), without deriving a qualified beacon from its light colour.

`FixedAidLayer` retains the existing IALA A/B checks and the published order
of green/white, red/white, green/grey and red/grey bands. Grey is never replaced
by white. Cardinal topmarks remain north both up, south both down, east bases
together, west points together. Isolated danger retains two black spheres;
safe water retains vertical red/white bands and a red sphere. Unknown or
multiple light colours select the default icon; no geographical light sector
is inferred from the artwork.

`MarineIconImage` supplies encoded PNG bytes with their decoded dimensions,
as required by the Android and iOS bridges of Mapbox Maps Flutter 2.30.1.
Images are cached per layer instance, restored after style reloads, and loading
errors are propagated so a later installation can retry.

`LICENSE-CC0.md` and `mobile/tool/make_fixed_aid_icons.py` document the historical
NoWave geometric drawings. That generator recreates the old artwork and must
not be used to regenerate the new supplied palette.
