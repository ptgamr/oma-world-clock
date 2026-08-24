import importlib.util
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "helpers" / "timezone.py"
SPEC = importlib.util.spec_from_file_location("world_clock_timezone", MODULE_PATH)
timezone = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(timezone)


def timestamp_ms(value: datetime) -> int:
    return round(value.timestamp() * 1000)


LOCATIONS = [
    {"id": "home", "name": "Wellington", "timezone": "Pacific/Auckland", "isHome": True},
    {"id": "london", "name": "London", "timezone": "Europe/London"},
    {"id": "new-york", "name": "New York", "timezone": "America/New_York"},
    {"id": "adelaide", "name": "Adelaide", "timezone": "Australia/Adelaide"},
    {"id": "kathmandu", "name": "Kathmandu", "timezone": "Asia/Kathmandu"},
    {"id": "kolkata", "name": "Kolkata", "timezone": "Asia/Kolkata"},
]


class RenderTests(unittest.TestCase):
    def rows_at(self, value: datetime):
        result = timezone.render_locations(timestamp_ms(value), LOCATIONS)
        return {row["id"]: row for row in result["rows"]}

    def test_southern_and_northern_summer_offsets(self):
        rows = self.rows_at(datetime(2026, 1, 15, 12, tzinfo=UTC))
        self.assertEqual(rows["home"]["utcOffsetMinutes"], 13 * 60)
        self.assertEqual(rows["london"]["utcOffsetMinutes"], 0)
        self.assertEqual(rows["new-york"]["utcOffsetMinutes"], -5 * 60)
        self.assertEqual(rows["adelaide"]["utcOffsetMinutes"], 10 * 60 + 30)

    def test_southern_winter_and_northern_summer_offsets(self):
        rows = self.rows_at(datetime(2026, 7, 15, 12, tzinfo=UTC))
        self.assertEqual(rows["home"]["utcOffsetMinutes"], 12 * 60)
        self.assertEqual(rows["london"]["utcOffsetMinutes"], 60)
        self.assertEqual(rows["new-york"]["utcOffsetMinutes"], -4 * 60)
        self.assertEqual(rows["adelaide"]["utcOffsetMinutes"], 9 * 60 + 30)

    def test_non_whole_hour_zones(self):
        rows = self.rows_at(datetime(2026, 4, 10, 0, tzinfo=UTC))
        self.assertEqual(rows["kathmandu"]["utcOffsetMinutes"], 5 * 60 + 45)
        self.assertEqual(rows["kolkata"]["utcOffsetMinutes"], 5 * 60 + 30)

    def test_day_relationship_crosses_year_boundary(self):
        rows = self.rows_at(datetime(2026, 12, 31, 12, tzinfo=UTC))
        self.assertEqual(rows["home"]["date"], "2027-01-01")
        self.assertEqual(rows["london"]["dayRelation"], "Yesterday")

    def test_london_dst_transition_uses_exact_instant(self):
        before = self.rows_at(datetime(2026, 3, 29, 0, 30, tzinfo=UTC))
        after = self.rows_at(datetime(2026, 3, 29, 1, 30, tzinfo=UTC))
        self.assertEqual(before["london"]["utcOffsetMinutes"], 0)
        self.assertEqual(after["london"]["utcOffsetMinutes"], 60)

    def test_new_york_dst_transition_uses_exact_instant(self):
        before = self.rows_at(datetime(2026, 3, 8, 6, 30, tzinfo=UTC))
        after = self.rows_at(datetime(2026, 3, 8, 7, 30, tzinfo=UTC))
        self.assertEqual(before["new-york"]["utcOffsetMinutes"], -5 * 60)
        self.assertEqual(after["new-york"]["utcOffsetMinutes"], -4 * 60)

    def test_calendar_strip_is_sunday_first_and_selects_home_date(self):
        result = timezone.render_locations(
            timestamp_ms(datetime(2026, 8, 23, 23, 46, tzinfo=UTC)), LOCATIONS
        )
        calendar = result["calendar"]
        self.assertEqual(calendar["monthLabel"], "August 2026")
        self.assertEqual(calendar["weekNumber"], 35)
        self.assertEqual([day["date"] for day in calendar["days"]], [
            "2026-08-23",
            "2026-08-24",
            "2026-08-25",
            "2026-08-26",
            "2026-08-27",
            "2026-08-28",
            "2026-08-29",
        ])
        self.assertEqual(calendar["days"][1]["weekday"], "Mon")
        self.assertTrue(calendar["days"][1]["isSelected"])
        self.assertEqual(calendar["days"][1]["offsetDays"], 0)

    def test_calendar_strip_marks_days_outside_selected_month(self):
        calendar = timezone.calendar_strip(datetime(2026, 1, 1).date())
        self.assertEqual(calendar["monthLabel"], "January 2026")
        self.assertEqual(calendar["days"][0]["date"], "2025-12-28")
        self.assertTrue(calendar["days"][0]["isAdjacentMonth"])
        self.assertTrue(calendar["days"][4]["isSelected"])

    def test_render_includes_explicit_twelve_hour_time_and_period(self):
        rows = self.rows_at(datetime(2026, 8, 24, 0, 46, tzinfo=UTC))
        self.assertEqual(rows["home"]["time"], "12:46")
        self.assertEqual(rows["home"]["time12"], "12:46")
        self.assertEqual(rows["home"]["period"], "PM")
        self.assertEqual(rows["home"]["weekday"], "Monday")
        self.assertEqual(rows["london"]["time"], "01:46")
        self.assertEqual(rows["london"]["time12"], "1:46")
        self.assertEqual(rows["london"]["period"], "AM")


class PlannerDateTests(unittest.TestCase):
    def test_calendar_day_shift_preserves_wall_time_across_dst(self):
        start = datetime(2026, 3, 28, 12, tzinfo=UTC)
        shifted = timezone.shift_date(timestamp_ms(start), "Europe/London", 1)
        resolved = datetime.fromtimestamp(shifted["timestampMs"] / 1000, UTC)
        self.assertEqual(resolved, datetime(2026, 3, 29, 11, tzinfo=UTC))

    def test_nonexistent_wall_time_normalizes_forward(self):
        london = timezone.zone("Europe/London")
        resolved = timezone.resolve_local(datetime(2026, 3, 29, 1, 30), london)
        self.assertEqual((resolved.hour, resolved.minute), (2, 30))

    def test_ambiguous_wall_time_chooses_earlier_occurrence(self):
        london = timezone.zone("Europe/London")
        resolved = timezone.resolve_local(datetime(2026, 10, 25, 1, 30), london)
        self.assertEqual(resolved.fold, 0)
        self.assertEqual(resolved.utcoffset().total_seconds(), 3600)


class TimelineTests(unittest.TestCase):
    def test_timeline_has_twenty_four_hours_of_half_hour_cells(self):
        result = timezone.timeline(
            timestamp_ms(datetime(2026, 8, 23, 12, tzinfo=UTC)), LOCATIONS[:3]
        )
        self.assertEqual(result["slotCount"], 48)
        self.assertEqual(len(result["ticks"]), 5)
        self.assertEqual(len(result["rows"]), 3)
        self.assertTrue(all(len(row["cells"]) == 48 for row in result["rows"]))

    def test_timeline_applies_dst_inside_the_visible_range(self):
        locations = [
            {"id": "london", "name": "London", "timezone": "Europe/London", "isHome": True}
        ]
        result = timezone.timeline(
            timestamp_ms(datetime(2026, 3, 29, 0, tzinfo=UTC)), locations, hours=3
        )
        times = [cell["time"] for cell in result["rows"][0]["cells"]]
        self.assertEqual(times[:4], ["00:00", "00:30", "02:00", "02:30"])

    def test_timeline_marks_work_edge_and_off_hours(self):
        self.assertEqual(timezone.availability_key(datetime(2026, 8, 24, 10, 0)), "work")
        self.assertEqual(timezone.availability_key(datetime(2026, 8, 24, 18, 0)), "edge")
        self.assertEqual(timezone.availability_key(datetime(2026, 8, 23, 10, 0)), "off")


class SearchTests(unittest.TestCase):
    def test_city_and_iana_search(self):
        city_matches = timezone.search_zones("new york")
        zone_matches = timezone.search_zones("Asia/Kathmandu")
        self.assertEqual(city_matches[0]["timezone"], "America/New_York")
        self.assertEqual(zone_matches[0]["timezone"], "Asia/Kathmandu")


class SystemTimezoneTests(unittest.TestCase):
    def test_environment_timezone_takes_precedence(self):
        detected = timezone.detect_system_timezone(environment={"TZ": "Europe/Paris"})
        self.assertEqual(detected, "Europe/Paris")

    def test_localtime_symlink_resolves_to_iana_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "zoneinfo"
            target = root / "Pacific" / "Auckland"
            target.parent.mkdir(parents=True)
            target.touch()
            localtime = Path(directory) / "localtime"
            localtime.symlink_to(target)

            detected = timezone.detect_system_timezone(
                environment={},
                localtime_path=localtime,
                timezone_path=Path(directory) / "missing-timezone",
                zoneinfo_roots=(root,),
            )
            self.assertEqual(detected, "Pacific/Auckland")

    def test_timezone_file_is_used_when_localtime_is_not_a_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            timezone_file = Path(directory) / "timezone"
            timezone_file.write_text("America/New_York\n")

            detected = timezone.detect_system_timezone(
                environment={},
                localtime_path=Path(directory) / "missing-localtime",
                timezone_path=timezone_file,
                zoneinfo_roots=(),
            )
            self.assertEqual(detected, "America/New_York")


if __name__ == "__main__":
    unittest.main()
