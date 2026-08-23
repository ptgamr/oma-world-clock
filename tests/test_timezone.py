import importlib.util
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


class SearchTests(unittest.TestCase):
    def test_city_and_iana_search(self):
        city_matches = timezone.search_zones("new york")
        zone_matches = timezone.search_zones("Asia/Kathmandu")
        self.assertEqual(city_matches[0]["timezone"], "America/New_York")
        self.assertEqual(zone_matches[0]["timezone"], "Asia/Kathmandu")


if __name__ == "__main__":
    unittest.main()
