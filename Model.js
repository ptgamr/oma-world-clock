// Pure state and presentation helpers for the world-clock plugin. Keep this
// file free of Qt APIs so the important behavior can also be tested with Node.

var DEFAULT_LOCATIONS = [
  { id: "hanoi", name: "Hanoi", timezone: "Asia/Ho_Chi_Minh", isHome: true },
  { id: "berlin", name: "Berlin", timezone: "Europe/Berlin", isHome: false },
  { id: "pacific-time", name: "Pacific Time", timezone: "America/Los_Angeles", isHome: false },
  { id: "wellington", name: "Wellington", timezone: "Pacific/Auckland", isHome: false }
]

function cleanText(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "")
}

function cloneLocation(location) {
  return {
    id: cleanText(location && location.id),
    name: cleanText(location && location.name),
    timezone: cleanText(location && location.timezone),
    isHome: !!(location && location.isHome)
  }
}

function defaultLocations() {
  return DEFAULT_LOCATIONS.map(cloneLocation)
}

function slugify(value) {
  var slug = cleanText(value).toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
  return slug || "location"
}

function uniqueId(locations, preferred) {
  var used = {}
  for (var i = 0; i < locations.length; i++) used[String(locations[i].id)] = true
  var base = slugify(preferred)
  var candidate = base
  var suffix = 2
  while (used[candidate]) candidate = base + "-" + suffix++
  return candidate
}

function normalizeLocations(value) {
  if (!Array.isArray(value) || value.length === 0) return defaultLocations()

  var out = []
  var seen = {}
  var homeFound = false
  for (var i = 0; i < value.length; i++) {
    var source = value[i]
    if (!source || typeof source !== "object") continue
    var timezone = cleanText(source.timezone)
    if (timezone === "") continue

    var name = cleanText(source.name) || timezone.split("/").pop().replace(/_/g, " ")
    var baseId = cleanText(source.id) || slugify(name)
    var id = baseId
    var suffix = 2
    while (seen[id]) id = baseId + "-" + suffix++
    seen[id] = true

    var isHome = !!source.isHome && !homeFound
    if (isHome) homeFound = true
    out.push({ id: id, name: name, timezone: timezone, isHome: isHome })
  }

  if (out.length === 0) return defaultLocations()
  if (!homeFound) out[0].isHome = true
  return out
}

function homeLocation(locations) {
  var normalized = normalizeLocations(locations)
  for (var i = 0; i < normalized.length; i++) if (normalized[i].isHome) return normalized[i]
  return normalized[0]
}

function addLocation(locations, name, timezone) {
  var out = normalizeLocations(locations)
  var cleanZone = cleanText(timezone)
  if (cleanZone === "") return out
  var cleanName = cleanText(name) || cleanZone.split("/").pop().replace(/_/g, " ")
  out.push({
    id: uniqueId(out, cleanName),
    name: cleanName,
    timezone: cleanZone,
    isHome: false
  })
  return out
}

function removeLocation(locations, id) {
  var normalized = normalizeLocations(locations)
  if (normalized.length <= 1) return normalized
  var removedHome = false
  var out = []
  for (var i = 0; i < normalized.length; i++) {
    if (normalized[i].id === id) removedHome = normalized[i].isHome
    else out.push(cloneLocation(normalized[i]))
  }
  if (out.length === normalized.length) return normalized
  if (removedHome && out.length > 0) out[0].isHome = true
  return out
}

function renameLocation(locations, id, name) {
  var normalized = normalizeLocations(locations)
  var cleanName = cleanText(name)
  if (cleanName === "") return normalized
  for (var i = 0; i < normalized.length; i++) {
    if (normalized[i].id === id) normalized[i].name = cleanName
  }
  return normalized
}

function moveLocation(locations, id, delta) {
  var normalized = normalizeLocations(locations)
  var from = -1
  for (var i = 0; i < normalized.length; i++) if (normalized[i].id === id) from = i
  if (from < 0) return normalized
  var to = Math.max(0, Math.min(normalized.length - 1, from + Number(delta)))
  if (to === from) return normalized
  var moved = normalized.splice(from, 1)[0]
  normalized.splice(to, 0, moved)
  return normalized
}

function setHomeLocation(locations, id) {
  var normalized = normalizeLocations(locations)
  var found = false
  for (var i = 0; i < normalized.length; i++) if (normalized[i].id === id) found = true
  if (!found) return normalized
  for (var j = 0; j < normalized.length; j++) normalized[j].isHome = normalized[j].id === id
  return normalized
}

function clampPlannerMinutes(value) {
  var minutes = Math.round(Number(value) / 15) * 15
  if (!isFinite(minutes)) return 0
  return Math.max(-720, Math.min(720, minutes))
}

function formatDuration(minutes, includePlus) {
  var value = Math.round(Number(minutes))
  if (!isFinite(value)) value = 0
  var sign = value < 0 ? "−" : (includePlus && value > 0 ? "+" : "")
  var absolute = Math.abs(value)
  var hours = Math.floor(absolute / 60)
  var mins = absolute % 60
  if (hours === 0) return sign + mins + "m"
  if (mins === 0) return sign + hours + "h"
  return sign + hours + "h " + mins + "m"
}

function planningLabel(offsetMinutes, followingNow) {
  return followingNow ? "NOW" : formatDuration(offsetMinutes, true)
}

function formatTimezoneDifference(minutes) {
  var value = Math.round(Number(minutes))
  if (!isFinite(value) || value === 0) return ""
  return formatDuration(value, true)
}

function availability(hour, minute, isWeekend) {
  if (isWeekend) return { key: "off", label: "OFF" }
  var time = Number(hour) * 60 + Number(minute)
  if (time >= 9 * 60 && time < 17 * 60) return { key: "work", label: "WORK" }
  if (time >= 7 * 60 && time < 9 * 60) return { key: "edge", label: "EDGE" }
  if (time >= 17 * 60 && time < 20 * 60) return { key: "edge", label: "EDGE" }
  return { key: "off", label: "OFF" }
}

function isDaytime(hour) {
  var value = Math.floor(Number(hour))
  if (!isFinite(value)) return false
  return value >= 7 && value < 19
}

function analogMinuteAngle(minute) {
  var value = Number(minute)
  if (!isFinite(value)) value = 0
  return ((value % 60) + 60) % 60 * 6
}

function analogSecondAngle(second) {
  var value = Number(second)
  if (!isFinite(value)) value = 0
  return ((value % 60) + 60) % 60 * 6
}

function analogHourAngle(hour, minute) {
  var hours = Number(hour)
  var minutes = Number(minute)
  if (!isFinite(hours)) hours = 0
  if (!isFinite(minutes)) minutes = 0
  return (((hours % 12) + 12) % 12 + (((minutes % 60) + 60) % 60) / 60) * 30
}

function metadataForRow(row, showAbbreviation, showDifference) {
  if (!row) return ""
  var parts = []
  if (!row.isHome && row.dayRelation && row.dayRelation !== "Today") parts.push(row.dayRelation)
  if (!row.isHome && showDifference) {
    var difference = formatTimezoneDifference(row.offsetDifferenceMinutes)
    if (difference !== "") parts.push(difference)
  }
  if (showAbbreviation && row.abbreviation) parts.push(String(row.abbreviation))
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultLocations: defaultLocations,
    normalizeLocations: normalizeLocations,
    homeLocation: homeLocation,
    addLocation: addLocation,
    removeLocation: removeLocation,
    renameLocation: renameLocation,
    moveLocation: moveLocation,
    setHomeLocation: setHomeLocation,
    clampPlannerMinutes: clampPlannerMinutes,
    formatDuration: formatDuration,
    planningLabel: planningLabel,
    formatTimezoneDifference: formatTimezoneDifference,
    availability: availability,
    isDaytime: isDaytime,
    analogMinuteAngle: analogMinuteAngle,
    analogSecondAngle: analogSecondAngle,
    analogHourAngle: analogHourAngle,
    metadataForRow: metadataForRow
  }
}
