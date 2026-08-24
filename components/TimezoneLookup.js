function insideBounds(bounds, longitude, latitude) {
  return Array.isArray(bounds) && bounds.length === 4
    && longitude >= Number(bounds[0]) && longitude <= Number(bounds[2])
    && latitude >= Number(bounds[1]) && latitude <= Number(bounds[3])
}

function pointOnSegment(longitude, latitude, start, end) {
  var dx = Number(end[0]) - Number(start[0])
  var dy = Number(end[1]) - Number(start[1])
  if (dx === 0 && dy === 0)
    return Math.abs(longitude - Number(start[0])) <= 0.000001
      && Math.abs(latitude - Number(start[1])) <= 0.000001
  var cross = (longitude - Number(start[0])) * dy - (latitude - Number(start[1])) * dx
  if (Math.abs(cross) > 0.000001) return false
  var dot = (longitude - Number(start[0])) * dx + (latitude - Number(start[1])) * dy
  if (dot < 0) return false
  return dot <= dx * dx + dy * dy
}

function ringContains(ring, longitude, latitude) {
  if (!Array.isArray(ring) || ring.length < 4) return false
  var inside = false
  for (var index = 0, previous = ring.length - 1; index < ring.length; previous = index++) {
    var currentPoint = ring[index]
    var previousPoint = ring[previous]
    if (pointOnSegment(longitude, latitude, previousPoint, currentPoint)) return true
    var crosses = (Number(currentPoint[1]) > latitude) !== (Number(previousPoint[1]) > latitude)
    if (crosses) {
      var crossingLongitude = (Number(previousPoint[0]) - Number(currentPoint[0]))
        * (latitude - Number(currentPoint[1]))
        / (Number(previousPoint[1]) - Number(currentPoint[1])) + Number(currentPoint[0])
      if (longitude < crossingLongitude) inside = !inside
    }
  }
  return inside
}

function polygonContains(polygon, longitude, latitude) {
  if (!Array.isArray(polygon) || polygon.length !== 2
      || !insideBounds(polygon[0], longitude, latitude)) return false
  var rings = polygon[1]
  if (!Array.isArray(rings) || rings.length === 0
      || !ringContains(rings[0], longitude, latitude)) return false
  for (var index = 1; index < rings.length; index++)
    if (ringContains(rings[index], longitude, latitude)) return false
  return true
}

function zoneAt(zones, longitude, latitude) {
  if (!Array.isArray(zones) || !isFinite(longitude) || !isFinite(latitude)) return null
  var match = null
  var matchArea = Infinity
  for (var zoneIndex = 0; zoneIndex < zones.length; zoneIndex++) {
    var zone = zones[zoneIndex]
    if (!zone || !insideBounds(zone.bounds, longitude, latitude)) continue
    var polygons = Array.isArray(zone.polygons) ? zone.polygons : []
    for (var polygonIndex = 0; polygonIndex < polygons.length; polygonIndex++) {
      var polygon = polygons[polygonIndex]
      if (!polygonContains(polygon, longitude, latitude)) continue
      var bounds = polygon[0]
      var area = Math.abs((Number(bounds[2]) - Number(bounds[0]))
        * (Number(bounds[3]) - Number(bounds[1])))
      if (area < matchArea) {
        match = zone
        matchArea = area
      }
    }
  }
  return match
}

function zoneById(zones, timezone) {
  if (!Array.isArray(zones)) return null
  for (var index = 0; index < zones.length; index++)
    if (zones[index] && String(zones[index].id || "") === String(timezone || ""))
      return zones[index]
  return null
}

function locationNear(locations, longitude, latitude, mapWidth, mapHeight, maximumPixels) {
  if (!Array.isArray(locations) || mapWidth <= 0 || mapHeight <= 0) return null
  var match = null
  var matchDistance = Number(maximumPixels) * Number(maximumPixels)
  for (var index = 0; index < locations.length; index++) {
    var location = locations[index]
    var locationLongitude = Number(location && location.longitude)
    var locationLatitude = Number(location && location.latitude)
    if (!isFinite(locationLongitude) || !isFinite(locationLatitude)) continue
    var longitudeDistance = Math.abs(locationLongitude - longitude)
    longitudeDistance = Math.min(longitudeDistance, 360 - longitudeDistance)
    var dx = longitudeDistance / 360 * mapWidth
    var dy = Math.abs(locationLatitude - latitude) / 180 * mapHeight
    var distance = dx * dx + dy * dy
    if (distance <= matchDistance) {
      match = location
      matchDistance = distance
    }
  }
  return match
}

if (typeof module !== "undefined") {
  module.exports = {
    insideBounds: insideBounds,
    ringContains: ringContains,
    polygonContains: polygonContains,
    zoneAt: zoneAt,
    zoneById: zoneById,
    locationNear: locationNear
  }
}
