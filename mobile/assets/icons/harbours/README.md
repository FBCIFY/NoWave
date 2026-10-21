# NoWave ports and marinas

Two supplied NoWave maritime PNGs, transparent and 72×72 pixels:

| Asset | Mapbox image ID | Tile category |
| --- | --- | --- |
| `port.png` | `nowave-harbour` | Other qualified harbour categories |
| `marina.png` | `nowave-marina` | `marina` |

Both are registered at pixel ratio 3 (24 logical pixels before the existing
zoom interpolation). `HarbourLayer` keeps the Z6 threshold, collision rules,
source coordinates, categories and rendering priorities unchanged.

The native bridges of Mapbox Maps Flutter 2.30.1 decode encoded PNG bytes;
`MarineIconImage` preserves that format and reads the real dimensions.
Installation is idempotent, retries after errors, and restores both images
when Mapbox reloads the style.
