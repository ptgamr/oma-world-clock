#!/usr/bin/env python3
"""Build a compact, map-scale timezone lookup asset from GeoJSON."""

from __future__ import annotations

import argparse
import json
from math import hypot
from pathlib import Path
from typing import Any, Iterable


SOURCE_NAME = "timezone-boundary-builder"
SOURCE_RELEASE = "2026c"
SOURCE_URL = (
    "https://github.com/evansiroky/timezone-boundary-builder/releases/"
    "download/2026c/timezones.geojson.zip"
)
SOURCE_SHA256 = "7d3f0c5a33b6acd891335c0ad5ba767736b6914cb1a1d68c71921c17ce358948"
LICENSE = "ODbL-1.0"
LICENSE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"


Point = list[float]
Ring = list[Point]


def segment_distance(point: Point, start: Point, end: Point) -> float:
    """Return the Euclidean distance from a point to a line segment."""

    dx = end[0] - start[0]
    dy = end[1] - start[1]
    if dx == 0 and dy == 0:
        return hypot(point[0] - start[0], point[1] - start[1])
    position = max(
        0.0,
        min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / (dx * dx + dy * dy)),
    )
    return hypot(point[0] - (start[0] + position * dx), point[1] - (start[1] + position * dy))


def simplify_line(points: Ring, tolerance: float) -> Ring:
    """Simplify an open line with the Ramer-Douglas-Peucker algorithm."""

    if len(points) <= 2:
        return points[:]
    largest_distance = 0.0
    largest_index = 0
    for index in range(1, len(points) - 1):
        distance = segment_distance(points[index], points[0], points[-1])
        if distance > largest_distance:
            largest_distance = distance
            largest_index = index
    if largest_distance <= tolerance:
        return [points[0], points[-1]]
    return (
        simplify_line(points[: largest_index + 1], tolerance)[:-1]
        + simplify_line(points[largest_index:], tolerance)
    )


def simplify_ring(raw_points: Iterable[Iterable[float]], tolerance: float, precision: int) -> Ring:
    """Simplify a closed ring without collapsing it into a line."""

    points: Ring = []
    for raw_point in raw_points:
        point = [float(raw_point[0]), float(raw_point[1])]
        if not points or point != points[-1]:
            points.append(point)
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        return []

    pivot = max(
        range(1, len(points)),
        key=lambda index: hypot(points[index][0] - points[0][0], points[index][1] - points[0][1]),
    )
    simplified = simplify_line(points[: pivot + 1], tolerance)[:-1]
    simplified += simplify_line(points[pivot:] + [points[0]], tolerance)[:-1]
    if len(simplified) < 3:
        simplified = points

    rounded: Ring = []
    for longitude, latitude in simplified:
        point = [round(longitude, precision), round(latitude, precision)]
        if not rounded or point != rounded[-1]:
            rounded.append(point)
    if len(rounded) < 3:
        return []
    if rounded[0] != rounded[-1]:
        rounded.append(rounded[0])
    return rounded if len(rounded) >= 4 else []


def bounds_for_rings(rings: list[Ring], precision: int) -> list[float]:
    points = [point for ring in rings for point in ring]
    return [
        round(min(point[0] for point in points), precision),
        round(min(point[1] for point in points), precision),
        round(max(point[0] for point in points), precision),
        round(max(point[1] for point in points), precision),
    ]


def source_polygons(geometry: dict[str, Any]) -> list[list[list[list[float]]]]:
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])
    if geometry_type == "Polygon":
        return [coordinates]
    if geometry_type == "MultiPolygon":
        return coordinates
    raise ValueError(f"Unsupported geometry type: {geometry_type}")


def compact_zone(feature: dict[str, Any], tolerance: float, precision: int) -> dict[str, Any] | None:
    polygons: list[list[Any]] = []
    for source_polygon in source_polygons(feature["geometry"]):
        if not source_polygon:
            continue
        outer = simplify_ring(source_polygon[0], tolerance, precision)
        if not outer:
            continue
        rings = [outer]
        rings.extend(
            ring
            for raw_ring in source_polygon[1:]
            if (ring := simplify_ring(raw_ring, tolerance, precision))
        )
        polygons.append([bounds_for_rings([rings[0]], precision), rings])
    if not polygons:
        return None
    zone_bounds = [
        min(polygon[0][0] for polygon in polygons),
        min(polygon[0][1] for polygon in polygons),
        max(polygon[0][2] for polygon in polygons),
        max(polygon[0][3] for polygon in polygons),
    ]
    return {
        "id": str(feature["properties"]["tzid"]),
        "bounds": zone_bounds,
        "polygons": polygons,
    }


def convert(source: Path, tolerance: float = 0.08, precision: int = 2) -> dict[str, Any]:
    data = json.loads(source.read_text(encoding="utf-8"))
    zones = []
    for feature in data.get("features", []):
        zone = compact_zone(feature, tolerance, precision)
        if zone:
            zones.append(zone)
    zones.sort(key=lambda zone: zone["id"])
    polygon_count = sum(len(zone["polygons"]) for zone in zones)
    ring_count = sum(len(polygon[1]) for zone in zones for polygon in zone["polygons"])
    point_count = sum(
        len(ring)
        for zone in zones
        for polygon in zone["polygons"]
        for ring in polygon[1]
    )
    return {
        "source": SOURCE_NAME,
        "release": SOURCE_RELEASE,
        "sourceUrl": SOURCE_URL,
        "sourceSha256": SOURCE_SHA256,
        "license": LICENSE,
        "licenseUrl": LICENSE_URL,
        "attribution": (
            "Contains information from timezone-boundary-builder, "
            "made available under the Open Database License (ODbL)."
        ),
        "coordinatePrecision": precision,
        "simplificationToleranceDegrees": tolerance,
        "zoneCount": len(zones),
        "polygonCount": polygon_count,
        "ringCount": ring_count,
        "pointCount": point_count,
        "zones": zones,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="path to combined.json")
    parser.add_argument("output", type=Path, help="destination JSON path")
    parser.add_argument("--tolerance", type=float, default=0.08)
    parser.add_argument("--precision", type=int, default=2)
    args = parser.parse_args()
    result = convert(args.source, args.tolerance, args.precision)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {result['zoneCount']} zones / {result['polygonCount']} polygons / "
        f"{result['pointCount']} points to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
