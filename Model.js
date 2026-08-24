// Pure state and presentation helpers for the world-clock plugin. Keep this
// file free of Qt APIs so the important behavior can also be tested with Node.

var REGION_DEFAULTS = {
  asia: { id: "ho-chi-minh", name: "Ho Chi Minh", timezone: "Asia/Ho_Chi_Minh", isHome: false },
  europe: { id: "berlin", name: "Berlin", timezone: "Europe/Berlin", isHome: false },
  america: { id: "new-york", name: "New York", timezone: "America/New_York", isHome: false },
  africa: { id: "johannesburg", name: "Johannesburg", timezone: "Africa/Johannesburg", isHome: false },
  oceania: { id: "sydney", name: "Sydney", timezone: "Australia/Sydney", isHome: false }
}

var CITY_COORDINATES = {
  "auckland": { latitude: -36.8509, longitude: 174.7645 },
  "berlin": { latitude: 52.52, longitude: 13.405 },
  "hanoi": { latitude: 21.0278, longitude: 105.8342 },
  "ho chi minh": { latitude: 10.8231, longitude: 106.6297 },
  "johannesburg": { latitude: -26.2041, longitude: 28.0473 },
  "los angeles": { latitude: 34.0522, longitude: -118.2437 },
  "new york": { latitude: 40.7128, longitude: -74.006 },
  "pacific time": { latitude: 34.0522, longitude: -118.2437 },
  "sydney": { latitude: -33.8688, longitude: 151.2093 },
  "wellington": { latitude: -41.2866, longitude: 174.7756 }
}

var COMPLEMENTARY_REGIONS = {
  asia: ["europe", "america"],
  europe: ["asia", "america"],
  america: ["europe", "asia"],
  africa: ["europe", "asia"],
  oceania: ["asia", "america"],
  other: ["europe", "asia"]
}

var WEEKDAY_NAMES = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]
var WEEKDAY_SHORT_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_SHORT_NAMES = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

function cleanText(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "")
}

function validCoordinate(value, minimum, maximum) {
  if (value === undefined || value === null || cleanText(value) === "") return null
  var number = Number(value)
  return isFinite(number) && number >= minimum && number <= maximum ? number : null
}

function coordinatesForLocation(location, name) {
  var latitude = validCoordinate(location && location.latitude, -90, 90)
  var longitude = validCoordinate(location && location.longitude, -180, 180)
  if (latitude !== null && longitude !== null)
    return { latitude: latitude, longitude: longitude }
  return CITY_COORDINATES[cleanText(name).toLowerCase()] || null
}

function applyCoordinates(target, source, name) {
  var coordinates = coordinatesForLocation(source, name)
  if (coordinates) {
    target.latitude = coordinates.latitude
    target.longitude = coordinates.longitude
  }
  return target
}

function cloneLocation(location) {
  var name = cleanText(location && location.name)
  return applyCoordinates({
    id: cleanText(location && location.id),
    name: name,
    timezone: cleanText(location && location.timezone),
    isHome: !!(location && location.isHome)
  }, location, name)
}

function timezoneRegion(timezone) {
  var area = cleanText(timezone).split("/")[0]
  if (area === "Asia") return "asia"
  if (area === "Europe") return "europe"
  if (area === "America" || area === "US" || area === "Canada"
      || area === "Mexico" || area === "Brazil" || area === "Chile") return "america"
  if (area === "Africa") return "africa"
  if (area === "Australia" || area === "Pacific") return "oceania"
  return "other"
}

function timezoneDisplayName(timezone) {
  var value = cleanText(timezone) || "Etc/UTC"
  if (value === "UTC" || value === "Etc/UTC") return "UTC"
  var parts = value.split("/")
  return parts[parts.length - 1].replace(/_/g, " ")
}

function defaultLocations(systemTimezone) {
  var timezone = cleanText(systemTimezone) || "Etc/UTC"
  var name = timezoneDisplayName(timezone)
  var home = {
    id: slugify(name),
    name: name,
    timezone: timezone,
    isHome: true
  }
  var regions = COMPLEMENTARY_REGIONS[timezoneRegion(timezone)] || COMPLEMENTARY_REGIONS.other
  var locations = [cloneLocation(home)]
  for (var i = 0; i < regions.length; i++)
    locations.push(cloneLocation(REGION_DEFAULTS[regions[i]]))
  return locations
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
    out.push(applyCoordinates(
      { id: id, name: name, timezone: timezone, isHome: isHome }, source, name))
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

function addLocation(locations, name, timezone, latitude, longitude) {
  var out = normalizeLocations(locations)
  var cleanZone = cleanText(timezone)
  if (cleanZone === "") return out
  var cleanName = cleanText(name) || cleanZone.split("/").pop().replace(/_/g, " ")
  out.push(applyCoordinates({
    id: uniqueId(out, cleanName),
    name: cleanName,
    timezone: cleanZone,
    isHome: false
  }, { latitude: latitude, longitude: longitude }, cleanName))
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

function paddedNumber(value) {
  return Number(value) < 10 ? "0" + Number(value) : String(Number(value))
}

function shiftedDateParts(timestampMs, utcOffsetMinutes) {
  var date = new Date(Number(timestampMs) + Number(utcOffsetMinutes || 0) * 60000)
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth(),
    day: date.getUTCDate(),
    weekday: date.getUTCDay(),
    hour: date.getUTCHours(),
    minute: date.getUTCMinutes()
  }
}

function dateKey(parts) {
  return String(parts.year) + "-" + paddedNumber(parts.month + 1) + "-" + paddedNumber(parts.day)
}

function previewDayRelation(parts, homeParts) {
  var day = Date.UTC(parts.year, parts.month, parts.day) / 86400000
  var homeDay = Date.UTC(homeParts.year, homeParts.month, homeParts.day) / 86400000
  var difference = Math.round(day - homeDay)
  if (difference === -1) return "Yesterday"
  if (difference === 0) return "Today"
  if (difference === 1) return "Tomorrow"
  return WEEKDAY_SHORT_NAMES[parts.weekday] + " " + parts.day + " "
    + MONTH_SHORT_NAMES[parts.month] + " " + parts.year
}

// Keep the clock faces and labels under the pointer while the exact zoneinfo
// render is still in flight. The helper replaces this offset-based preview as
// soon as it returns, including any DST transition crossed by the slider.
function previewRenderedRows(rows, renderedTimestamp, planningTimestamp) {
  var source = Array.isArray(rows) ? rows : []
  var rendered = Number(renderedTimestamp)
  var planning = Number(planningTimestamp)
  if (source.length === 0 || !isFinite(rendered) || !isFinite(planning)
      || rendered <= 0 || rendered === planning) return source

  var home = source[0]
  for (var h = 0; h < source.length; h++) {
    if (source[h] && source[h].isHome === true) { home = source[h]; break }
  }
  var homeParts = shiftedDateParts(planning, home && home.utcOffsetMinutes)
  var result = []
  for (var i = 0; i < source.length; i++) {
    var original = source[i] || ({})
    var row = ({})
    for (var key in original) row[key] = original[key]
    var parts = shiftedDateParts(planning, original.utcOffsetMinutes)
    var hour12 = parts.hour % 12 || 12
    row.date = dateKey(parts)
    row.dateLabel = WEEKDAY_SHORT_NAMES[parts.weekday] + " " + parts.day + " "
      + MONTH_SHORT_NAMES[parts.month] + " " + parts.year
    row.weekday = WEEKDAY_NAMES[parts.weekday]
    row.time = paddedNumber(parts.hour) + ":" + paddedNumber(parts.minute)
    row.time12 = String(hour12) + ":" + paddedNumber(parts.minute)
    row.period = parts.hour < 12 ? "AM" : "PM"
    row.hour = parts.hour
    row.minute = parts.minute
    row.isWeekend = parts.weekday === 0 || parts.weekday === 6
    row.dayRelation = previewDayRelation(parts, homeParts)
    result.push(row)
  }
  return result
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

function metadataForRow(row, showAbbreviation, showDifference, showDayRelation) {
  if (!row) return ""
  var parts = []
  if (showDayRelation !== false && !row.isHome
      && row.dayRelation && row.dayRelation !== "Today") parts.push(row.dayRelation)
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
    coordinatesForLocation: coordinatesForLocation,
    normalizeLocations: normalizeLocations,
    homeLocation: homeLocation,
    addLocation: addLocation,
    removeLocation: removeLocation,
    renameLocation: renameLocation,
    moveLocation: moveLocation,
    setHomeLocation: setHomeLocation,
    previewRenderedRows: previewRenderedRows,
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
