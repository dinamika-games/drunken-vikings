#!/usr/bin/env python3

"""
Make the map of Lake Mälaren between Sigtuna and Birka for the sailing: the
water, with its islands, from the land cover of Lantmäteriet (Marktäcke, CC BY
4.0), in metres.

We download the land cover of the municipalities around the route (one
GeoPackage each, through the STAC API of Lantmäteriet), keep the polygons of
the water, merge them, clip them to the box of the level, simplify them, and
write data/world/malaren_map.json.

The coordinates are those of SWEREF 99 TM (EPSG:3006, metres east and north),
shifted so that the south-west corner of the box is the origin, with x east
and y SOUTH (as Godot draws), so that the game needs no projection.

The download needs a (free) account of Geotorget
(https://geotorget.lantmateriet.se). Pass the account in the environment
variables LANTMATERIET_USER and LANTMATERIET_PASSWORD, or put it in ~/.netrc:

  machine dl1.lantmateriet.se login <user> password <password>

Never commit the account. The downloads are cached in .cache/maps/.

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/maps/make_malaren_map.py [--inspect]

With --inspect, only print the layers and the kinds of land cover of the
downloads, to see what they hold.
"""

import argparse
import base64
import collections
import json
import netrc
import os
import pathlib
import sqlite3
import struct
import sys
import urllib.request
import zipfile
from typing import Dict, List, Optional, Tuple

import shapely
from shapely.geometry import box as make_box, mapping
from shapely.ops import unary_union

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CACHE_DIR = REPO_ROOT / ".cache" / "maps"
TARGET = REPO_ROOT / "data" / "world" / "malaren_map.json"

STAC_ITEMS = "https://api.lantmateriet.se/stac-vektor/v1/collections/marktacke/items/"
DOWNLOAD_HOST = "dl1.lantmateriet.se"

#: The municipalities around the route: Sigtuna, Upplands-Bro, Håbo,
#: Järfälla, Ekerö and Stockholm (for the shore of Hässelby).
MUNICIPALITIES = ["0191", "0139", "0305", "0123", "0125", "0180"]

#: The box of the level in SWEREF 99 TM: (west, south, east, north) in metres.
BOX = (636_000.0, 6_576_000.0, 666_000.0, 6_620_000.0)

#: Simplify the shores to this tolerance, in metres.
TOLERANCE_M = 8.0

#: Drop the islands and the ponds smaller than this, in square metres.
MIN_AREA_M2 = 2_000.0

#: The kinds of land cover (the column "objekttyp") which are water.
WATER_KINDS = {"Sjö", "Vattendragsyta", "Hav"}


def credentials() -> Tuple[str, str]:
    user = os.environ.get("LANTMATERIET_USER")
    password = os.environ.get("LANTMATERIET_PASSWORD")
    if user and password:
        return user, password
    try:
        entry = netrc.netrc().authenticators(DOWNLOAD_HOST)
    except (FileNotFoundError, netrc.NetrcParseError):
        entry = None
    if entry is not None and entry[0] and entry[2]:
        return entry[0], entry[2]
    raise RuntimeError(
        "The download needs an account of Geotorget: set LANTMATERIET_USER and "
        f"LANTMATERIET_PASSWORD, or add {DOWNLOAD_HOST} to ~/.netrc (see the docstring)."
    )


def download(code: str) -> pathlib.Path:
    """Download the land cover of the municipality, unless cached; return the GeoPackage."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    archive = CACHE_DIR / f"marktacke_kn{code}.zip"
    if not archive.exists():
        with urllib.request.urlopen(STAC_ITEMS + code, timeout=60) as response:
            item = json.load(response)
        href = item["assets"]["data"]["href"]
        print(f"Downloading {item['properties']['title']} from {href}")
        user, password = credentials()
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        request = urllib.request.Request(href, headers={"Authorization": f"Basic {token}"})
        partial = archive.with_suffix(".part")
        with urllib.request.urlopen(request, timeout=600) as response:
            partial.write_bytes(response.read())
        partial.rename(archive)

    with zipfile.ZipFile(archive) as zipped:
        names = [n for n in zipped.namelist() if n.endswith(".gpkg")]
        if len(names) != 1:
            raise RuntimeError(f"Expected one GeoPackage in {archive}, but got: {zipped.namelist()}")
        target = CACHE_DIR / pathlib.Path(names[0]).name
        if not target.exists():
            target.write_bytes(zipped.read(names[0]))
    return target


def geometry_of(blob: bytes) -> Optional[shapely.Geometry]:
    """Parse the geometry of a GeoPackage (its header, then WKB)."""
    if blob is None or blob[:2] != b"GP":
        return None
    flags = blob[3]
    envelope = (flags >> 1) & 0b111
    size = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[envelope]
    return shapely.from_wkb(blob[8 + size :])


def layers(connection: sqlite3.Connection) -> List[Tuple[str, str]]:
    """The feature tables of the GeoPackage and their geometry columns."""
    return list(connection.execute("SELECT table_name, column_name FROM gpkg_geometry_columns"))


def inspect(path: pathlib.Path) -> None:
    connection = sqlite3.connect(path)
    for table, column in layers(connection):
        columns = [row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')]
        count = connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
        print(f"  {table} ({count} rows), geometry {column}, columns {columns}")
        if "objekttyp" in columns:
            kinds = collections.Counter(
                row[0] for row in connection.execute(f'SELECT objekttyp FROM "{table}"')
            )
            print("    kinds:", dict(kinds.most_common()))


def water_of(path: pathlib.Path, clip: shapely.Geometry) -> List[shapely.Geometry]:
    connection = sqlite3.connect(path)
    found = []
    for table, column in layers(connection):
        columns = [row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')]
        if "objekttyp" not in columns:
            continue
        for kind, blob in connection.execute(f'SELECT objekttyp, "{column}" FROM "{table}"'):
            if kind not in WATER_KINDS:
                continue
            geometry = geometry_of(blob)
            if geometry is not None and geometry.intersects(clip):
                found.append(geometry)
    return found


def polygons(geometry: shapely.Geometry) -> List[shapely.Polygon]:
    if isinstance(geometry, shapely.Polygon):
        return [geometry]
    if isinstance(geometry, (shapely.MultiPolygon, shapely.GeometryCollection)):
        return [p for g in geometry.geoms for p in polygons(g)]
    return []


def ring(coordinates) -> List[List[float]]:
    """Shift a ring to the origin of the box, with y south, rounded to decimetres."""
    west, _, _, north = BOX
    return [[round(x - west, 1), round(north - y, 1)] for x, y in coordinates]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--inspect", action="store_true", help="only print what the downloads hold")
    args = parser.parse_args()

    packages = [download(code) for code in MUNICIPALITIES]
    if args.inspect:
        for path in packages:
            print(path.name)
            inspect(path)
        return 0

    clip = make_box(*BOX)
    pieces = []
    for path in packages:
        found = water_of(path, clip)
        print(f"{path.name}: {len(found)} polygons of water")
        pieces.extend(found)
    if not pieces:
        print("Found no water; check the kinds with --inspect.")
        return 1

    # NOTE (mristin):
    # The municipalities cut the lake at their borders; the union glues it
    # back together. A tiny buffer closes the slivers along the cuts.
    water = unary_union([p.buffer(0.5) for p in pieces]).buffer(-0.5).intersection(clip)
    water = water.simplify(TOLERANCE_M, preserve_topology=True)

    kept = []
    for polygon in polygons(water):
        if polygon.area < MIN_AREA_M2:
            continue
        islands = [r for r in polygon.interiors if shapely.Polygon(r).area >= MIN_AREA_M2]
        kept.append({"water": ring(polygon.exterior.coords), "islands": [ring(r.coords) for r in islands]})
    kept.sort(key=lambda p: -shapely.Polygon(p["water"]).area)

    west, south, east, north = BOX
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(
        json.dumps(
            {
                "source": (
                    "Lantmäteriet, Marktäcke (land cover), CC BY 4.0, "
                    f"municipalities {', '.join(MUNICIPALITIES)}"
                ),
                "projection": "SWEREF 99 TM (EPSG:3006), shifted: x = east - west, y = north - north_of_point",
                "box": {"west": west, "south": south, "east": east, "north": north},
                "size_m": [east - west, north - south],
                "tolerance_m": TOLERANCE_M,
                "lakes": kept,
            },
            separators=(",", ":"),
        )
    )
    points = sum(len(p["water"]) + sum(len(i) for i in p["islands"]) for p in kept)
    islands = sum(len(p["islands"]) for p in kept)
    print(f"Wrote {TARGET}: {len(kept)} bodies of water, {islands} islands, {points} points")
    return 0


if __name__ == "__main__":
    sys.exit(main())
