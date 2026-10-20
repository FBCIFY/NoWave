"""Offline bounded import of a public Shom survey archive (optional py7zr).

Retains original XYZ rows, never averages/interpolates depths. The finest served
grid (z16, 32px) minimum is sufficient for every nested coarser request grid.
Large archives are processed offline; neither archive nor full cloud is served.
"""

import argparse
import hashlib
import json
from pathlib import Path
import tempfile
from contextlib import nullcontext
import xml.etree.ElementTree as ET


def select_rows(path, bounds, minimum_depth=None):
    """Stream large XYZ files in awk; Python retains only selected rows.

    This avoids creating hundreds of millions of Python float/string objects.
    The output is an original row and its exact ASCII values, never a grid Z.
    """
    import os
    import subprocess
    import shutil

    west, south, east, north = bounds
    if not (-180 <= west < east <= 180 and -85 < south < north < 85):
        raise ValueError("Invalid geographic bounds")
    with path.open() as stream:
        header = [next(stream).strip() for _ in range(3)]
    if header[2] != "long(DD),lat(DD),depth(m - down positive - LAT)":
        raise ValueError("Unverified sounding unit/datum/header")
    program = r"""
      BEGIN { pi=atan2(0,-1) }
      NR<=3 { next }
      $1+0>=west && $1+0<=east && $2+0>=south && $2+0<=north {
        sub(/\r$/, "", $0)
        if (NF!=3 || $1 !~ /^-?[0-9]+(\.[0-9]+)?$/ ||
            $2 !~ /^-?[0-9]+(\.[0-9]+)?$/ || $3 !~ /^-?[0-9]+(\.[0-9]+)?$/) exit 2
        inside++
        if (limit_depth && $3+0 < minimum_depth) next
        phi=($2+0)*pi/180
        x=int((($1+0)+180)/360*1048576)
        y=int((1+log((1+sin(phi))/cos(phi))/pi)/2*1048576)
        key=x ":" y
        if (!(key in depth) || $3+0 < depth[key]) {
          depth[key]=$3+0; original[key]=$0; row[key]=NR
          if (length(depth)>100000) exit 3
        }
      }
      END {
        print NR-3 "\t" inside+0
        for (key in depth) print row[key] "\t" original[key]
      }
    """
    command = [
        shutil.which("mawk") or "awk",
        "-F,",
        "-v",
        f"west={west}",
        "-v",
        f"east={east}",
        "-v",
        f"south={south}",
        "-v",
        f"north={north}",
        "-v",
        f"limit_depth={int(minimum_depth is not None)}",
        "-v",
        f"minimum_depth={minimum_depth or 0}",
        program,
        str(path),
    ]
    result = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    lines = result.stdout.splitlines()
    total, inside = map(int, lines[0].split("\t"))
    rows = []
    for record in lines[1:]:
        row, xyz = record.split("\t", 1)
        rows.append((float(xyz.split(",")[2]), int(row), xyz))
    return header, total, inside, sorted(rows, key=lambda r: r[1])


def digest(path, algorithm="sha256"):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("survey")
    parser.add_argument("--expected-md5", required=True)
    parser.add_argument("--bounds", nargs=4, type=float, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--minimum-depth", type=float)
    args = parser.parse_args()
    if digest(args.archive, "md5") != args.expected_md5:
        raise ValueError("Archive differs from the public download file descriptor")
    import py7zr  # optional offline tooling only; not a serving dependency

    sid = args.survey
    if args.work_dir:
        args.work_dir.mkdir(parents=True, exist_ok=True)
    extraction = (
        nullcontext(args.work_dir)
        if args.work_dir
        else tempfile.TemporaryDirectory(prefix="shom-import-")
    )
    with extraction as temporary:
        root = Path(temporary)
        names = [f"{sid}/{sid}.xyz", f"{sid}/{sid}_LEVE_BATHY.xml"]
        with py7zr.SevenZipFile(args.archive) as archive:
            if not set(names) <= set(archive.getnames()):
                raise ValueError("Unexpected archive layout")
            archive.extract(root, targets=names)
        xyz, metadata = [root / name for name in names]
        xml = ET.parse(metadata).getroot()
        constraints = " ".join(xml.itertext())
        if "Open License (version 2.0" not in constraints:
            raise ValueError("Licence must be checked before redistribution")
        ns = {
            "gmd": "http://www.isotc211.org/2005/gmd",
            "gco": "http://www.isotc211.org/2005/gco",
        }
        dates = xml.findall(
            ".//gmd:identificationInfo//gmd:citation/gmd:CI_Citation/gmd:date/gmd:CI_Date",
            ns,
        )
        revisions = [
            d.find("gmd:date/gco:Date", ns).text
            for d in dates
            if d.find("gmd:dateType/gmd:CI_DateTypeCode", ns).get("codeListValue")
            == "revision"
        ]
        if not revisions:
            raise ValueError("No verified source revision")

        def time_value(tag):
            return next(e.text for e in xml.iter() if e.tag.endswith("}" + tag))

        header, total, inside, selected = select_rows(
            xyz, args.bounds, args.minimum_depth
        )
        if header[1] != sid:
            raise ValueError("Wrong survey identifier")
        args.output_dir.mkdir(parents=True, exist_ok=True)
        output = args.output_dir / f"{sid}.jsonl"
        output.write_text(
            "".join(
                json.dumps(dict(row=row, xyz=line), separators=(",", ":")) + "\n"
                for _, row, line in selected
            )
        )
        entry = dict(
            id=sid,
            file=output.name,
            sha256=digest(output),
            metadata_sha256=digest(metadata),
            archive_sha256=digest(args.archive),
            download_url=f"https://services.data.shom.fr/INSPIRE/telechargement/prepackageGroup/LEVES_BATHY_APRES_2005_PACK_DL/prepackage/{sid}/file/{sid}.7z",
            metadata_url=f"https://services.data.shom.fr/geonetwork/srv/api/records/{sid}_LEVE_BATHY",
            doi=f"https://dx.doi.org/10.17183/{sid}",
            acquisition_start=time_value("beginPosition"),
            acquisition_end=time_value("endPosition"),
            revision=max(revisions),
            license="etalab-2.0",
            count=len(selected),
            selection=dict(
                kind="original_row_minimum_per_mercator_cell",
                bounds=args.bounds,
                zoom=16,
                cell_pixels=32,
                minimum_depth=args.minimum_depth,
                source_header=header,
                source_xyz_sha256=digest(xyz),
                source_count=total,
                points_in_bounds=inside,
            ),
        )
        manifest_path = args.output_dir / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["surveys"] = [s for s in manifest["surveys"] if s["id"] != sid] + [
            entry
        ]
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        print(json.dumps(entry, indent=2))


if __name__ == "__main__":
    main()
