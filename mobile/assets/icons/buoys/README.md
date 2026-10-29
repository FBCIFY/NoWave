# NoWave buoy icons

The twelve transparent PNGs are the supplied NoWave maritime palette. Each
canvas is 72×72 pixels. The eleven qualified symbols are registered at pixel
ratio 3 (24 logical pixels before zoom scaling). The small unqualified neutral
symbol is registered at pixel ratio 18 (4 logical pixels), preserving its
previous screen size despite its new 72×72 canvas.

Colours, cardinal topmarks, preferred-channel bands and the existing IALA A/B
selection rules remain defined by `BuoyLayer.imageExpression()`. A neutral
symbol never supplies a missing or contradictory nautical classification.
The new neutral artwork is a dark generic marker, not the previous plain dot.

`MarineIconImage` validates the PNG dimensions and passes the encoded PNG to
Mapbox Maps Flutter **2.30.1**. The Android bridge uses
`BitmapFactory.decodeByteArray`; the iOS bridge uses `UIImage(data:)`. Both
require an encoded image, despite the generic `MbxImage.data` documentation
mentioning raw premultiplied RGBA. Native decoding performs the pixel conversion.
Images are loaded once per layer instance and registered again after a style
reload; failed loads remain retryable.

Historical source: `buoy.svg` is the original Temaki buoy from Rapid Editor:
https://github.com/rapideditor/temaki/blob/6d9ac860d1d615d4449aab049f630d25d036c19e/icons/buoy.svg
Its CC0 licence remains in `LICENSE-Temaki.md`. The historical SVG and
`mobile/tool/make_buoy_icons.py` generate the old artwork, not these new PNGs.
