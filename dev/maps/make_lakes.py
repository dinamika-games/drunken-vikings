#!/usr/bin/env python3

"""
Make a lake system for a level: lakes joined by narrow sounds, with bays and
islands, and the route of the viking ship through it, from a start village to
a goal village. The names of the lakes, the sounds, the islands and the
villages are made up from Norse-sounding syllables, so that no real place is
meant.

Everything comes from the seed, so the same seed always gives the same lakes.
The map goes to data/world/<name>.json, in metres, with x east and y south
(as Godot draws):

* "water": the polygons of the water, each an outer ring and its holes (the
  islands);
* "route": the course of the viking ship, from the start to the goal;
* "labels": the names, each with its kind ("lake", "sound", "island" or
  "village") and where to write it;
* "places": the settlements (the home farm, the market, the healer's island,
  the inn, ...), each with its "id", "kind", "name", where it stands on the
  land ("at") and where its jetty is on the water ("jetty");
* "routes": the ways of the boats on the water between every two places
  (by "<id>|<id>"), away from the shores;
* "start" and "goal": the home farm and the market village, at the ends of the
  route of the viking ship.

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/maps/make_lakes.py [--seed 7] [--name lakes] [--plot out.png]
"""

import argparse
import json
import math
import pathlib
import random
import sys
from typing import List, Sequence, Tuple

import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

Vec = Tuple[float, float]

#: How long the route is, about, in metres.
ROUTE_LENGTH_M = 2600.0

#: How many lakes the route goes through; sounds join them.
LAKE_COUNT = 4

#: The half-width of the lakes and of the sounds, in metres.
LAKE_RADIUS_M = (160.0, 260.0)
SOUND_RADIUS_M = (45.0, 65.0)

#: How long a sound is against a lake, along the route.
SOUND_SHARE = 0.6

#: The water along the route is at least this wide on each side, in metres,
#: whatever the islands and the shores do.
CLEAR_M = 40.0

#: How much the shores wiggle, in metres.
SHORE_WIGGLE_M = 24.0

#: Simplify the shores to this tolerance, in metres.
TOLERANCE_M = 2.5

#: The margin of land around the water, in metres.
MARGIN_M = 300.0

# ---------------------------------------------------------------------------
# The names
# ---------------------------------------------------------------------------

#: The first parts of the names: animals, trees, stones, weather and the like.
STEMS = [
    "Ulv",
    "Ravn",
    "Björn",
    "Ask",
    "Ek",
    "Hjort",
    "Sten",
    "Svan",
    "Tor",
    "Brand",
    "Rim",
    "Vind",
    "Is",
    "Myr",
    "Guld",
    "Sol",
    "Mjöd",
    "Lo",
    "Örn",
    "Al",
    "Hägg",
    "Lind",
    "Gran",
    "Säl",
    "Häst",
    "Ugg",
    "Dimm",
    "Snö",
    "Kråk",
    "Varg",
    "Lax",
    "Gädd",
    "Ål",
    "Skog",
    "Berg",
    "Hall",
    "Kvarn",
    "Frost",
    "Storm",
    "Vass",
]

#: The middle parts, to make longer names now and then.
LINKS = ["a", "e", "s", "ar", "ing", ""]

#: The endings of each kind of name.
ENDINGS = {
    "lake": ["sjön", "fjärden", "vattnet"],
    "sound": ["sund", "strömmen", "näset"],
    "island": ["ö", "holmen", "ön", "skär"],
    "village": ["by", "vik", "hamn", "stad", "torp"],
}

#: Real places (and names too close to them) which we never make.
AVOID = {"Birka", "Sigtuna", "Uppsala", "Hedeby", "Ekerö", "Torö", "Askö", "Lovö", "Alby", "Ekby"}


def make_name(rng: random.Random, kind: str, used: set) -> str:
    for _ in range(200):
        stem = rng.choice(STEMS)
        link = rng.choice(LINKS) if rng.random() < 0.35 else ""
        ending = rng.choice(ENDINGS[kind])
        name = stem + link + ending
        # NOTE (mristin):
        # Avoid the doubled letters at the joint (e.g., "Snööng") which read badly.
        joint = (stem + link)[-1] + ending[0]
        if joint[0] == joint[1] or name in used or name in AVOID:
            continue
        used.add(name)
        return name
    raise RuntimeError(f"Could not make a new name of the kind {kind}")


# ---------------------------------------------------------------------------
# The geometry
# ---------------------------------------------------------------------------


class Noise1D:
    """A smooth noise along one axis: a sum of sines of random phases."""

    def __init__(self, rng: random.Random, wavelengths: Sequence[float]):
        self.waves = [
            (2 * math.pi / w, rng.uniform(0, 2 * math.pi), 1.0 / (i + 1)) for i, w in enumerate(wavelengths)
        ]
        self.norm = sum(a for _, _, a in self.waves)

    def __call__(self, x: float) -> float:
        return sum(a * math.sin(k * x + p) for k, p, a in self.waves) / self.norm


def catmull_rom(points: Sequence[Vec], step: float) -> List[Vec]:
    """A smooth curve through the points, sampled about every step metres."""
    padded = [points[0]] + list(points) + [points[-1]]
    result: List[Vec] = []
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1], padded[i], padded[i + 1], padded[i + 2]
        length = math.dist(p1, p2)
        count = max(2, int(length / step))
        for j in range(count):
            t = j / count
            t2, t3 = t * t, t * t * t
            result.append(
                tuple(
                    0.5
                    * (
                        2 * p1[c]
                        + (-p0[c] + p2[c]) * t
                        + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
                        + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3
                    )
                    for c in range(2)
                )
            )
    result.append(points[-1])
    return result


def route_points(rng: random.Random) -> List[Vec]:
    """The control points of the route: southwards, meandering east and west."""
    count = 2 * LAKE_COUNT + 1
    step = ROUTE_LENGTH_M / (count - 1)
    points = []
    x = 0.0
    for i in range(count):
        x = max(-550.0, min(550.0, x + rng.uniform(-280.0, 280.0)))
        points.append((x, i * step * rng.uniform(0.75, 0.95)))
    return points


def blob(rng: random.Random, center: Vec, radius: float, wiggle: float, count: int = 48) -> Polygon:
    """A round shape with a noisy edge."""
    noise = Noise1D(rng, [2 * math.pi, math.pi, math.pi / 2])
    ring = []
    for i in range(count):
        a = 2 * math.pi * i / count
        r = radius * (1.0 + wiggle * noise(a))
        ring.append((center[0] + r * math.cos(a), center[1] + r * math.sin(a)))
    return Polygon(ring).buffer(0)


def wiggle_ring(rng: random.Random, coords: Sequence[Vec], amplitude: float) -> List[Vec]:
    """Push the points of a ring in and out along its normals with a smooth noise."""
    ring = LineString(coords)
    length = ring.length
    count = max(16, int(length / 12.0))
    noise = Noise1D(rng, [length / max(1, int(length / w)) for w in (600.0, 260.0, 110.0, 45.0)])
    points = [ring.interpolate(length * i / count) for i in range(count)]
    result = []
    for i, p in enumerate(points):
        a = points[i - 1]
        b = points[(i + 1) % count]
        dx, dy = b.x - a.x, b.y - a.y
        norm = math.hypot(dx, dy) or 1.0
        offset = amplitude * noise(length * i / count)
        result.append((p.x - dy / norm * offset, p.y + dx / norm * offset))
    return result


def wiggle_polygon(rng: random.Random, polygon: Polygon, amplitude: float) -> Polygon:
    shell = wiggle_ring(rng, list(polygon.exterior.coords), amplitude)
    holes = [wiggle_ring(rng, list(r.coords), amplitude * 0.7) for r in polygon.interiors]
    return Polygon(shell, holes).buffer(0)


def polygons(geometry) -> List[Polygon]:
    if isinstance(geometry, Polygon):
        return [geometry]
    if hasattr(geometry, "geoms"):
        return [p for g in geometry.geoms for p in polygons(g)]
    return []


def make(seed: int) -> dict:
    rng = random.Random(seed)
    used: set = set()

    route = catmull_rom(route_points(rng), 20.0)
    line = LineString(route)
    length = line.length

    # NOTE (mristin):
    # The route alternates between lakes and sounds: the half-width of the
    # water along it rises and falls smoothly, with a lake at each end (for
    # the villages) and sounds between the lakes.
    sections = 2 * LAKE_COUNT - 1
    radii = []
    for i in range(sections):
        low, high = LAKE_RADIUS_M if i % 2 == 0 else SOUND_RADIUS_M
        radii.append(rng.uniform(low, high))

    # NOTE (mristin):
    # The sections take their share of the route: the sounds are short. Each
    # section keeps its width in its middle, and blends into the next near the
    # ends.
    weights = [1.0 if i % 2 == 0 else SOUND_SHARE for i in range(sections)]
    edges = [0.0]
    for w in weights:
        edges.append(edges[-1] + w / sum(weights) * length)

    def section_at(s: float) -> int:
        for i in range(sections):
            if s < edges[i + 1]:
                return i
        return sections - 1

    def radius_at(s: float) -> float:
        i = section_at(s)
        if i % 2 == 1:
            return radii[i]
        # NOTE (mristin):
        # A lake narrows down to the sound next to it over its last half, so
        # that the sounds stay narrow.
        start, end = edges[i], edges[i + 1]
        half = (end - start) / 2
        middle = start + half
        j = i + 1 if s > middle else i - 1
        if j < 0 or j >= sections:
            return radii[i]
        f = min(1.0, abs(s - middle) / half)
        f = f * f * (3 - 2 * f)
        return radii[i] * (1 - f) + radii[j] * f

    def section_of(point: Vec) -> int:
        return section_at(line.project(Point(point)))

    circles = []
    s = 0.0
    while s <= length:
        p = line.interpolate(s)
        circles.append(p.buffer(radius_at(s), quad_segs=12))
        s += 15.0
    water = unary_union(circles)

    # NOTE (mristin):
    # Bays: arms of water off the lakes, which lead nowhere, for the players
    # who explore (and to make the shores less like a pipe).
    for i in range(0, sections, 2):
        for _ in range(rng.randint(1, 3)):
            s = edges[i] + rng.uniform(0.2, 0.8) * (edges[i + 1] - edges[i])
            base = line.interpolate(s)
            angle = rng.uniform(0, 2 * math.pi)
            reach = radii[i] + rng.uniform(150.0, 400.0)
            bend = rng.uniform(-0.6, 0.6)
            arm = [(base.x, base.y)]
            for k in range(1, 5):
                a = angle + bend * k / 4
                arm.append((arm[-1][0] + reach / 4 * math.cos(a), arm[-1][1] + reach / 4 * math.sin(a)))
            width = rng.uniform(45.0, 110.0)
            water = water.union(LineString(arm).buffer(width, quad_segs=8))
            water = water.union(Point(arm[-1]).buffer(width * rng.uniform(1.2, 2.0), quad_segs=12))

    # NOTE (mristin):
    # Islands in the lakes, never in the way of the route.
    corridor = line.buffer(CLEAR_M + 25.0)
    islands = []
    for _ in range(400):
        if len(islands) >= 10:
            break
        center = (rng.uniform(*water.bounds[0::2]), rng.uniform(*water.bounds[1::2]))
        radius = rng.uniform(25.0, 110.0)
        island = blob(rng, center, radius, 0.35)
        if not water.buffer(-30.0).contains(island):
            continue
        if island.intersects(corridor) or any(island.distance(other) < 40.0 for other in islands):
            continue
        islands.append(island)
    water = water.difference(unary_union(islands)) if islands else water

    water = unary_union([wiggle_polygon(rng, p, SHORE_WIGGLE_M) for p in polygons(water)])
    # NOTE (mristin):
    # The wiggles must not close the way: the corridor along the route stays water.
    water = water.union(line.buffer(CLEAR_M, quad_segs=8))
    water = water.simplify(TOLERANCE_M, preserve_topology=True)
    water = max(polygons(water), key=lambda p: p.area)

    # The map starts at the origin, with a margin of land around the water.
    west, north, east, south = water.bounds
    dx, dy = MARGIN_M - west, MARGIN_M - north

    def shift(points) -> List[List[float]]:
        return [[round(x + dx, 1), round(y + dy, 1)] for x, y in points]

    labels = []

    # The lakes and the sounds, at the middle of their sections of the route.
    for i in range(sections):
        kind = "lake" if i % 2 == 0 else "sound"
        middle = line.interpolate((edges[i] + edges[i + 1]) / 2)
        p = middle
        if kind == "lake":
            # NOTE (mristin):
            # A lake writes its name a bit off the route, where the boats do not cover it.
            for side in (1, -1):
                q = Point(middle.x + side * radii[i] * 0.5, middle.y)
                if water.buffer(-40.0).contains(q):
                    p = q
                    break
        labels.append({"kind": kind, "name": make_name(rng, kind, used), "at": shift([(p.x, p.y)])[0]})

    # The islands, the larger first.
    for hole in sorted(water.interiors, key=lambda r: -Polygon(r).area):
        island = Polygon(hole)
        if island.area < 6000.0:
            continue
        p = island.representative_point()
        labels.append(
            {"kind": "island", "name": make_name(rng, "island", used), "at": shift([(p.x, p.y)])[0]}
        )

    places = place_settlements(rng, used, water, line, route, sections, section_of)
    # NOTE (mristin):
    # The healer lives on the largest island, which keeps its own name.
    largest_island = next((label for label in labels if label["kind"] == "island"), None)
    for place in places:
        if place["kind"] == "healer" and largest_island is not None:
            place["name"] = largest_island["name"]
            continue
        labels.append({"kind": "place", "name": place["name"], "at": place["at"]})
    print(f"Finding the routes between {len(places)} places on the water...")
    routes = find_routes(water, places)

    def shifted_place(place: dict) -> dict:
        return {
            "id": place["id"],
            "kind": place["kind"],
            "name": place["name"],
            "at": shift([place["at"]])[0],
            "jetty": shift([place["jetty"]])[0],
        }

    home = shifted_place(places[0])
    market = shifted_place(places[1])
    return {
        "seed": seed,
        "size_m": [round(east - west + 2 * MARGIN_M, 1), round(south - north + 2 * MARGIN_M, 1)],
        "water": [
            {"outer": shift(water.exterior.coords), "holes": [shift(r.coords) for r in water.interiors]}
        ],
        "route": shift(line.simplify(2.0).coords),
        "labels": [
            {**label, "at": label["at"] if label["kind"] != "place" else shift([label["at"]])[0]}
            for label in labels
        ],
        "places": [shifted_place(place) for place in places],
        "routes": {key: shift(points) for key, points in routes.items()},
        "nav": navigation_grid(water, places, dx, dy),
        "start": {"name": home["name"], "at": home["at"]},
        "goal": {"name": market["name"], "at": market["at"]},
    }


# ---------------------------------------------------------------------------
# The grid of the water, for the boats which find their own way (the pirates)
# ---------------------------------------------------------------------------

#: The cells of the navigation grid, in metres.
NAV_CELL_M = 8.0

#: The cells of the grid keep this far from the shores, in metres.
NAV_CLEARANCE_M = 10.0


def navigation_grid(water: Polygon, places: List[dict], dx: float, dy: float) -> dict:
    """
    The grid of the water for the path finding, in the shifted coordinates of
    the map: "cell" (metres), "cols", "rows", and "runs": for each row, the
    lengths of the runs of the cells, alternating, starting with a run of land
    (which may be empty). The free cells keep clear of the shores and of the
    jetties.
    """
    import numpy as np

    inner = water.buffer(-NAV_CLEARANCE_M).difference(jetty_zones(places))
    west, north, east, south = water.bounds
    cols = int((east - west + 2 * MARGIN_M) / NAV_CELL_M) + 1
    rows = int((south - north + 2 * MARGIN_M) / NAV_CELL_M) + 1
    # NOTE (mristin):
    # The centers of the cells, back in the coordinates of the water.
    xs = (np.arange(cols) + 0.5) * NAV_CELL_M - dx
    ys = (np.arange(rows) + 0.5) * NAV_CELL_M - dy
    gx, gy = np.meshgrid(xs, ys)
    free = shapely.contains_xy(inner, gx, gy)
    runs = []
    for row in free.tolist():
        lengths = []
        current = False
        count = 0
        for cell in row:
            if cell == current:
                count += 1
            else:
                lengths.append(count)
                current = cell
                count = 1
        lengths.append(count)
        runs.append(lengths)
    return {"cell": NAV_CELL_M, "cols": cols, "rows": rows, "runs": runs}


# ---------------------------------------------------------------------------
# The settlements and the routes between them
# ---------------------------------------------------------------------------

#: The settlements of the region, in the order of placing: (kind, the lake
#: (the section of the route, see make) where it lies, or "island", and the
#: endings of its name). The home farm lies at the start of the route and the
#: market village at its end, so that the first mission (follow the
#: longship) goes from home to the market.
SETTLEMENTS = [
    ("home", "start", ["gården", "torp"]),
    ("market", "end", ["stad", "hamn"]),
    ("healer", "island", ["ö", "holmen"]),
    ("inn", 1, ["vik", "näs"]),
    ("fishers", 0, ["vik", "hamn"]),
    ("brewer", 2, ["by", "torp"]),
    ("beekeeper", 4, ["by", "berga"]),
    ("horse_farm", 4, ["gården", "berga"]),
    ("weaver", 2, ["by", "vik"]),
    ("chieftain", 6, ["hall", "sala"]),
    ("farm", 0, ["gården", "torp"]),
    ("farm", 2, ["gården", "by"]),
    ("farm", 6, ["torp", "berga"]),
    ("mill", 2, ["kvarn", "by"]),
    ("smith", 4, ["by", "näs"]),
    ("potter", "island2", ["ö", "näs"]),
    ("herders", 6, ["berga", "torp"]),
    ("fishers", 4, ["vik", "näs"]),
    ("inn", 5, ["vik", "sund"]),
]

#: The jetty lies this far out from the shore, in metres.
JETTY_M = 18.0

#: The settlements stand at least this far apart, in metres.
MIN_PLACE_DISTANCE_M = 170.0

#: The NPC boats keep this far from the shores, in metres.
ROUTE_CLEARANCE_M = 14.0

#: The grid of the path finding, in metres.
GRID_M = 5.0

#: How close to a jetty the game takes a point for the jetty (see
#: LakeMap.JETTY_CLEARANCE), and where a boat lies beside its end (see
#: LakeMap.BERTH), in metres.
JETTY_CLEARANCE_M = 5.5
BERTH_M = 8.0

#: The boats which the game steers keep this far from a jetty (beyond
#: JETTY_CLEARANCE_M), but at their own berth, in metres (see
#: tests/godot/test_map.gd).
JETTY_KEEP_OFF_M = 4.0


def berth(place: dict) -> Vec:
    """Where a boat lies at the jetty of the place: beyond the end of the jetty, as in LakeMap."""
    (ax, ay), (jx, jy) = place["at"], place["jetty"]
    length = math.hypot(jx - ax, jy - ay)
    return (jx + (jx - ax) / length * BERTH_M, jy + (jy - ay) / length * BERTH_M)


def jetty_zones(places: List[dict]):
    """The water around the jetties, where the boats which the game steers do not go."""
    return unary_union(
        [
            LineString([place["at"], place["jetty"]]).buffer(JETTY_CLEARANCE_M + JETTY_KEEP_OFF_M)
            for place in places
        ]
    )


def make_place_name(rng: random.Random, endings: List[str], used: set) -> str:
    """A new name of a settlement, whose first part no other settlement has, so
    that the children do not mix them up."""
    for _ in range(400):
        stem = rng.choice(STEMS)
        if "stem:" + stem in used:
            continue
        name = stem + (rng.choice(LINKS) if rng.random() < 0.3 else "") + rng.choice(endings)
        if name in used or name in AVOID:
            continue
        used.add(name)
        used.add("stem:" + stem)
        return name
    raise RuntimeError("Could not make a new name of a place")


def shore_spots(water: Polygon, ring_coords, spacing: float = 30.0) -> List[Tuple[Vec, Vec]]:
    """
    The spots along a ring of the shore where a settlement could stand: each
    the point on the land and the point of the jetty out on the water.
    """
    ring = LineString(ring_coords)
    inner = water.buffer(-ROUTE_CLEARANCE_M)
    spots = []
    count = max(8, int(ring.length / spacing))
    for i in range(count):
        p = ring.interpolate(ring.length * i / count)
        a = ring.interpolate(ring.length * (i - 0.5) / count)
        b = ring.interpolate(ring.length * (i + 0.5) / count)
        nx, ny = -(b.y - a.y), b.x - a.x
        norm = math.hypot(nx, ny) or 1.0
        nx, ny = nx / norm, ny / norm
        for sign in (1.0, -1.0):
            jetty = (p.x + sign * nx * JETTY_M, p.y + sign * ny * JETTY_M)
            land = (p.x - sign * nx * 25.0, p.y - sign * ny * 25.0)
            if inner.contains(Point(jetty)) and not water.contains(Point(land)):
                spots.append((land, jetty))
                break
    return spots


def place_settlements(rng, used, water, line, route, sections, section_of) -> List[dict]:
    outer_spots = shore_spots(water, list(water.exterior.coords))
    island_rings = sorted(water.interiors, key=lambda r: -Polygon(r).area)
    places: List[dict] = []

    def far_enough(point: Vec) -> float:
        return min((math.dist(point, p["at"]) for p in places), default=1e9)

    def nearest(spots, target: Vec):
        return min(spots, key=lambda spot: math.dist(spot[1], target))

    for kind, where, endings in SETTLEMENTS:
        if where == "start":
            spot = nearest(outer_spots, route[0])
        elif where == "end":
            spot = nearest(outer_spots, route[-1])
        elif where in ("island", "island2"):
            # NOTE (mristin):
            # The healer lives on the largest island, with the jetty towards the
            # route; another settlement on the second largest.
            index = 0 if where == "island" else 1
            ring = island_rings[index] if len(island_rings) > index else None
            spots = shore_spots(water, list(ring.coords)) if ring is not None else outer_spots
            spot = min(spots, key=lambda s: line.distance(Point(s[1])))
        else:
            candidates = [s for s in outer_spots if section_of(s[1]) == min(where, sections - 1)]
            candidates = [s for s in candidates if far_enough(s[0]) >= MIN_PLACE_DISTANCE_M] or [
                s for s in outer_spots if far_enough(s[0]) >= MIN_PLACE_DISTANCE_M
            ]
            if not candidates:
                raise RuntimeError(f"No room for the settlement {kind}")
            # NOTE (mristin):
            # Among the free spots, prefer one far from the others (but not always the farthest).
            candidates.sort(key=lambda s: -far_enough(s[0]))
            spot = candidates[rng.randint(0, min(2, len(candidates) - 1))]
        # NOTE (mristin):
        # A kind may come more than once (two inns, three farms): the id counts them.
        same = sum(1 for p in places if p["kind"] == kind)
        places.append(
            {
                "id": kind if same == 0 else f"{kind}_{same + 1}",
                "kind": kind,
                "name": make_place_name(rng, endings, used),
                "at": spot[0],
                "jetty": spot[1],
            }
        )
    return places


def find_routes(water: Polygon, places: List[dict]) -> dict:
    """
    The routes of the boats between every two places, from berth to berth,
    along the water and away from the shores and the jetties: a shortest path
    on a grid, straightened where the water lets it.
    """
    import heapq

    import numpy as np

    inner = water.buffer(-ROUTE_CLEARANCE_M).difference(jetty_zones(places))
    west, north, east, south = water.bounds
    cols = int((east - west) / GRID_M) + 1
    rows = int((south - north) / GRID_M) + 1
    xs = west + np.arange(cols) * GRID_M
    ys = north + np.arange(rows) * GRID_M
    gx, gy = np.meshgrid(xs, ys)
    free = shapely.contains_xy(inner, gx, gy)

    def cell(point: Vec) -> Tuple[int, int]:
        c = int(round((point[0] - west) / GRID_M))
        r = int(round((point[1] - north) / GRID_M))
        if free[r, c]:
            return r, c
        # The nearest free cell.
        best = None
        for radius in range(1, 20):
            for dr in range(-radius, radius + 1):
                for dc in range(-radius, radius + 1):
                    rr, cc = r + dr, c + dc
                    if 0 <= rr < rows and 0 <= cc < cols and free[rr, cc]:
                        d = dr * dr + dc * dc
                        if best is None or d < best[0]:
                            best = (d, rr, cc)
            if best is not None:
                return best[1], best[2]
        raise RuntimeError(f"No water near {point}")

    steps = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0)] + [
        (dr, dc, math.sqrt(2.0)) for dr in (-1, 1) for dc in (-1, 1)
    ]
    free_list = free.tolist()

    def dijkstra(source: Tuple[int, int]):
        distance = {source: 0.0}
        parent = {}
        queue = [(0.0, source)]
        while queue:
            d, (r, c) = heapq.heappop(queue)
            if d > distance.get((r, c), 1e18):
                continue
            for dr, dc, cost in steps:
                rr, cc = r + dr, c + dc
                if 0 <= rr < rows and 0 <= cc < cols and free_list[rr][cc]:
                    nd = d + cost
                    if nd < distance.get((rr, cc), 1e18):
                        distance[(rr, cc)] = nd
                        parent[(rr, cc)] = (r, c)
                        heapq.heappush(queue, (nd, (rr, cc)))
        return parent

    def straighten(points: List[Vec]) -> List[Vec]:
        result = [points[0]]
        i = 0
        while i < len(points) - 1:
            j = len(points) - 1
            while j > i + 1 and not inner.contains(LineString([points[i], points[j]])):
                j -= 1
            result.append(points[j])
            i = j
        return result

    routes = {}
    berths = [berth(place) for place in places]
    cells = [cell(point) for point in berths]
    for a, place in enumerate(places):
        parent = dijkstra(cells[a])
        for b in range(a + 1, len(places)):
            path = [cells[b]]
            while path[-1] != cells[a]:
                if path[-1] not in parent:
                    raise RuntimeError(f"No way on the water from {place['id']} to {places[b]['id']}")
                path.append(parent[path[-1]])
            path.reverse()
            points = [berths[a]] + [(west + c * GRID_M, north + r * GRID_M) for r, c in path] + [berths[b]]
            routes[f"{place['id']}|{places[b]['id']}"] = straighten(points)
    return routes


def plot(data: dict, path: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    width, height = data["size_m"]
    figure, axis = plt.subplots(figsize=(8, 8 * height / width))
    axis.set_facecolor("#7a8a4a")
    for polygon in data["water"]:
        xs, ys = zip(*polygon["outer"])
        axis.fill(xs, ys, color="#3d6f9c")
        for hole in polygon["holes"]:
            xs, ys = zip(*hole)
            axis.fill(xs, ys, color="#7a8a4a")
    for points in data.get("routes", {}).values():
        xs, ys = zip(*points)
        axis.plot(xs, ys, color="white", linewidth=0.5, alpha=0.5)
    xs, ys = zip(*data["route"])
    axis.plot(xs, ys, color="#f2c14e", linewidth=1, linestyle="--")
    for place in data.get("places", []):
        axis.plot(*place["jetty"], "o", color="#f2c14e", markersize=3)
        axis.plot(*place["at"], "s", color="#8a3b2a", markersize=5)
    for label in data["labels"]:
        x, y = label["at"]
        axis.text(
            x,
            y,
            label["name"],
            fontsize=7,
            ha="center",
            color="white" if label["kind"] != "place" else "black",
        )
    axis.set_xlim(0, width)
    axis.set_ylim(height, 0)
    axis.set_aspect("equal")
    figure.tight_layout()
    figure.savefig(path, dpi=110)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--seed", type=int, default=7, help="the seed of the lakes")
    parser.add_argument("--name", default="lakes", help="write data/world/<name>.json")
    parser.add_argument("--plot", help="also draw the map into this PNG")
    args = parser.parse_args()

    data = make(args.seed)
    target = REPO_ROOT / "data" / "world" / f"{args.name}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False))
    points = sum(len(p["outer"]) + sum(len(h) for h in p["holes"]) for p in data["water"])
    print(
        f"Wrote {target}: {data['size_m'][0]:.0f} x {data['size_m'][1]:.0f} m, {points} points, "
        f"{len(data['water'][0]['holes'])} islands, route {LineString(data['route']).length:.0f} m, "
        f"from {data['start']['name']} to {data['goal']['name']}"
    )
    for label in data["labels"]:
        if label["kind"] != "place":
            print(f"  {label['kind']:8s} {label['name']}")
    for place in data["places"]:
        print(f"  {place['kind']:10s} {place['name']}")
    print(f"  {len(data['routes'])} routes between the places")
    if args.plot:
        plot(data, args.plot)
        print(f"Plotted into {args.plot}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
