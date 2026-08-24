import json
import unittest
from pathlib import Path


ASSET_PATH = Path(__file__).parents[1] / "assets" / "world-timezones-2026c.json"


class TimezoneBoundaryAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(ASSET_PATH.read_text(encoding="utf-8"))

    def test_asset_has_comprehensive_geographic_timezones(self):
        self.assertEqual(self.data["source"], "timezone-boundary-builder")
        self.assertEqual(self.data["release"], "2026c")
        self.assertEqual(self.data["license"], "ODbL-1.0")
        self.assertEqual(self.data["zoneCount"], len(self.data["zones"]))
        self.assertGreaterEqual(self.data["zoneCount"], 400)
        self.assertGreaterEqual(self.data["polygonCount"], 1000)
        self.assertGreaterEqual(self.data["pointCount"], 25000)
        identifiers = {zone["id"] for zone in self.data["zones"]}
        self.assertTrue({
            "Asia/Ho_Chi_Minh",
            "Europe/Berlin",
            "America/Los_Angeles",
            "Pacific/Auckland",
        }.issubset(identifiers))

    def test_compact_coordinates_stay_inside_world_bounds(self):
        for zone in self.data["zones"]:
            self.assertEqual(len(zone["bounds"]), 4)
            for polygon_bounds, rings in zone["polygons"]:
                self.assertEqual(len(polygon_bounds), 4)
                self.assertGreaterEqual(len(rings), 1)
                for ring in rings:
                    self.assertGreaterEqual(len(ring), 4)
                    self.assertEqual(ring[0], ring[-1])
                    for longitude, latitude in ring:
                        self.assertGreaterEqual(longitude, -180)
                        self.assertLessEqual(longitude, 180)
                        self.assertGreaterEqual(latitude, -90)
                        self.assertLessEqual(latitude, 90)


if __name__ == "__main__":
    unittest.main()
