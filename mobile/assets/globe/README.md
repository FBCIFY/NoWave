# NoWave globe assets

These are geographic data derivatives, not derivatives of the user's reference
photograph. Rebuild with `tool/prepare_globe_assets.py` (Python, numpy, Pillow).
`provenance.json` records input URLs and input/output SHA-256 hashes.

## Clouds

NASA Blue Marble cloud mosaic (2002), from:
https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/cloud_combined_2048.jpg

Original catalogue: https://visibleearth.nasa.gov/images/57747/blue-marble-clouds
(the old catalogue now redirects to NASA Earth Observatory).

Credit: NASA Goddard Space Flight Center / Blue Marble.
The grayscale world mosaic is sampled into four 512 × 512 Web Mercator PNGs.
Brightness becomes cloud opacity. A fixed artistic solar mask is composited
over it, using a sun direction of 35° W / 35° N. This is neither live weather
nor a representation of the current day/night boundary. The map engine projects
the four geographic quadrants onto the interactive globe; they are not screen
overlays. The Mercator texture ends at ±85.05113°, as documented by Mapbox.

## Moon

NASA Scientific Visualization Studio, CGI Moon Kit (2019 color map):
https://svs.gsfc.nasa.gov/4720/
https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_poles_1k.jpg

Credit: NASA's Scientific Visualization Studio / Ernie Wright; LRO / LROC.
The near-side color map is orthographically projected into a 128 × 128 PNG.
The Moon's screen position is decorative and has no astronomical meaning.

## Near-camera cloud passage

`cloud-passage-atlas.png` contains three different 512 × 512 cloud banks derived
from the same NASA grayscale mosaic, with transparent irregular margins and
diffuse lighting encoded offline. It adds no weather API. These are decorative
foreground planes during Z4.5–Z6.2; the geographic clouds above remain unchanged.
Rebuild with `tool/prepare_cloud_passage.py`. Input hash, crop coordinates and
output hash are recorded separately in `cloud-passage-provenance.json`.

## Usage and cost

NASA content is generally available for factual/informational uses, with source
credit and without implying endorsement; third-party exceptions must be checked:
https://www.nasa.gov/nasa-brand-center/images-and-media/
These inputs contain no logos, people or identified third-party copyright notice.
No NASA network calls, service subscriptions or live weather API in the app.

Mapbox Satellite is fetched through the existing native SDK and existing token;
it is not copied into these assets. Mapbox licensing, attribution and applicable
account usage charges still apply. Free unlimited satellite access is not assumed:
https://docs.mapbox.com/data/tilesets/reference/mapbox-satellite/
https://docs.mapbox.com/flutter/maps/guides/pricing/
