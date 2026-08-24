#!/usr/bin/env python3
"""Small JSON-speaking timezone helper for the Omarchy world-clock plugin.

Only the standard library is used. All conversion is delegated to zoneinfo,
which reads the system IANA timezone database and therefore applies the rules
for the exact instant being planned.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import UTC, date, datetime, time, timedelta
from math import isfinite
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones


WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
WEEKDAY_NAMES = (
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
)
MONTHS = (
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
)
MONTH_NAMES = (
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
)
POPULAR_ZONES = (
    "Pacific/Auckland",
    "Australia/Sydney",
    "Australia/Adelaide",
    "Asia/Singapore",
    "Asia/Ho_Chi_Minh",
    "Asia/Kolkata",
    "Asia/Kathmandu",
    "Europe/London",
    "Europe/Berlin",
    "America/New_York",
    "America/Chicago",
    "America/Los_Angeles",
)
ZONEINFO_ROOTS = (
    Path("/usr/share/zoneinfo"),
    Path("/usr/lib/zoneinfo"),
    Path("/usr/share/lib/zoneinfo"),
    Path("/etc/zoneinfo"),
)
MAX_LOCATIONS = 12
MAX_LOCATION_ID_LENGTH = 64
MAX_LOCATION_NAME_LENGTH = 80
MAX_TIMEZONE_LENGTH = 128
MAX_SEARCH_QUERY_LENGTH = 80
MAX_LOCATIONS_JSON_BYTES = 8192
MAX_HELPER_OUTPUT_BYTES = 256 * 1024
MAX_HELPER_ERROR_LENGTH = 256
MAX_SEARCH_RESULTS = 20
MAX_TIMELINE_SLOTS = 48


class InputError(ValueError):
    """Raised for a bad CLI request that should be shown in the panel."""


def zone(zone_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(zone_name)
    except ZoneInfoNotFoundError as error:
        raise InputError(f"Unknown timezone: {zone_name}") from error


def valid_timezone_name(value: str | None) -> str | None:
    """Return a usable IANA key, or None for paths and invalid values."""

    candidate = str(value or "").strip()
    if candidate.startswith(":"):
        candidate = candidate[1:]
    for prefix in ("/usr/share/zoneinfo/", "/usr/lib/zoneinfo/"):
        if candidate.startswith(prefix):
            candidate = candidate[len(prefix):]
    for prefix in ("posix/", "right/"):
        if candidate.startswith(prefix):
            candidate = candidate[len(prefix):]
    if not candidate or candidate.startswith("/") or ".." in candidate.split("/"):
        return None
    try:
        ZoneInfo(candidate)
    except (ZoneInfoNotFoundError, ValueError):
        return None
    return candidate


def timezone_name_from_path(path: Path, zoneinfo_roots: tuple[Path, ...]) -> str | None:
    """Resolve an /etc/localtime-style symlink back to its IANA key."""

    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError):
        return None
    for root in zoneinfo_roots:
        try:
            relative = resolved.relative_to(root.resolve())
        except (OSError, ValueError):
            continue
        candidate = valid_timezone_name(relative.as_posix())
        if candidate:
            return candidate
    return None


def detect_system_timezone(
    environment: dict[str, str] | None = None,
    localtime_path: Path = Path("/etc/localtime"),
    timezone_path: Path = Path("/etc/timezone"),
    zoneinfo_roots: tuple[Path, ...] = ZONEINFO_ROOTS,
) -> str:
    """Detect the machine's IANA timezone without systemd or network access."""

    active_environment = os.environ if environment is None else environment
    environment_timezone = valid_timezone_name(active_environment.get("TZ"))
    if environment_timezone:
        return environment_timezone

    linked_timezone = timezone_name_from_path(localtime_path, zoneinfo_roots)
    if linked_timezone:
        return linked_timezone

    try:
        configured_timezone = valid_timezone_name(timezone_path.read_text().splitlines()[0])
    except (OSError, IndexError):
        configured_timezone = None
    if configured_timezone:
        return configured_timezone

    local_key = getattr(datetime.now().astimezone().tzinfo, "key", None)
    return valid_timezone_name(local_key) or "Etc/UTC"


def offset_minutes(value: datetime) -> int:
    offset = value.utcoffset()
    return int(offset.total_seconds() // 60) if offset is not None else 0


def date_label(value: date) -> str:
    return f"{WEEKDAYS[value.weekday()]} {value.day} {MONTHS[value.month - 1]} {value.year}"


def day_relation(value: date, home_date: date) -> str:
    difference = (value - home_date).days
    if difference == -1:
        return "Yesterday"
    if difference == 0:
        return "Today"
    if difference == 1:
        return "Tomorrow"
    return date_label(value)


def coordinate_component(value: str, degree_digits: int) -> float:
    """Parse one compact ISO 6709 component from an IANA zone table."""

    if len(value) not in (degree_digits + 3, degree_digits + 5) or value[0] not in "+-":
        raise ValueError(f"Invalid coordinate component: {value}")
    digits = value[1:]
    degrees = int(digits[:degree_digits])
    minutes = int(digits[degree_digits:degree_digits + 2])
    seconds = int(digits[degree_digits + 2:]) if len(digits) > degree_digits + 2 else 0
    if minutes >= 60 or seconds >= 60:
        raise ValueError(f"Invalid coordinate component: {value}")
    result = degrees + minutes / 60 + seconds / 3600
    return -result if value[0] == "-" else result


def parse_zone_coordinates(value: str) -> tuple[float, float]:
    """Return latitude and longitude from an IANA zone.tab coordinate."""

    longitude_sign = max(value.find("+", 1), value.find("-", 1))
    if longitude_sign <= 0:
        raise ValueError(f"Invalid zone coordinate: {value}")
    return (
        coordinate_component(value[:longitude_sign], 2),
        coordinate_component(value[longitude_sign:], 3),
    )


def timezone_coordinates() -> dict[str, tuple[float, float]]:
    result: dict[str, tuple[float, float]] = {}
    for filename in ("zone.tab", "zone1970.tab"):
        path = Path("/usr/share/zoneinfo") / filename
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        for line in lines:
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 3:
                continue
            try:
                result.setdefault(fields[2], parse_zone_coordinates(fields[1]))
            except ValueError:
                continue
    return result


def coordinates_for_zone(
    zone_name: str, coordinates: dict[str, tuple[float, float]]
) -> tuple[float | None, float | None]:
    point = coordinates.get(zone_name)
    if point is None:
        try:
            resolved = (Path("/usr/share/zoneinfo") / zone_name).resolve(strict=True)
            canonical = resolved.relative_to(Path("/usr/share/zoneinfo").resolve()).as_posix()
            point = coordinates.get(canonical)
        except (OSError, RuntimeError, ValueError):
            point = None
    return point if point is not None else (None, None)


def coordinates_for_location(
    location: dict[str, Any], coordinates: dict[str, tuple[float, float]]
) -> tuple[float | None, float | None]:
    try:
        latitude = float(location["latitude"])
        longitude = float(location["longitude"])
        if (
            isfinite(latitude)
            and isfinite(longitude)
            and -90 <= latitude <= 90
            and -180 <= longitude <= 180
        ):
            return latitude, longitude
    except (KeyError, TypeError, ValueError):
        pass
    return coordinates_for_zone(str(location.get("timezone", "")), coordinates)


def calendar_strip(selected_date: date) -> dict[str, Any]:
    """Return the Sunday-first week containing the selected home date."""

    sunday_offset = (selected_date.weekday() + 1) % 7
    week_start = selected_date - timedelta(days=sunday_offset)
    days = []
    for offset in range(7):
        value = week_start + timedelta(days=offset)
        days.append(
            {
                "date": value.isoformat(),
                "weekday": WEEKDAYS[value.weekday()],
                "day": value.day,
                "offsetDays": (value - selected_date).days,
                "isSelected": value == selected_date,
                "isAdjacentMonth": value.month != selected_date.month,
            }
        )

    return {
        "monthLabel": f"{MONTH_NAMES[selected_date.month - 1]} {selected_date.year}",
        "weekNumber": selected_date.isocalendar().week,
        "days": days,
    }


def availability_key(value: datetime) -> str:
    if value.weekday() >= 5:
        return "off"
    minute_of_day = value.hour * 60 + value.minute
    if 9 * 60 <= minute_of_day < 17 * 60:
        return "work"
    if 7 * 60 <= minute_of_day < 9 * 60 or 17 * 60 <= minute_of_day < 20 * 60:
        return "edge"
    return "off"


def timeline(
    start_timestamp_ms: int | float,
    locations: list[dict[str, Any]],
    hours: int = 24,
    step_minutes: int = 30,
) -> dict[str, Any]:
    """Render a DST-correct absolute timeline into local wall-clock cells."""

    if not locations:
        raise InputError("At least one location is required")
    if hours < 1 or hours > 72:
        raise InputError("Timeline hours must be between 1 and 72")
    if step_minutes < 5 or step_minutes > 60 or 60 % step_minutes != 0:
        raise InputError("Timeline step must divide one hour")

    start = datetime.fromtimestamp(float(start_timestamp_ms) / 1000, UTC)
    total_minutes = hours * 60
    slot_count = total_minutes // step_minutes
    if slot_count > MAX_TIMELINE_SLOTS:
        raise InputError(f"Timeline cannot exceed {MAX_TIMELINE_SLOTS} slots")
    home_location = next((item for item in locations if item.get("isHome")), locations[0])
    home_zone = zone(str(home_location.get("timezone", "")))

    rows = []
    for location in locations:
        timezone = zone(str(location.get("timezone", "")))
        cells = []
        for index in range(slot_count):
            offset = index * step_minutes
            local = (start + timedelta(minutes=offset)).astimezone(timezone)
            hour_12 = local.hour % 12 or 12
            cells.append(
                {
                    "offsetMinutes": offset,
                    "timestampMs": round(local.timestamp() * 1000),
                    "date": local.date().isoformat(),
                    "weekday": WEEKDAY_NAMES[local.weekday()],
                    "time": f"{local.hour:02d}:{local.minute:02d}",
                    "time12": f"{hour_12}:{local.minute:02d}",
                    "period": "AM" if local.hour < 12 else "PM",
                    "hour": local.hour,
                    "minute": local.minute,
                    "isWeekend": local.weekday() >= 5,
                    "isDaytime": 7 <= local.hour < 19,
                    "availability": availability_key(local),
                }
            )
        rows.append(
            {
                "id": str(location.get("id", "")),
                "name": str(location.get("name", location.get("timezone", ""))),
                "timezone": str(location.get("timezone", "")),
                "isHome": bool(location.get("isHome")),
                "cells": cells,
            }
        )

    ticks = []
    for offset in range(0, total_minutes + 1, 6 * 60):
        local = (start + timedelta(minutes=offset)).astimezone(home_zone)
        ticks.append(
            {
                "offsetMinutes": offset,
                "time": f"{local.hour:02d}:{local.minute:02d}",
                "weekday": WEEKDAYS[local.weekday()],
                "date": local.date().isoformat(),
            }
        )

    return {
        "startTimestampMs": round(start.timestamp() * 1000),
        "endTimestampMs": round((start + timedelta(hours=hours)).timestamp() * 1000),
        "hours": hours,
        "stepMinutes": step_minutes,
        "slotCount": slot_count,
        "ticks": ticks,
        "rows": rows,
    }


def clock_range(start: datetime, end: datetime, twelve_hour: bool) -> str:
    def clock(value: datetime) -> str:
        if not twelve_hour:
            return f"{value.hour:02d}:{value.minute:02d}"
        hour = value.hour % 12 or 12
        return f"{hour}:{value.minute:02d} {'AM' if value.hour < 12 else 'PM'}"

    if start.date() == end.date():
        return f"{clock(start)}–{clock(end)}"
    return f"{clock(start)} {WEEKDAYS[start.weekday()]}–{clock(end)} {WEEKDAYS[end.weekday()]}"


def meeting_summary(
    start_timestamp_ms: int | float,
    duration_minutes: int,
    locations: list[dict[str, Any]],
) -> dict[str, Any]:
    if not locations:
        raise InputError("At least one location is required")
    if duration_minutes < 15 or duration_minutes > 12 * 60:
        raise InputError("Meeting duration must be between 15 minutes and 12 hours")

    start = datetime.fromtimestamp(float(start_timestamp_ms) / 1000, UTC)
    end = start + timedelta(minutes=duration_minutes)
    home_location = next((item for item in locations if item.get("isHome")), locations[0])
    home_start = start.astimezone(zone(str(home_location.get("timezone", ""))))
    rows = []
    for location in locations:
        timezone = zone(str(location.get("timezone", "")))
        local_start = start.astimezone(timezone)
        local_end = end.astimezone(timezone)
        rows.append(
            {
                "id": str(location.get("id", "")),
                "name": str(location.get("name", location.get("timezone", ""))),
                "timezone": str(location.get("timezone", "")),
                "isHome": bool(location.get("isHome")),
                "startDate": local_start.date().isoformat(),
                "startWeekday": WEEKDAY_NAMES[local_start.weekday()],
                "range12": clock_range(local_start, local_end, True),
                "range24": clock_range(local_start, local_end, False),
                "abbreviation": local_start.tzname() or "",
            }
        )

    return {
        "startTimestampMs": round(start.timestamp() * 1000),
        "endTimestampMs": round(end.timestamp() * 1000),
        "durationMinutes": duration_minutes,
        "homeDate": home_start.date().isoformat(),
        "homeDateLabel": (
            f"{WEEKDAY_NAMES[home_start.weekday()]}, {home_start.day} "
            f"{MONTH_NAMES[home_start.month - 1]} {home_start.year}"
        ),
        "rows": rows,
    }


def render_locations(timestamp_ms: int | float, locations: list[dict[str, Any]]) -> dict[str, Any]:
    if not locations:
        raise InputError("At least one location is required")

    instant = datetime.fromtimestamp(float(timestamp_ms) / 1000, UTC)
    home_location = next((item for item in locations if item.get("isHome")), locations[0])
    home_zone = zone(str(home_location.get("timezone", "")))
    home_time = instant.astimezone(home_zone)
    home_offset = offset_minutes(home_time)
    coordinates = timezone_coordinates()

    rows: list[dict[str, Any]] = []
    for location in locations:
        zone_name = str(location.get("timezone", ""))
        local = instant.astimezone(zone(zone_name))
        local_offset = offset_minutes(local)
        hour_12 = local.hour % 12 or 12
        latitude, longitude = coordinates_for_location(location, coordinates)
        rows.append(
            {
                "id": str(location.get("id", "")),
                "name": str(location.get("name", zone_name)),
                "timezone": zone_name,
                "isHome": bool(location.get("isHome")),
                "date": local.date().isoformat(),
                "dateLabel": date_label(local.date()),
                "weekday": WEEKDAY_NAMES[local.weekday()],
                "time": f"{local.hour:02d}:{local.minute:02d}",
                "time12": f"{hour_12}:{local.minute:02d}",
                "period": "AM" if local.hour < 12 else "PM",
                "hour": local.hour,
                "minute": local.minute,
                "latitude": latitude,
                "longitude": longitude,
                "isWeekend": local.weekday() >= 5,
                "utcOffsetMinutes": local_offset,
                "offsetDifferenceMinutes": local_offset - home_offset,
                "abbreviation": local.tzname() or "",
                "dayRelation": day_relation(local.date(), home_time.date()),
            }
        )

    return {
        "timestampMs": round(float(timestamp_ms)),
        "homeDate": home_time.date().isoformat(),
        "homeDateLabel": date_label(home_time.date()),
        "calendar": calendar_strip(home_time.date()),
        "rows": rows,
    }


def valid_local_candidates(naive: datetime, timezone: ZoneInfo) -> list[datetime]:
    candidates: list[datetime] = []
    seen: set[float] = set()
    for fold in (0, 1):
        candidate = naive.replace(tzinfo=timezone, fold=fold)
        round_trip = candidate.astimezone(UTC).astimezone(timezone).replace(tzinfo=None)
        stamp = candidate.timestamp()
        if round_trip == naive and stamp not in seen:
            candidates.append(candidate)
            seen.add(stamp)
    return candidates


def resolve_local(naive: datetime, timezone: ZoneInfo) -> datetime:
    """Resolve wall time deterministically through gaps and repeated hours.

    The earlier occurrence wins during a repeated DST hour. A nonexistent
    spring-forward time is normalized through UTC to the corresponding time
    after the gap (for example 02:30 becomes 03:30 for a one-hour gap).
    """

    candidates = valid_local_candidates(naive, timezone)
    if candidates:
        return min(candidates, key=lambda item: item.timestamp())

    provisional = naive.replace(tzinfo=timezone, fold=0)
    return provisional.astimezone(UTC).astimezone(timezone)


def shift_date(timestamp_ms: int | float, zone_name: str, days: int) -> dict[str, Any]:
    if not isinstance(zone_name, str) or not zone_name or len(zone_name) > MAX_TIMEZONE_LENGTH:
        raise InputError("Timezone exceeds the safe field limit")
    if not isinstance(days, int) or isinstance(days, bool) or abs(days) > 366:
        raise InputError("Date shift must be within 366 days")
    timezone = zone(zone_name)
    instant = datetime.fromtimestamp(float(timestamp_ms) / 1000, UTC)
    local = instant.astimezone(timezone)
    target_date = local.date() + timedelta(days=days)
    naive = datetime.combine(target_date, time(local.hour, local.minute, local.second, local.microsecond))
    resolved = resolve_local(naive, timezone)
    return {
        "timestampMs": round(resolved.timestamp() * 1000),
        "date": resolved.date().isoformat(),
        "normalized": resolved.replace(tzinfo=None) != naive,
    }


def country_names() -> dict[str, str]:
    path = Path("/usr/share/zoneinfo/iso3166.tab")
    result: dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            code, name = line.split("\t", 1)
            result[code] = name
    except (OSError, ValueError):
        pass
    return result


def zone_records() -> list[dict[str, Any]]:
    countries = country_names()
    records: dict[str, dict[str, Any]] = {}
    for filename in ("zone1970.tab", "zone.tab"):
        path = Path("/usr/share/zoneinfo") / filename
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        for line in lines:
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 3:
                continue
            codes, coordinate_text, zone_name = fields[:3]
            comment = fields[3] if len(fields) > 3 else ""
            country = ", ".join(countries.get(code, code) for code in codes.split(","))
            city = zone_name.rsplit("/", 1)[-1].replace("_", " ")
            try:
                latitude, longitude = parse_zone_coordinates(coordinate_text)
            except ValueError:
                continue
            records.setdefault(
                zone_name,
                {
                    "timezone": zone_name,
                    "name": city,
                    "country": country,
                    "description": comment,
                    "latitude": latitude,
                    "longitude": longitude,
                },
            )

    for zone_name in available_timezones():
        if "/" not in zone_name or zone_name.startswith(("posix/", "right/", "SystemV/")):
            continue
        records.setdefault(
            zone_name,
            {
                "timezone": zone_name,
                "name": zone_name.rsplit("/", 1)[-1].replace("_", " "),
                "country": "",
                "description": "",
            },
        )
    return list(records.values())


def search_zones(query: str, limit: int = 8) -> list[dict[str, Any]]:
    if not isinstance(query, str) or len(query) > MAX_SEARCH_QUERY_LENGTH:
        raise InputError("Timezone search exceeds the safe field limit")
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= MAX_SEARCH_RESULTS:
        raise InputError(f"Timezone search limit must be between 1 and {MAX_SEARCH_RESULTS}")
    needle = " ".join(query.strip().lower().replace("_", " ").split())
    records = zone_records()

    def public_record(item: dict[str, Any]) -> dict[str, Any]:
        result: dict[str, Any] = {
            "timezone": str(item.get("timezone", ""))[:MAX_TIMEZONE_LENGTH],
            "name": str(item.get("name", ""))[:MAX_LOCATION_NAME_LENGTH],
            "country": str(item.get("country", ""))[:128],
        }
        for coordinate in ("latitude", "longitude"):
            if coordinate in item:
                result[coordinate] = item[coordinate]
        return result

    if not needle:
        by_zone = {item["timezone"]: item for item in records}
        return [
            public_record(by_zone[name])
            for name in POPULAR_ZONES
            if name in by_zone
        ][:limit]

    def score(item: dict[str, Any]) -> tuple[int, int, str]:
        timezone = item["timezone"].lower()
        name = item["name"].lower()
        haystack = " ".join((timezone.replace("_", " "), name, item["country"].lower(), item["description"].lower()))
        if timezone == query.strip().lower():
            rank = 0
        elif name == needle:
            rank = 1
        elif name.startswith(needle):
            rank = 2
        elif timezone.replace("_", " ").startswith(needle):
            rank = 3
        elif needle in haystack:
            rank = 4
        else:
            rank = 99
        return (rank, len(timezone), timezone)

    matches = [item for item in records if score(item)[0] < 99]
    matches.sort(key=score)
    return [public_record(item) for item in matches[:limit]]


def parse_locations(raw: str) -> list[dict[str, Any]]:
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_LOCATIONS_JSON_BYTES:
        raise InputError("Locations JSON exceeds the safe serialized limit")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise InputError("Locations must be valid JSON") from error
    if not isinstance(value, list):
        raise InputError("Locations must be a JSON array")
    if not 1 <= len(value) <= MAX_LOCATIONS:
        raise InputError(f"Locations must contain between 1 and {MAX_LOCATIONS} entries")

    result: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    home_count = 0
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise InputError(f"Location {index + 1} must be an object")

        fields = (
            ("id", MAX_LOCATION_ID_LENGTH),
            ("name", MAX_LOCATION_NAME_LENGTH),
            ("timezone", MAX_TIMEZONE_LENGTH),
        )
        normalized: dict[str, Any] = {}
        for field, maximum in fields:
            field_value = item.get(field)
            if not isinstance(field_value, str):
                raise InputError(f"Location {index + 1} {field} must be text")
            field_value = field_value.strip()
            if not field_value or len(field_value) > maximum:
                raise InputError(f"Location {index + 1} {field} exceeds the safe field limit")
            normalized[field] = field_value

        if normalized["id"] in seen_ids:
            raise InputError("Location ids must be unique")
        seen_ids.add(normalized["id"])
        if valid_timezone_name(normalized["timezone"]) != normalized["timezone"]:
            raise InputError(f"Unknown timezone: {normalized['timezone']}")

        is_home = item.get("isHome", False)
        if not isinstance(is_home, bool):
            raise InputError(f"Location {index + 1} isHome must be boolean")
        normalized["isHome"] = is_home
        if is_home:
            home_count += 1

        latitude_present = "latitude" in item
        longitude_present = "longitude" in item
        if latitude_present != longitude_present:
            raise InputError("Location coordinates must include latitude and longitude")
        if latitude_present:
            latitude = item["latitude"]
            longitude = item["longitude"]
            if (
                isinstance(latitude, bool)
                or isinstance(longitude, bool)
                or not isinstance(latitude, (int, float))
                or not isinstance(longitude, (int, float))
                or not isfinite(latitude)
                or not isfinite(longitude)
                or not -90 <= latitude <= 90
                or not -180 <= longitude <= 180
            ):
                raise InputError("Location coordinates are outside the safe range")
            normalized["latitude"] = latitude
            normalized["longitude"] = longitude

        result.append(normalized)

    if home_count != 1:
        raise InputError("Locations must contain exactly one Home entry")
    return result


def write_json(value: Any) -> None:
    payload = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    if len(payload.encode("utf-8")) > MAX_HELPER_OUTPUT_BYTES:
        raise InputError("Timezone helper output exceeds the safe limit")
    sys.stdout.write(payload + "\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    render = subparsers.add_parser("render", help="render locations at one epoch timestamp")
    render.add_argument("timestamp_ms", type=float)
    render.add_argument("locations_json")

    shift = subparsers.add_parser("shift-date", help="move an instant by local calendar days")
    shift.add_argument("timestamp_ms", type=float)
    shift.add_argument("timezone")
    shift.add_argument("days", type=int)

    search = subparsers.add_parser("search", help="search the installed IANA timezone catalog")
    search.add_argument("query", nargs="?", default="")
    search.add_argument("--limit", type=int, default=8)
    subparsers.add_parser("detect-timezone", help="detect the machine's IANA timezone")
    timeline_parser = subparsers.add_parser("timeline", help="render a timezone timeline")
    timeline_parser.add_argument("start_timestamp_ms", type=float)
    timeline_parser.add_argument("locations_json")
    timeline_parser.add_argument("--hours", type=int, default=24)
    timeline_parser.add_argument("--step-minutes", type=int, default=30)
    meeting_parser = subparsers.add_parser("meeting", help="render a meeting-time range")
    meeting_parser.add_argument("start_timestamp_ms", type=float)
    meeting_parser.add_argument("duration_minutes", type=int)
    meeting_parser.add_argument("locations_json")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "render":
            result: Any = render_locations(args.timestamp_ms, parse_locations(args.locations_json))
        elif args.command == "shift-date":
            result = shift_date(args.timestamp_ms, args.timezone, args.days)
        elif args.command == "search":
            result = search_zones(args.query, args.limit)
        elif args.command == "timeline":
            result = timeline(
                args.start_timestamp_ms,
                parse_locations(args.locations_json),
                args.hours,
                args.step_minutes,
            )
        elif args.command == "meeting":
            result = meeting_summary(
                args.start_timestamp_ms,
                args.duration_minutes,
                parse_locations(args.locations_json),
            )
        else:
            result = {"timezone": detect_system_timezone()}
        write_json(result)
        return 0
    except (InputError, ValueError, OverflowError) as error:
        write_json({"error": str(error)[:MAX_HELPER_ERROR_LENGTH]})
        return 2


if __name__ == "__main__":
    sys.exit(main())
