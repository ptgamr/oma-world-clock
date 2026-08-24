import json
import unittest
from pathlib import Path


ASSET_PATH = Path(__file__).parents[1] / "assets" / "world-land-110m.json"


class WorldMapAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(ASSET_PATH.read_text(encoding="utf-8"))

    def test_asset_has_real_low_resolution_land_geometry(self):
        self.assertEqual(self.data["source"], "Natural Earth 1:110m Land")
        self.assertTrue(self.data["publicDomain"])
        self.assertGreaterEqual(self.data["polygonCount"], 120)
        self.assertGreaterEqual(self.data["pointCount"], 5000)
        self.assertEqual(len(self.data["polygons"]), self.data["polygonCount"])

    def test_coordinates_stay_inside_world_bounds(self):
        for polygon in self.data["polygons"]:
            self.assertGreaterEqual(len(polygon), 4)
            for longitude, latitude in polygon:
                self.assertGreaterEqual(longitude, -180)
                self.assertLessEqual(longitude, 180)
                self.assertGreaterEqual(latitude, -90)
                self.assertLessEqual(latitude, 90)


if __name__ == "__main__":
    unittest.main()
