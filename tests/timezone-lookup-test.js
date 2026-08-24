const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Lookup = require("../components/TimezoneLookup.js")

const squareWithHole = [{
  id: "Test/Outer",
  bounds: [0, 0, 10, 10],
  polygons: [[
    [0, 0, 10, 10],
    [
      [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
      [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]]
    ]
  ]]
}]

assert.equal(Lookup.zoneAt(squareWithHole, 2, 2).id, "Test/Outer")
assert.equal(Lookup.zoneAt(squareWithHole, 5, 5), null)
assert.equal(Lookup.zoneAt(squareWithHole, 20, 20), null)
assert.equal(Lookup.zoneAt(squareWithHole, 0, 4).id, "Test/Outer")

const assetPath = path.join(__dirname, "..", "assets", "world-timezones-2026c.json")
const asset = JSON.parse(fs.readFileSync(assetPath, "utf8"))
const cases = [
  // The comprehensive source intentionally assigns historic northern Vietnam
  // to Bangkok and southern Vietnam to Ho Chi Minh City.
  [105.8342, 21.0278, "Asia/Bangkok"],
  [106.6297, 10.8231, "Asia/Ho_Chi_Minh"],
  [13.405, 52.52, "Europe/Berlin"],
  [-118.2437, 34.0522, "America/Los_Angeles"],
  [174.7756, -41.2866, "Pacific/Auckland"]
]
for (const [longitude, latitude, expected] of cases)
  assert.equal(Lookup.zoneAt(asset.zones, longitude, latitude)?.id, expected)

assert.equal(Lookup.zoneAt(asset.zones, -140, 0), null)
assert.equal(Lookup.zoneById(asset.zones, "Europe/Berlin").id, "Europe/Berlin")
assert.equal(Lookup.locationNear([
  { name: "Hanoi", timezone: "Asia/Ho_Chi_Minh", latitude: 21.0278, longitude: 105.8342 }
], 105.84, 21.03, 1000, 500, 12).timezone, "Asia/Ho_Chi_Minh")
assert.equal(Lookup.locationNear([
  { name: "Hanoi", timezone: "Asia/Ho_Chi_Minh", latitude: 21.0278, longitude: 105.8342 }
], 90, 21.03, 1000, 500, 12), null)

console.log("Timezone lookup tests passed")
