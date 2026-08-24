const assert = require("node:assert/strict")
const Model = require("../Model.js")

const defaults = Model.defaultLocations("Asia/Ho_Chi_Minh")
assert.equal(defaults.length, 3)
assert.deepEqual(defaults.map(location => location.id), [
  "ho-chi-minh",
  "berlin",
  "new-york"
])
assert.equal(Model.homeLocation(defaults).timezone, "Asia/Ho_Chi_Minh")
assert.equal(Model.homeLocation(defaults).name, "Ho Chi Minh")
assert.equal(defaults.find(location => location.id === "berlin").timezone, "Europe/Berlin")
assert.equal(defaults.find(location => location.id === "new-york").timezone, "America/New_York")

const europeanDefaults = Model.defaultLocations("Europe/Paris")
assert.deepEqual(europeanDefaults.map(location => location.timezone), [
  "Europe/Paris",
  "Asia/Ho_Chi_Minh",
  "America/New_York"
])

const americanDefaults = Model.defaultLocations("America/Chicago")
assert.deepEqual(americanDefaults.map(location => location.timezone), [
  "America/Chicago",
  "Europe/Berlin",
  "Asia/Ho_Chi_Minh"
])

const oceanianDefaults = Model.defaultLocations("Pacific/Auckland")
assert.deepEqual(oceanianDefaults.map(location => location.timezone), [
  "Pacific/Auckland",
  "Asia/Ho_Chi_Minh",
  "America/New_York"
])

const africanDefaults = Model.defaultLocations("Africa/Cairo")
assert.deepEqual(africanDefaults.map(location => location.timezone), [
  "Africa/Cairo",
  "Europe/Berlin",
  "Asia/Ho_Chi_Minh"
])

const utcDefaults = Model.defaultLocations()
assert.deepEqual(utcDefaults.map(location => location.timezone), [
  "Etc/UTC",
  "Europe/Berlin",
  "Asia/Ho_Chi_Minh"
])

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

const newHome = Model.setHomeLocation(renamed, "new-york")
assert.equal(Model.homeLocation(newHome).id, "new-york")

const withoutHome = Model.removeLocation(newHome, "new-york")
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

const metadataRow = {
  isHome: false,
  dayRelation: "Yesterday",
  offsetDifferenceMinutes: -300,
  abbreviation: "CEST"
}
assert.equal(Model.metadataForRow(metadataRow, true, true), "Yesterday · −5h · CEST")
assert.equal(Model.metadataForRow(metadataRow, true, true, false), "−5h · CEST")

console.log("Model tests passed")
