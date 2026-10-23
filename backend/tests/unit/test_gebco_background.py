"""Offline global coverage and provenance; never contact GEBCO in tests."""

import hashlib
from io import BytesIO
import json
from pathlib import Path
import tarfile

import numpy as np
from PIL import Image
import pytest

from tools.prepare_gebco_background import colour_tile, sample_tile, SOURCE_SHA256, TID_SHA256

ROOT = Path(__file__).resolve().parents[3]
ARTIFACT = ROOT / "deploy/marine/gebco-2026-v2.tar.gz"


def test_complete_versioned_world_pyramid_and_pinned_provenance():
    expected = ARTIFACT.with_suffix(".gz.sha256").read_text().split()[0]
    with ARTIFACT.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == expected
    with tarfile.open(ARTIFACT) as archive:
        members = archive.getmembers()
        assert all(member.isfile() and member.mode == 0o644 for member in members)
        manifest = json.load(archive.extractfile("gebco-2026-v2/manifest.json"))
        assert manifest["source_sha256"] == SOURCE_SHA256
        assert manifest["land_mask_sha256"] == TID_SHA256
        assert manifest["sample_arc_minutes"] == 2
        assert "not for navigation" in manifest["usage"]
        expected_names = {f"gebco-2026-v2/{z}/{x}/{y}.webp"
                          for z in range(7) for x in range(1 << z) for y in range(1 << z)}
        assert manifest["tile_count"] == len(expected_names) == 5461
        assert {member.name for member in members} == expected_names | {"gebco-2026-v2/manifest.json"}
        for member in members:
            if member.name in expected_names:
                with Image.open(archive.extractfile(member)) as image:
                    assert image.format == "WEBP"
                    assert image.size == (256, 256)
                    image.verify()


@pytest.mark.parametrize("x,y", [(57, 25), (24, 36), (59, 38), (10, 24), (33, 23)])
def test_real_ocean_pixels_in_japan_brazil_australia_california_mediterranean(x, y):
    with tarfile.open(ARTIFACT) as archive:
        image = Image.open(archive.extractfile(f"gebco-2026-v2/6/{x}/{y}.webp")).convert("RGBA")
    pixels = np.array(image)
    ocean = pixels[:, :, 3] > 0
    assert ocean.mean() > .05  # Some coastal XYZ tiles contain mostly land.
    assert np.unique(pixels[:, :, :3][ocean], axis=0).shape[0] > 20


def test_land_stays_transparent_and_depth_colour_is_only_visual():
    depth = np.full((256, 256), 4000.)
    ocean = np.ones((256, 256))
    ocean[:, :100] = 0
    result = np.array(Image.open(BytesIO(colour_tile(depth, ocean))).convert("RGBA"))
    assert not result[:, :100, 3].any()
    assert (result[:, 101:, 3] == 255).all()
    assert np.all(result[:, 110:, 2] > result[:, 110:, 0])


def test_projected_grid_wraps_at_date_line_and_excludes_positive_land_from_depth():
    class Grid:
        shape = (5400, 10800)

        def __getitem__(self, index):
            lat, lon = index
            # Force a mixed coastline along the date line. Positive land must
            # contribute opacity only, never a fake shallow ocean depth.
            return np.broadcast_to(np.where(lon % 2, 8000, -1000), (len(lat), lon.shape[1]))

    class Tid:
        def __getitem__(self, index):
            return 40  # Predicted ocean, intentionally not original soundings.

    for x in (0, 63):
        depth, covered = sample_tile(Grid(), Tid(), 6, x, 31)
        assert np.isfinite(depth).all()
        assert np.allclose(depth[covered > 0], 1000)
        assert (covered >= 0).all() and (covered <= 1).all()


def test_official_land_classification_excludes_dry_land_below_sea_level():
    class Grid:
        shape = (5400, 10800)

        def __getitem__(self, index):
            return -80

    class Tid:
        def __getitem__(self, index):
            return 0  # Land, including dry depressions with negative elevation.

    depth, covered = sample_tile(Grid(), Tid(), 6, 10, 24)
    assert not covered.any()
    assert not depth.any()


def test_coarse_ocean_colour_excludes_unknown_coast_and_bilinear_neighbours():
    depth = np.full((258, 258), 4000.)
    coverage = np.ones((258, 258))
    coverage[81:121, 81:121] = 0
    image = Image.open(BytesIO(colour_tile(depth, coverage, padding=1))).convert("RGBA")
    alpha = np.array(image)[:, :, 3]
    assert alpha.shape == (256, 256)
    assert not alpha[79:121, 79:121].any()
    assert alpha[78, 100] == 255
    assert alpha[122, 100] == 255
