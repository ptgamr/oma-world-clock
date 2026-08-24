# Timezone boundary data

`world-timezones-2026c.json` is a simplified derivative of the comprehensive
land-only GeoJSON from **timezone-boundary-builder release 2026c**.

- Source: https://github.com/evansiroky/timezone-boundary-builder
- Archive: https://github.com/evansiroky/timezone-boundary-builder/releases/download/2026c/timezones.geojson.zip
- Archive SHA-256: `7d3f0c5a33b6acd891335c0ad5ba767736b6914cb1a1d68c71921c17ce358948`
- Data license: Open Database License 1.0
- License text: https://opendatacommons.org/licenses/odbl/1-0/

Contains information from timezone-boundary-builder, which is made available
under the Open Database License (ODbL).

The checked-in derivative database is also made available under ODbL 1.0. It
uses two-decimal-degree coordinates and a 0.08-degree map-scale simplification.
The application code remains covered by the repository's MIT license.

Regenerate the derivative database with:

```sh
curl -fLO https://github.com/evansiroky/timezone-boundary-builder/releases/download/2026c/timezones.geojson.zip
sha256sum timezones.geojson.zip
unzip timezones.geojson.zip
python3 tools/build_timezone_boundaries.py combined.json assets/world-timezones-2026c.json
```
