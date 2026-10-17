import time
from functools import lru_cache
from io import BytesIO

import httpx
from PIL import Image, ImageFilter


EMODNET_WMS_URL = "https://ows.emodnet-bathymetry.eu/wms"

# Échantillons RGB dans l'ordre de la légende GetLegendGraphic de
# mean_multicolour (Multi Colour non-linear), relevés hors des graduations.
# Référence : EMODNET_WMS_URL avec request=GetLegendGraphic,
# service=WMS, version=1.1.1, layer=emodnet:mean_multicolour, format=image/png.
# La position est celle du dégradé visuel, jamais une profondeur en mètres.
# Inclure le rouge rosé initial ET la baisse d'intensité du bleu final :
# ni la teinte HSV seule ni la luminance seule ne sont monotones ici.
_EMODNET_RAMP = (
    (54, (255, 96, 101)),
    (60, (253, 68, 80)),
    (66, (251, 34, 51)),
    (75, (255, 0, 7)),
    (81, (249, 56, 15)),
    (90, (250, 164, 12)),
    (96, (251, 224, 11)),
    (105, (249, 245, 7)),
    (114, (235, 250, 3)),
    (126, (206, 254, 0)),
    (138, (153, 251, 6)),
    (147, (110, 250, 25)),
    (156, (71, 249, 73)),
    (165, (31, 243, 149)),
    (174, (0, 231, 214)),
    (183, (8, 171, 230)),
    (192, (8, 92, 238)),
    (201, (0, 20, 245)),
    (210, (4, 8, 178)),
    (219, (1, 1, 94)),
    (228, (0, 0, 66)),  # Début du plateau bleu nuit final (~62–66).
)

_NOWAVE_RAMP = (
    (230, 247, 253),  # #E6F7FD
    (210, 240, 251),  # #D2F0FB
    (183, 228, 247),  # #B7E4F7
    (143, 208, 238),  # #8FD0EE
    (92, 179, 223),   # #5CB3DF
    (30, 111, 168),   # #1E6FA8
)

# Demi-circonférence du monde en Web Mercator EPSG:3857.
_WEB_MERCATOR_HALF_WORLD = 20037508.342789244

# Une requête initiale + deux nouvelles tentatives.
_RETRY_DELAYS = (0.25, 0.75)

# Erreurs temporaires pour lesquelles une nouvelle tentative a du sens.
_RETRYABLE_STATUS_CODES = {429, 502, 503, 504}

# On réutilise les connexions mais on force HTTP/1.1.
_client = httpx.Client(
    http2=False,
    follow_redirects=True,
    timeout=httpx.Timeout(10.0, connect=3.0),
    limits=httpx.Limits(
        max_connections=8,
        max_keepalive_connections=4,
    ),
    headers={
        "User-Agent": "NoWave bathymetry tile proxy",
    },
)


class BathymetryUnavailable(RuntimeError):
    """EMODnet n'a pas pu fournir la tuile demandée."""


@lru_cache(maxsize=1)
def _blue_color_lut() -> ImageFilter.Color3DLUT:
    """Construit une fois la LUT RGB, interpolée par Pillow pour chaque tuile."""

    segments = []
    first = _EMODNET_RAMP[0][0]
    span = _EMODNET_RAMP[-1][0] - first
    for (position, start), (end_position, end) in zip(
        _EMODNET_RAMP, _EMODNET_RAMP[1:]
    ):
        direction = tuple(b - a for a, b in zip(start, end))
        length_squared = sum(value * value for value in direction)
        segments.append((
            start, direction, length_squared,
            (position - first) / span, (end_position - position) / span,
        ))

    def transform(red: float, green: float, blue: float):
        red, green, blue = red * 255, green * 255, blue * 255
        closest_distance = float("inf")
        progress = 0.0
        # Projection sur la rampe RGB observée, uniquement à la construction
        # de la LUT 33³ ; aucune boucle Python par pixel de tuile.
        for start, direction, length_squared, offset, scale in segments:
            dr, dg, db = red - start[0], green - start[1], blue - start[2]
            vr, vg, vb = direction
            fraction = max(0.0, min(1.0, (
                dr * vr + dg * vg + db * vb
            ) / length_squared))
            distance = (
                (dr - fraction * vr) ** 2
                + (dg - fraction * vg) ** 2
                + (db - fraction * vb) ** 2
            )
            if distance < closest_distance:
                closest_distance = distance
                progress = offset + fraction * scale

        target = progress * (len(_NOWAVE_RAMP) - 1)
        index = min(int(target), len(_NOWAVE_RAMP) - 2)
        fraction = target - index
        return tuple(
            (a + fraction * (b - a)) / 255
            for a, b in zip(_NOWAVE_RAMP[index], _NOWAVE_RAMP[index + 1])
        )

    return ImageFilter.Color3DLUT.generate(33, transform)


def recolor_bathymetry_png(content: bytes) -> bytes:
    """Applique le dégradé visuel NoWave en préservant exactement l'alpha."""

    try:
        with Image.open(BytesIO(content)) as source:
            if source.format != "PNG":
                raise BathymetryUnavailable("Expected an EMODnet PNG tile")
            rgba = source.convert("RGBA")
        recolored = rgba.convert("RGB").filter(_blue_color_lut())
        recolored.putalpha(rgba.getchannel("A"))
        # Adoucissement visuel subpixel, sans mélanger le noir/blanc des
        # pixels sans données à la côte. L'alpha source reste strictement
        # inchangé : ce lissage ne modifie ni l'emprise ni les profondeurs.
        recolored = (
            recolored.convert("RGBa")
            .filter(ImageFilter.GaussianBlur(radius=0.65))
            .convert("RGBA")
        )
        recolored.putalpha(rgba.getchannel("A"))
        output = BytesIO()
        recolored.save(output, format="PNG")
        return output.getvalue()
    except (OSError, ValueError) as error:
        raise BathymetryUnavailable("Invalid EMODnet PNG tile") from error


def web_mercator_tile_bbox(
    z: int,
    x: int,
    y: int,
) -> tuple[float, float, float, float]:
    """Convertit une tuile XYZ en bbox EPSG:3857."""

    tiles = 1 << z
    tile_span = (2 * _WEB_MERCATOR_HALF_WORLD) / tiles

    min_x = -_WEB_MERCATOR_HALF_WORLD + x * tile_span
    max_x = min_x + tile_span

    max_y = _WEB_MERCATOR_HALF_WORLD - y * tile_span
    min_y = max_y - tile_span

    return min_x, min_y, max_x, max_y


def _request_tile(params: dict[str, str]) -> httpx.Response:
    """Interroge EMODnet avec quelques retries sur erreurs temporaires."""

    attempts = len(_RETRY_DELAYS) + 1
    last_error: Exception | None = None

    for attempt in range(attempts):
        try:
            response = _client.get(
                EMODNET_WMS_URL,
                params=params,
            )

            if response.status_code in _RETRYABLE_STATUS_CODES:
                raise httpx.HTTPStatusError(
                    f"Temporary upstream error {response.status_code}",
                    request=response.request,
                    response=response,
                )

            response.raise_for_status()
            return response

        except httpx.HTTPError as error:
            last_error = error

            retryable = isinstance(error, httpx.TransportError)

            if isinstance(error, httpx.HTTPStatusError):
                retryable = (
                    error.response.status_code
                    in _RETRYABLE_STATUS_CODES
                )

            if not retryable or attempt >= len(_RETRY_DELAYS):
                break

            time.sleep(_RETRY_DELAYS[attempt])

    raise BathymetryUnavailable(
        "EMODnet bathymetry service unavailable"
    ) from last_error


@lru_cache(maxsize=512)
def fetch_bathymetry_tile(
    z: int,
    x: int,
    y: int,
) -> bytes:
    """Récupère une tuile PNG et garde le résultat recoloré en cache."""

    bbox = web_mercator_tile_bbox(z, x, y)

    params = {
        "service": "WMS",
        "request": "GetMap",
        "version": "1.1.1",
        "layers": "emodnet:mean_multicolour",
        "styles": "",
        "format": "image/png",
        "transparent": "true",
        "width": "256",
        "height": "256",
        "srs": "EPSG:3857",
        "bbox": ",".join(f"{value:.6f}" for value in bbox),
    }

    response = _request_tile(params)

    content_type = response.headers.get(
        "content-type",
        "",
    ).lower()

    if not content_type.startswith("image/png"):
        raise BathymetryUnavailable(
            "Unexpected EMODnet response: "
            f"{content_type or 'unknown'}"
        )

    return recolor_bathymetry_png(response.content)
