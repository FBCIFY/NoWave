# GEBCO worldwide visual background

`gebco-2026-v1.tar.gz` contains the complete XYZ Web Mercator pyramid Z0–Z6
(5,461 WebP tiles, 256 px) and its provenance manifest. It is a versioned visual
asset, checked into the release so builds, cold starts and map movement never
depend on the availability of GEBCO's public services. The web image verifies
the archive checksum before extracting it. Nginx serves it directly at
`/api/v1/map/seafloor/gebco-2026-v1/{z}/{x}/{y}.webp`, with a one-year cache
lifetime. It does not use the API render pool, SQLite, OSM or the WMS providers.

The client requests a coarse parent before the Z6 overview, keeps tiles on disk,
then overlays EMODnet regional detail from Z5 after a 600 ms request delay.
Outside the EMODnet service's advertised bounds, only GEBCO is requested.
Source/layer order keeps regional transparent gaps open onto the global base.
Failure of either optional raster does not hide the map or the other layers.

## Data and limitations

GEBCO Bathymetric Compilation Group 2026 (2026). The GEBCO_2026 Grid — a
continuous terrain model for oceans and land at 15 arc-second intervals.
DOI: https://doi.org/10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa

This overview samples every eighth native cell (2 arc-minutes, approximately
3.7 km north–south). It provides coarse relief worldwide, not port-scale
detail. Z6 overzoom enlarges the same overview; it creates no finer data.
Positive elevations and TID-classified land (including dry land below sea level)
remain transparent; the coarsely sampled shoreline
can differ from the basemap shoreline. Pixels use the NoWave palette and WebP
RGB compression. They never supply soundings, numerical depth labels or
contours. Regional detail and numerical marine data retain their own sources.

GEBCO combines heterogeneous measured and interpolated data. Native grid
spacing does not guarantee uniform measurement resolution or precision.
GEBCO must not be used for navigation or safety at sea.
Public domain, with attribution and the GEBCO conditions of use:
https://www.gebco.net/data-products/gridded-bathymetry/terms-of-use

## Regenerate the asset explicitly

Use the Python environment installed from `backend/requirements.lock` (numpy,
Pillow; no new production dependency). From the repository root:

```sh
python backend/tools/prepare_gebco_background.py \
  /tmp/gebco-2026-stride8.dods /tmp/gebco-2026-tid-stride8.dods \
  deploy/marine/gebco-2026-v1.tar.gz --download
cd deploy/marine
sha256sum gebco-2026-v1.tar.gz > gebco-2026-v1.tar.gz.sha256
```

The preparation tool verifies the exact subset SHA-256 before rendering. The
temporary DAP2 subsets are about 223 MiB (elevations) and 56 MiB (classification),
and are not committed. Re-rendering may
produce different compressed bytes with a different Pillow/libwebp version;
review the pixels and update the archive checksum intentionally. A source or
palette change requires a new path version to preserve HTTP/mobile caches.
Run `backend/tests/unit/test_gebco_background.py` and the mobile controller
tests. Production promotion also checks a real static tile near Japan; rollback
verification remains compatible with the previous, pre-GEBCO web image.
