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

// Settings are user-editable and are also supplied to a long-lived shell
// process. Keep all amplification points small and deterministic.
var MAX_LOCATIONS = 12
var MAX_LOCATION_ID_LENGTH = 64
var MAX_LOCATION_NAME_LENGTH = 80
var MAX_TIMEZONE_LENGTH = 128
var MAX_SEARCH_QUERY_LENGTH = 80
var MAX_LOCATIONS_JSON_BYTES = 8192
var MAX_HELPER_OUTPUT_BYTES = 256 * 1024
var MAX_HELPER_ERROR_LENGTH = 256
var MAX_SEARCH_RESULTS = 6

function cleanText(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "")
}

function limitedText(value, maximumLength) {
  if (typeof value !== "string") return ""
  return cleanText(value).slice(0, maximumLength)
}

function validResultText(value, maximumLength, allowEmpty) {
  return typeof value === "string" && value.length <= maximumLength
    && (allowEmpty === true || value.length > 0)
}

function validTimezoneText(value) {
  if (!validResultText(value, MAX_TIMEZONE_LENGTH, false)) return false
  var parts = value.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "" || parts[i] === "." || parts[i] === ".."
        || !/^[A-Za-z0-9_+.-]+$/.test(parts[i])) return false
  }
  return true
}

function utf8ByteLength(value) {
  var text = String(value || "")
  var length = 0
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code <= 0x7f) length += 1
    else if (code <= 0x7ff) length += 2
    else if (code >= 0xd800 && code <= 0xdbff
        && i + 1 < text.length) {
      var next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        length += 4
        i++
      } else length += 3
    } else length += 3
  }
  return length
}

function securityLimits() {
  return {
    maxLocations: MAX_LOCATIONS,
    maxLocationIdLength: MAX_LOCATION_ID_LENGTH,
    maxLocationNameLength: MAX_LOCATION_NAME_LENGTH,
    maxTimezoneLength: MAX_TIMEZONE_LENGTH,
    maxSearchQueryLength: MAX_SEARCH_QUERY_LENGTH,
    maxLocationsJsonBytes: MAX_LOCATIONS_JSON_BYTES,
    maxHelperOutputBytes: MAX_HELPER_OUTPUT_BYTES,
    maxSearchResults: MAX_SEARCH_RESULTS
  }
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
  var name = limitedText(location && location.name, MAX_LOCATION_NAME_LENGTH)
  return applyCoordinates({
    id: limitedText(location && location.id, MAX_LOCATION_ID_LENGTH),
    name: name,
    timezone: limitedText(location && location.timezone, MAX_TIMEZONE_LENGTH),
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
  return (slug || "location").slice(0, MAX_LOCATION_ID_LENGTH)
}

function uniqueBoundedId(seen, preferred) {
  var base = limitedText(preferred, MAX_LOCATION_ID_LENGTH) || "location"
  var candidate = base
  var suffix = 2
  while (seen[candidate]) {
    var ending = "-" + suffix++
    candidate = base.slice(0, MAX_LOCATION_ID_LENGTH - ending.length) + ending
  }
  return candidate
}

function uniqueId(locations, preferred) {
  var used = {}
  for (var i = 0; i < locations.length; i++) used[String(locations[i].id)] = true
  return uniqueBoundedId(used, slugify(preferred))
}

function normalizeLocations(value) {
  if (!Array.isArray(value) || value.length === 0) return defaultLocations()

  var out = []
  var seen = {}
  var homeFound = false
  var inspectedCount = Math.min(value.length, MAX_LOCATIONS)
  for (var i = 0; i < inspectedCount; i++) {
    var source = value[i]
    if (!source || typeof source !== "object") continue
    if (typeof source.timezone !== "string") continue
    var rawTimezone = cleanText(source.timezone)
    if (!validTimezoneText(rawTimezone)) continue
    var timezone = rawTimezone

    var name = limitedText(source.name, MAX_LOCATION_NAME_LENGTH)
      || timezone.split("/").pop().replace(/_/g, " ").slice(0, MAX_LOCATION_NAME_LENGTH)
    var baseId = limitedText(source.id, MAX_LOCATION_ID_LENGTH) || slugify(name)
    var id = uniqueBoundedId(seen, baseId)
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
  if (out.length >= MAX_LOCATIONS || typeof timezone !== "string") return out
  var cleanZone = cleanText(timezone)
  if (!validTimezoneText(cleanZone)) return out
  var cleanName = limitedText(name, MAX_LOCATION_NAME_LENGTH)
    || cleanZone.split("/").pop().replace(/_/g, " ").slice(0, MAX_LOCATION_NAME_LENGTH)
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
  var cleanName = limitedText(name, MAX_LOCATION_NAME_LENGTH)
  if (cleanName === "") return normalized
  for (var i = 0; i < normalized.length; i++) {
    if (normalized[i].id === id) normalized[i].name = cleanName
  }
  return normalized
}

function helperLocationsPayload(value) {
  var locations = normalizeLocations(value)
  var serialized = JSON.stringify(locations)
  if (utf8ByteLength(serialized) > MAX_LOCATIONS_JSON_BYTES) return null
  return { locations: locations, serialized: serialized }
}

function helperOutputAllowed(raw) {
  return typeof raw === "string" && utf8ByteLength(raw) <= MAX_HELPER_OUTPUT_BYTES
}

function boundedSearchQuery(value) {
  return limitedText(String(value || ""), MAX_SEARCH_QUERY_LENGTH)
}

function helperResultError(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || !("error" in value)) return ""
  if (validResultText(value.error, MAX_HELPER_ERROR_LENGTH, false)) return value.error
  return "Timezone helper returned an invalid error."
}

function finiteNumber(value, minimum, maximum) {
  return typeof value === "number" && isFinite(value)
    && value >= minimum && value <= maximum
}

function integerInRange(value, minimum, maximum) {
  return finiteNumber(value, minimum, maximum) && Math.floor(value) === value
}

function validDate(value) {
  return validResultText(value, 10, false) && /^\d{4}-\d{2}-\d{2}$/.test(value)
}

function validTime(value) {
  return validResultText(value, 5, false) && /^\d{1,2}:\d{2}$/.test(value)
}

function matchesLocation(row, expected) {
  return row && typeof row === "object" && !Array.isArray(row)
    && row.id === expected.id && row.name === expected.name
    && row.timezone === expected.timezone && row.isHome === expected.isHome
}

function sanitizedCalendar(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || !validResultText(value.monthLabel, 32, false)
      || !integerInRange(value.weekNumber, 1, 53)
      || !Array.isArray(value.days) || value.days.length !== 7) return null
  var days = []
  for (var i = 0; i < value.days.length; i++) {
    var day = value.days[i]
    if (!day || typeof day !== "object" || Array.isArray(day)
        || !validDate(day.date) || !validResultText(day.weekday, 3, false)
        || !integerInRange(day.day, 1, 31) || !integerInRange(day.offsetDays, -6, 6)
        || typeof day.isSelected !== "boolean"
        || typeof day.isAdjacentMonth !== "boolean") return null
    days.push({
      date: day.date,
      weekday: day.weekday,
      day: day.day,
      offsetDays: day.offsetDays,
      isSelected: day.isSelected,
      isAdjacentMonth: day.isAdjacentMonth
    })
  }
  return { monthLabel: value.monthLabel, weekNumber: value.weekNumber, days: days }
}

function sanitizedRenderedRow(row, expected) {
  if (!matchesLocation(row, expected)
      || !validDate(row.date) || !validResultText(row.dateLabel, 32, false)
      || !validResultText(row.weekday, 9, false) || !validTime(row.time)
      || !validTime(row.time12) || !/^(AM|PM)$/.test(row.period)
      || !integerInRange(row.hour, 0, 23) || !integerInRange(row.minute, 0, 59)
      || typeof row.isWeekend !== "boolean"
      || !integerInRange(row.utcOffsetMinutes, -24 * 60, 24 * 60)
      || !integerInRange(row.offsetDifferenceMinutes, -48 * 60, 48 * 60)
      || !validResultText(row.abbreviation, 16, true)
      || !validResultText(row.dayRelation, 32, false)) return null
  if (row.latitude !== null && !finiteNumber(row.latitude, -90, 90)) return null
  if (row.longitude !== null && !finiteNumber(row.longitude, -180, 180)) return null
  return {
    id: expected.id,
    name: expected.name,
    timezone: expected.timezone,
    isHome: expected.isHome,
    date: row.date,
    dateLabel: row.dateLabel,
    weekday: row.weekday,
    time: row.time,
    time12: row.time12,
    period: row.period,
    hour: row.hour,
    minute: row.minute,
    latitude: row.latitude,
    longitude: row.longitude,
    isWeekend: row.isWeekend,
    utcOffsetMinutes: row.utcOffsetMinutes,
    offsetDifferenceMinutes: row.offsetDifferenceMinutes,
    abbreviation: row.abbreviation,
    dayRelation: row.dayRelation
  }
}

function sanitizedRenderResult(value, expectedTimestamp, expectedLocations) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || value.timestampMs !== expectedTimestamp || !validDate(value.homeDate)
      || !validResultText(value.homeDateLabel, 32, false)
      || !Array.isArray(value.rows) || value.rows.length !== expectedLocations.length
      || value.rows.length > MAX_LOCATIONS) return null
  var calendar = sanitizedCalendar(value.calendar)
  if (!calendar) return null
  var rows = []
  for (var i = 0; i < value.rows.length; i++) {
    var row = sanitizedRenderedRow(value.rows[i], expectedLocations[i])
    if (!row) return null
    rows.push(row)
  }
  return {
    timestampMs: value.timestampMs,
    homeDate: value.homeDate,
    homeDateLabel: value.homeDateLabel,
    calendar: calendar,
    rows: rows
  }
}

function sanitizedTimelineCell(value, expectedTimestamp, expectedOffset) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || value.offsetMinutes !== expectedOffset || value.timestampMs !== expectedTimestamp
      || !validDate(value.date) || !validResultText(value.weekday, 9, false)
      || !validTime(value.time) || !validTime(value.time12)
      || !/^(AM|PM)$/.test(value.period)
      || !integerInRange(value.hour, 0, 23) || !integerInRange(value.minute, 0, 59)
      || typeof value.isWeekend !== "boolean" || typeof value.isDaytime !== "boolean"
      || !/^(work|edge|off)$/.test(value.availability)) return null
  return {
    offsetMinutes: value.offsetMinutes,
    timestampMs: value.timestampMs,
    date: value.date,
    weekday: value.weekday,
    time: value.time,
    time12: value.time12,
    period: value.period,
    hour: value.hour,
    minute: value.minute,
    isWeekend: value.isWeekend,
    isDaytime: value.isDaytime,
    availability: value.availability
  }
}

function sanitizedTimelineResult(value, expectedStart, expectedLocations) {
  var hours = 24
  var stepMinutes = 30
  var slotCount = hours * 60 / stepMinutes
  if (!value || typeof value !== "object" || Array.isArray(value)
      || value.startTimestampMs !== expectedStart
      || value.endTimestampMs !== expectedStart + hours * 60 * 60 * 1000
      || value.hours !== hours || value.stepMinutes !== stepMinutes
      || value.slotCount !== slotCount || !Array.isArray(value.ticks)
      || value.ticks.length !== 5 || !Array.isArray(value.rows)
      || value.rows.length !== expectedLocations.length
      || value.rows.length > MAX_LOCATIONS) return null
  var ticks = []
  for (var t = 0; t < value.ticks.length; t++) {
    var tick = value.ticks[t]
    var expectedOffset = t * 6 * 60
    if (!tick || typeof tick !== "object" || Array.isArray(tick)
        || tick.offsetMinutes !== expectedOffset || !validTime(tick.time)
        || !validResultText(tick.weekday, 3, false) || !validDate(tick.date)) return null
    ticks.push({
      offsetMinutes: tick.offsetMinutes,
      time: tick.time,
      weekday: tick.weekday,
      date: tick.date
    })
  }
  var rows = []
  for (var r = 0; r < value.rows.length; r++) {
    var source = value.rows[r]
    var expected = expectedLocations[r]
    if (!matchesLocation(source, expected) || !Array.isArray(source.cells)
        || source.cells.length !== slotCount) return null
    var cells = []
    for (var c = 0; c < source.cells.length; c++) {
      var offset = c * stepMinutes
      var cell = sanitizedTimelineCell(
        source.cells[c], expectedStart + offset * 60000, offset)
      if (!cell) return null
      cells.push(cell)
    }
    rows.push({
      id: expected.id,
      name: expected.name,
      timezone: expected.timezone,
      isHome: expected.isHome,
      cells: cells
    })
  }
  return {
    startTimestampMs: value.startTimestampMs,
    endTimestampMs: value.endTimestampMs,
    hours: hours,
    stepMinutes: stepMinutes,
    slotCount: slotCount,
    ticks: ticks,
    rows: rows
  }
}

function sanitizedMeetingResult(value, expectedStart, expectedDuration, expectedLocations) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || value.startTimestampMs !== expectedStart
      || value.endTimestampMs !== expectedStart + expectedDuration * 60000
      || value.durationMinutes !== expectedDuration || !validDate(value.homeDate)
      || !validResultText(value.homeDateLabel, 48, false)
      || !Array.isArray(value.rows) || value.rows.length !== expectedLocations.length
      || value.rows.length > MAX_LOCATIONS) return null
  var rows = []
  for (var i = 0; i < value.rows.length; i++) {
    var row = value.rows[i]
    var expected = expectedLocations[i]
    if (!matchesLocation(row, expected) || !validDate(row.startDate)
        || !validResultText(row.startWeekday, 9, false)
        || !validResultText(row.range12, 48, false)
        || !validResultText(row.range24, 48, false)
        || !validResultText(row.abbreviation, 16, true)) return null
    rows.push({
      id: expected.id,
      name: expected.name,
      timezone: expected.timezone,
      isHome: expected.isHome,
      startDate: row.startDate,
      startWeekday: row.startWeekday,
      range12: row.range12,
      range24: row.range24,
      abbreviation: row.abbreviation
    })
  }
  return {
    startTimestampMs: value.startTimestampMs,
    endTimestampMs: value.endTimestampMs,
    durationMinutes: value.durationMinutes,
    homeDate: value.homeDate,
    homeDateLabel: value.homeDateLabel,
    rows: rows
  }
}

function sanitizedShiftDateResult(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || !finiteNumber(value.timestampMs, -8640000000000000, 8640000000000000)
      || !validDate(value.date) || typeof value.normalized !== "boolean") return null
  return { timestampMs: value.timestampMs, date: value.date, normalized: value.normalized }
}

function sanitizedDetectedTimezone(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || !validTimezoneText(value.timezone)) return ""
  return value.timezone
}

function sanitizedSearchResults(value) {
  if (!Array.isArray(value) || value.length > MAX_SEARCH_RESULTS) return null
  var result = []
  for (var i = 0; i < value.length; i++) {
    var item = value[i]
    if (!item || typeof item !== "object" || Array.isArray(item)
        || !validResultText(item.name, MAX_LOCATION_NAME_LENGTH, false)
        || !validTimezoneText(item.timezone)
        || !validResultText(item.country, 128, true)) return null
    if (item.latitude !== undefined && item.latitude !== null
        && !finiteNumber(item.latitude, -90, 90)) return null
    if (item.longitude !== undefined && item.longitude !== null
        && !finiteNumber(item.longitude, -180, 180)) return null
    result.push({
      name: item.name,
      timezone: item.timezone,
      country: item.country,
      latitude: item.latitude === undefined ? null : item.latitude,
      longitude: item.longitude === undefined ? null : item.longitude
    })
  }
  return result
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

function clampedIndex(index, count) {
  var length = Math.max(0, Number(count || 0))
  if (length === 0) return -1
  return Math.max(0, Math.min(length - 1, Number(index || 0)))
}

function movedSelection(index, count, delta, cursorActive) {
  var length = Math.max(0, Number(count || 0))
  if (length === 0) return -1
  if (cursorActive !== true) return Number(delta || 0) < 0 ? length - 1 : 0
  return clampedIndex(Number(index || 0) + Number(delta || 0), length)
}

function pointerMoved(fromX, fromY, toX, toY, threshold) {
  var previousX = Number(fromX)
  var previousY = Number(fromY)
  var currentX = Number(toX)
  var currentY = Number(toY)
  if (!isFinite(previousX) || !isFinite(previousY)
      || !isFinite(currentX) || !isFinite(currentY)) return true
  var minimum = Math.max(0, Number(threshold || 0))
  var deltaX = currentX - previousX
  var deltaY = currentY - previousY
  return deltaX * deltaX + deltaY * deltaY > minimum * minimum
}

function reorderOffset(index, from, to, step) {
  var row = Number(index)
  var source = Number(from)
  var target = Number(to)
  var distance = Number(step)
  if (source < 0 || target < 0 || !(distance > 0)) return 0
  if (row === source) return (target - source) * distance
  if (source < target && row > source && row <= target) return -distance
  if (source > target && row >= target && row < source) return distance
  return 0
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
  return Math.max(-1440, Math.min(1440, minutes))
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

function plannerTooltipLabel(row, hourFormat) {
  if (!row) return ""
  var weekday = cleanText(row.weekday).slice(0, 3)
  var date = /^(\d{4})-(\d{2})-(\d{2})$/.exec(cleanText(row.date))
  var dateLabel = weekday
  if (date) {
    var month = MONTH_SHORT_NAMES[Math.max(0, Math.min(11, Number(date[2]) - 1))]
    dateLabel = [weekday, month, String(Number(date[3]))].filter(Boolean).join(" ")
  }
  var time = hourFormat === "24"
    ? cleanText(row.time)
    : [cleanText(row.time12), cleanText(row.period)].filter(Boolean).join(" ")
  return [dateLabel, time].filter(Boolean).join(" ")
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
    securityLimits: securityLimits,
    utf8ByteLength: utf8ByteLength,
    helperLocationsPayload: helperLocationsPayload,
    helperOutputAllowed: helperOutputAllowed,
    boundedSearchQuery: boundedSearchQuery,
    helperResultError: helperResultError,
    sanitizedRenderResult: sanitizedRenderResult,
    sanitizedTimelineResult: sanitizedTimelineResult,
    sanitizedMeetingResult: sanitizedMeetingResult,
    sanitizedShiftDateResult: sanitizedShiftDateResult,
    sanitizedDetectedTimezone: sanitizedDetectedTimezone,
    sanitizedSearchResults: sanitizedSearchResults,
    defaultLocations: defaultLocations,
    coordinatesForLocation: coordinatesForLocation,
    normalizeLocations: normalizeLocations,
    homeLocation: homeLocation,
    addLocation: addLocation,
    removeLocation: removeLocation,
    renameLocation: renameLocation,
    moveLocation: moveLocation,
    setHomeLocation: setHomeLocation,
    clampedIndex: clampedIndex,
    movedSelection: movedSelection,
    pointerMoved: pointerMoved,
    reorderOffset: reorderOffset,
    previewRenderedRows: previewRenderedRows,
    clampPlannerMinutes: clampPlannerMinutes,
    formatDuration: formatDuration,
    planningLabel: planningLabel,
    plannerTooltipLabel: plannerTooltipLabel,
    formatTimezoneDifference: formatTimezoneDifference,
    availability: availability,
    isDaytime: isDaytime,
    analogMinuteAngle: analogMinuteAngle,
    analogSecondAngle: analogSecondAngle,
    analogHourAngle: analogHourAngle,
    metadataForRow: metadataForRow
  }
}
