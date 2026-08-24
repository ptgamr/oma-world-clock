const assert = require("node:assert/strict")
const Model = require("../Model.js")

const defaults = Model.defaultLocations()
assert.equal(defaults.length, 4)
assert.deepEqual(defaults.map(location => location.id), [
  "hanoi",
  "berlin",
  "pacific-time",
  "wellington"
])
assert.equal(Model.homeLocation(defaults).timezone, "Asia/Ho_Chi_Minh")
assert.equal(Model.homeLocation(defaults).name, "Hanoi")
assert.equal(defaults.find(location => location.id === "wellington").isHome, false)
assert.equal(defaults.find(location => location.id === "berlin").timezone, "Europe/Berlin")
assert.equal(defaults.find(location => location.id === "hanoi").timezone, "Asia/Ho_Chi_Minh")
assert.equal(defaults.find(location => location.id === "pacific-time").timezone, "America/Los_Angeles")

const duplicateHomes = Model.normalizeLocations([
  { id: "one", name: "One", timezone: "Pacific/Auckland", isHome: true },
  { id: "two", name: "Two", timezone: "Europe/London", isHome: true }
])
assert.equal(duplicateHomes.filter(location => location.isHome).length, 1)

const added = Model.addLocation(defaults, "Customer", "Asia/Kathmandu")
assert.equal(added.at(-1).name, "Customer")
assert.equal(added.at(-1).timezone, "Asia/Kathmandu")

const moved = Model.moveLocation(added, added.at(-1).id, -1)
assert.equal(moved.at(-2).timezone, "Asia/Kathmandu")

const renamed = Model.renameLocation(moved, "berlin", "Work")
assert.equal(renamed.find(location => location.id === "berlin").name, "Work")

const newHome = Model.setHomeLocation(renamed, "pacific-time")
assert.equal(Model.homeLocation(newHome).id, "pacific-time")

const withoutHome = Model.removeLocation(newHome, "pacific-time")
assert.equal(withoutHome[0].isHome, true)

assert.equal(Model.clampPlannerMinutes(22), 15)
assert.equal(Model.clampPlannerMinutes(999), 720)
assert.equal(Model.planningLabel(0, true), "NOW")
assert.equal(Model.planningLabel(195, false), "+3h 15m")
assert.equal(Model.formatTimezoneDifference(-690), "−11h 30m")

assert.deepEqual(Model.availability(10, 0, false), { key: "work", label: "WORK" })
assert.deepEqual(Model.availability(18, 30, false), { key: "edge", label: "EDGE" })
assert.deepEqual(Model.availability(10, 0, true), { key: "off", label: "OFF" })
assert.equal(Model.isDaytime(6), false)
assert.equal(Model.isDaytime(7), true)
assert.equal(Model.isDaytime(18), true)
assert.equal(Model.isDaytime(19), false)
assert.equal(Model.analogMinuteAngle(45), 270)
assert.equal(Model.analogSecondAngle(37), 222)
assert.equal(Model.analogHourAngle(3, 30), 105)

console.log("Model tests passed")
