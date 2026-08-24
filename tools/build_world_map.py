#!/usr/bin/env python3
"""Convert Natural Earth polygon shapefile geometry into compact map JSON."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import BinaryIO, Iterator


SOURCE_NAME = "Natural Earth 1:110m Land"
SOURCE_URL = "https://naciscdn.org/naturalearth/110m/physical/ne_110m_land.zip"


def records(stream: BinaryIO) -> Iterator[bytes]:
    header = stream.read(100)
    if len(header) != 100 or struct.unpack(">i", header[:4])[0] != 9994:
        raise ValueError("Not an ESRI shapefile")
    while record_header := stream.read(8):
        if len(record_header) != 8:
            raise ValueError("Truncated shapefile record header")
        _, word_length = struct.unpack(">2i", record_header)
        content = stream.read(word_length * 2)
        if len(content) != word_length * 2:
            raise ValueError("Truncated shapefile record")
        yield content


def polygon_rings(content: bytes, precision: int) -> Iterator[list[list[float]]]:
    if len(content) < 44:
        return
    shape_type = struct.unpack_from("<i", content, 0)[0]
    if shape_type == 0:
        return
    if shape_type not in (5, 15, 25):
        raise ValueError(f"Expected polygon geometry, found shape type {shape_type}")
    part_count, point_count = struct.unpack_from("<2i", content, 36)
    parts = list(struct.unpack_from(f"<{part_count}i", content, 44))
    points_offset = 44 + part_count * 4
    points = [
        struct.unpack_from("<2d", content, points_offset + index * 16)
        for index in range(point_count)
    ]
    parts.append(point_count)
    for index in range(part_count):
        ring: list[list[float]] = []
        for longitude, latitude in points[parts[index]:parts[index + 1]]:
            point = [round(longitude, precision), round(latitude, precision)]
            if not ring or point != ring[-1]:
                ring.append(point)
        if len(ring) >= 4:
            yield ring


def convert(source: Path, precision: int = 2) -> dict[str, object]:
    polygons: list[list[list[float]]] = []
    with source.open("rb") as stream:
        for record in records(stream):
            polygons.extend(polygon_rings(record, precision))
    return {
        "source": SOURCE_NAME,
        "sourceUrl": SOURCE_URL,
        "publicDomain": True,
        "coordinatePrecision": precision,
        "polygonCount": len(polygons),
        "pointCount": sum(len(polygon) for polygon in polygons),
        "polygons": polygons,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="path to ne_110m_land.shp")
    parser.add_argument("output", type=Path, help="destination JSON path")
    parser.add_argument("--precision", type=int, default=2)
    args = parser.parse_args()
    result = convert(args.source, args.precision)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {result['polygonCount']} polygons / {result['pointCount']} points "
        f"to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
