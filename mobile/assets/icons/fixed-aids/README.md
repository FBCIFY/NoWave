# NoWave fixed aids

Original geometric artwork created for NoWave in 2026, dedicated to CC0 1.0.
See LICENSE-CC0.md. No third-party drawing, sprite or style is incorporated.

`mobile/tool/make_fixed_aid_icons.py` generates these PNGs from the inline SVG
geometry with the existing development tool CairoSVG; no mobile dependency.
Beacons/lighthouses: 72×72 at density 3 (24 logical px before zoom scaling).
Lights: 72×72 at density 6 (12 logical px), a compact four-ray star. The neutral fallback reuses the small
existing dark dot, without implying an unqualified category.

Upright narrow supports with a foot distinguish beacons from floating buoys.
Four fixed lateral variants preserve published horizontal green/white or
red/white bands and their order. They require a lateral category consistent
with the declared IALA A/B system; a light colour alone never selects them.
The Môle Bérouard SHOM beacon is a verified green/white, starboard, IALA A case.
Four further variants preserve published red/grey and green/grey horizontal
bands (including reversed order), with the same strict lateral/IALA checks.
The SHOM Antibes marks FR000002555800001 and FR000002556200001 are verified
green/grey starboard and red/grey port cases; grey is never replaced by white.
Cardinal topmarks: north both up, south both down, east bases together, west
points together. The support band colours follow the existing qualified buoy
rules; these are abstract display symbols, not replicas of physical shapes.
Lighthouses use a small tower/lantern. Lights use a smaller coloured star with four rays, distinct from a fixed
support or floating buoy. Multi-colour or unknown light colour uses a neutral
lantern: no sector is inferred, and no characteristic text is drawn.

Regenerate: `python mobile/tool/make_fixed_aid_icons.py`
(after installing cairosvg in that development environment).
