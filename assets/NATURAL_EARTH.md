# World map data

`world-land-110m.json` is derived from **Natural Earth 1:110m Land**, version
4.0.0. It contains only rounded longitude/latitude polygon coordinates used by
the local QML map renderer.

- Source: https://www.naturalearthdata.com/downloads/110m-physical-vectors/
- Download: https://naciscdn.org/naturalearth/110m/physical/ne_110m_land.zip
- Terms: https://www.naturalearthdata.com/about/terms-of-use/

Natural Earth data is in the public domain. Regenerate the compact asset with:

```sh
python3 tools/build_world_map.py path/to/ne_110m_land.shp assets/world-land-110m.json
```
