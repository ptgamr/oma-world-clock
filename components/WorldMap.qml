import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TimezoneLookup.js" as TimezoneLookup

BorderSurface {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property var rows: service ? service.renderedRows : []
  readonly property string mapDataPath: decodeURIComponent(
    String(Qt.resolvedUrl("../assets/world-land-110m.json")).replace(/^file:\/\//, ""))
  readonly property string timezoneDataPath: decodeURIComponent(
    String(Qt.resolvedUrl("../assets/world-timezones-2026c.json")).replace(/^file:\/\//, ""))
  property var continents: []
  property var timezoneZones: []
  property string mapDataError: ""
  property string timezoneDataError: ""
  property var hoveredBoundary: null
  property var selectedBoundary: null
  property string hoverTimezone: ""
  property string selectedTimezone: ""
  property string selectedName: ""
  property string selectionMessage: ""
  property real selectedLatitude: 0
  property real selectedLongitude: 0

  readonly property bool selectedAlreadyConfigured: timezoneConfigured(selectedTimezone)

  signal addTimezoneRequested(string name, string timezone, real latitude, real longitude)

  // Longitude spans twice the angular range of latitude. Keep the drawable
  // area at 2:1 so the equirectangular projection is not vertically squashed.
  implicitHeight: Style.space(24) + mapHeader.implicitHeight + Style.space(9)
    + Math.max(1, width - Style.space(24)) / 2
  color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

  function xForLongitude(longitude, width) {
    return (Number(longitude) + 180) / 360 * width
  }

  function yForLatitude(latitude, height) {
    return (90 - Number(latitude)) / 180 * height
  }

  function longitudeForX(x, width) {
    return Number(x) / Math.max(1, width) * 360 - 180
  }

  function latitudeForY(y, height) {
    return 90 - Number(y) / Math.max(1, height) * 180
  }

  function displayTime(row) {
    if (!row) return ""
    return root.service && root.service.hourFormat === "24"
      ? row.time
      : row.time12 + " " + row.period
  }

  function timezoneName(timezone) {
    var parts = String(timezone || "").split("/")
    return String(parts[parts.length - 1] || timezone || "Timezone").replace(/_/g, " ")
  }

  function timezoneConfigured(timezone) {
    var locations = root.service && Array.isArray(root.service.locations)
      ? root.service.locations : []
    for (var index = 0; index < locations.length; index++)
      if (String(locations[index].timezone || "") === String(timezone || "")) return true
    return false
  }

  function hitAt(x, y) {
    var longitude = root.longitudeForX(x, mapArea.width)
    var latitude = root.latitudeForY(y, mapArea.height)
    var nearby = TimezoneLookup.locationNear(
      root.rows, longitude, latitude, mapArea.width, mapArea.height, Style.space(12))
    var boundary = TimezoneLookup.zoneAt(root.timezoneZones, longitude, latitude)
    return {
      longitude: longitude,
      latitude: latitude,
      nearby: nearby,
      boundary: boundary,
      timezone: nearby ? String(nearby.timezone || "") : (boundary ? String(boundary.id || "") : ""),
      name: nearby ? String(nearby.name || "") : ""
    }
  }

  function updateHover(x, y) {
    var hit = root.hitAt(x, y)
    var nextTimezone = hit.timezone
    var nextBoundary = hit.boundary && (!hit.nearby || hit.boundary.id === hit.timezone)
      ? hit.boundary : null
    if (nextTimezone === root.hoverTimezone && nextBoundary === root.hoveredBoundary) return
    root.hoverTimezone = nextTimezone
    root.hoveredBoundary = nextBoundary
    highlightCanvas.requestPaint()
  }

  function selectAt(x, y) {
    var hit = root.hitAt(x, y)
    root.selectedLongitude = Math.round(hit.longitude * 10000) / 10000
    root.selectedLatitude = Math.round(hit.latitude * 10000) / 10000
    root.selectedTimezone = hit.timezone
    root.selectedName = hit.name || root.timezoneName(hit.timezone)
    root.selectedBoundary = hit.boundary && (!hit.nearby || hit.boundary.id === hit.timezone)
      ? hit.boundary : null
    root.selectionMessage = hit.timezone === ""
      ? "No land timezone at that point"
      : "Selected · " + hit.timezone
    highlightCanvas.requestPaint()
  }

  function selectCoordinate(longitude, latitude) {
    root.selectAt(root.xForLongitude(longitude, mapArea.width),
      root.yForLatitude(latitude, mapArea.height))
  }

  function traceTimezonePolygon(context, polygon, targetWidth, targetHeight) {
    if (!polygon || !Array.isArray(polygon[1])) return false
    var rings = polygon[1]
    context.beginPath()
    for (var ringIndex = 0; ringIndex < rings.length; ringIndex++) {
      var ring = rings[ringIndex]
      if (!Array.isArray(ring) || ring.length < 4) continue
      context.moveTo(root.xForLongitude(ring[0][0], targetWidth),
        root.yForLatitude(ring[0][1], targetHeight))
      for (var pointIndex = 1; pointIndex < ring.length; pointIndex++)
        context.lineTo(root.xForLongitude(ring[pointIndex][0], targetWidth),
          root.yForLatitude(ring[pointIndex][1], targetHeight))
      context.closePath()
    }
    return true
  }

  function drawTimezoneZone(context, zone, targetWidth, targetHeight, fill, stroke, lineWidth) {
    if (!zone || !Array.isArray(zone.polygons)) return
    context.fillStyle = fill
    context.strokeStyle = stroke
    context.lineWidth = lineWidth
    for (var index = 0; index < zone.polygons.length; index++) {
      if (!root.traceTimezonePolygon(context, zone.polygons[index], targetWidth, targetHeight))
        continue
      if (fill.a > 0) context.fill()
      if (stroke.a > 0) context.stroke()
    }
  }

  function loadMapData(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (!data || !Array.isArray(data.polygons) || data.polygons.length === 0)
        throw new Error("missing polygons")
      root.continents = data.polygons
      root.mapDataError = ""
    } catch (error) {
      root.continents = []
      root.mapDataError = "Map data unavailable"
    }
  }

  function loadTimezoneData(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (!data || !Array.isArray(data.zones) || data.zones.length === 0)
        throw new Error("missing zones")
      root.timezoneZones = data.zones
      root.timezoneDataError = ""
    } catch (error) {
      root.timezoneZones = []
      root.timezoneDataError = "Timezone boundaries unavailable"
    }
  }

  FileView {
    id: mapDataFile
    path: root.mapDataPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadMapData(text())
    onLoadFailed: root.mapDataError = "Map data unavailable"
  }

  FileView {
    id: timezoneDataFile
    path: root.timezoneDataPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadTimezoneData(text())
    onLoadFailed: root.timezoneDataError = "Timezone boundaries unavailable"
  }

  onContinentsChanged: Qt.callLater(function() { mapCanvas.requestPaint() })
  onTimezoneZonesChanged: Qt.callLater(function() { boundaryCanvas.requestPaint() })

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(12)

    Row {
      id: mapHeader
      anchors.left: parent.left
      anchors.top: parent.top
      spacing: Style.space(9)

      Text {
        textFormat: Text.PlainText
        text: "WORLD MAP"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        font.letterSpacing: 1
      }

      Text {
        textFormat: Text.PlainText
        text: "DAY / NIGHT AT SELECTED TIME"
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.top: parent.top
      width: Math.min(parent.width * 0.46, Style.space(390))
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: root.hoverTimezone !== "" ? root.hoverTimezone
        : root.selectionMessage !== "" ? root.selectionMessage
        : root.timezoneZones.length > 0 ? "CLICK A REGION TO SELECT A TIMEZONE"
        : root.timezoneDataError !== "" ? root.timezoneDataError
        : "LOADING TIMEZONE BOUNDARIES…"
      color: root.hoverTimezone !== "" ? root.accent : Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.hoverTimezone !== ""
    }

    Item {
      id: mapArea
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: mapHeader.bottom
      anchors.topMargin: Style.space(9)
      height: width / 2
      clip: true

      Canvas {
        id: mapCanvas
        anchors.fill: parent

        function tracePolygon(context, points) {
          if (!points || points.length === 0) return
          context.beginPath()
          context.moveTo(root.xForLongitude(points[0][0], width), root.yForLatitude(points[0][1], height))
          for (var i = 1; i < points.length; i++)
            context.lineTo(root.xForLongitude(points[i][0], width), root.yForLatitude(points[i][1], height))
          context.closePath()
        }

        function drawContinents(context, fill) {
          context.fillStyle = fill
          context.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.30)
          context.lineWidth = 1
          for (var i = 0; i < root.continents.length; i++) {
            tracePolygon(context, root.continents[i])
            context.fill()
            context.stroke()
          }
        }

        function drawNight(context) {
          var timestamp = root.service ? Number(root.service.planningTimestamp) : Date.now()
          var value = new Date(timestamp)
          var yearStart = Date.UTC(value.getUTCFullYear(), 0, 0)
          var day = Math.floor((timestamp - yearStart) / 86400000)
          var utcHour = value.getUTCHours() + value.getUTCMinutes() / 60
            + value.getUTCSeconds() / 3600
          var declination = 23.44 * Math.sin(2 * Math.PI * (284 + day) / 365)
          var declinationRadians = declination * Math.PI / 180

          function boundaryLatitude(longitude) {
            var hourAngle = (15 * (utcHour - 12) + longitude) * Math.PI / 180
            var latitude = Math.atan2(
              -Math.cos(declinationRadians) * Math.cos(hourAngle),
              Math.sin(declinationRadians)) * 180 / Math.PI
            if (latitude > 90) latitude -= 180
            else if (latitude < -90) latitude += 180
            return latitude
          }

          context.beginPath()
          context.moveTo(root.xForLongitude(-180, width),
            root.yForLatitude(declination >= 0 ? -90 : 90, height))
          context.lineTo(root.xForLongitude(-180, width),
            root.yForLatitude(boundaryLatitude(-180), height))
          for (var longitude = -179; longitude <= 180; longitude += 1)
            context.lineTo(root.xForLongitude(longitude, width),
              root.yForLatitude(boundaryLatitude(longitude), height))
          context.lineTo(root.xForLongitude(180, width),
            root.yForLatitude(declination >= 0 ? -90 : 90, height))
          context.closePath()
          context.fillStyle = Qt.rgba(0.01, 0.02, 0.05, 0.42)
          context.fill()
          context.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          context.lineWidth = 1
          context.stroke()
        }

        onPaint: {
          var context = getContext("2d")
          context.clearRect(0, 0, width, height)
          context.fillStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.035)
          context.fillRect(0, 0, width, height)

          context.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          context.lineWidth = 1
          for (var longitude = -120; longitude <= 120; longitude += 60) {
            var x = root.xForLongitude(longitude, width)
            context.beginPath()
            context.moveTo(x, 0)
            context.lineTo(x, height)
            context.stroke()
          }
          for (var latitude = -60; latitude <= 60; latitude += 30) {
            var y = root.yForLatitude(latitude, height)
            context.beginPath()
            context.moveTo(0, y)
            context.lineTo(width, y)
            context.stroke()
          }

          drawContinents(context, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15))
          drawNight(context)
          drawContinents(context, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035))
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
      }

      Canvas {
        id: boundaryCanvas
        anchors.fill: parent
        z: 0.25

        onPaint: {
          var context = getContext("2d")
          context.clearRect(0, 0, width, height)
          context.strokeStyle = Qt.rgba(
            root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          context.lineWidth = 0.7
          for (var zoneIndex = 0; zoneIndex < root.timezoneZones.length; zoneIndex++) {
            var zone = root.timezoneZones[zoneIndex]
            var polygons = zone && Array.isArray(zone.polygons) ? zone.polygons : []
            for (var polygonIndex = 0; polygonIndex < polygons.length; polygonIndex++) {
              if (root.traceTimezonePolygon(context, polygons[polygonIndex], width, height))
                context.stroke()
            }
          }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
      }

      Canvas {
        id: highlightCanvas
        anchors.fill: parent
        z: 0.5

        onPaint: {
          var context = getContext("2d")
          context.clearRect(0, 0, width, height)
          if (root.hoveredBoundary
              && (!root.selectedBoundary || root.hoveredBoundary.id !== root.selectedBoundary.id))
            root.drawTimezoneZone(context, root.hoveredBoundary, width, height,
              Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08),
              Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.72), 1.2)
          if (root.selectedBoundary)
            root.drawTimezoneZone(context, root.selectedBoundary, width, height,
              Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16),
              Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.95), 1.7)
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
      }

      MouseArea {
        id: mapPointer
        anchors.fill: parent
        z: 1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: root.hoverTimezone === "" ? Qt.CrossCursor : Qt.PointingHandCursor
        onPositionChanged: function(mouse) { root.updateHover(mouse.x, mouse.y) }
        onClicked: function(mouse) { root.selectAt(mouse.x, mouse.y) }
        onExited: {
          root.hoverTimezone = ""
          root.hoveredBoundary = null
          highlightCanvas.requestPaint()
        }
      }

      Connections {
        target: root.service
        function onPlanningTimestampChanged() { mapCanvas.requestPaint() }
      }

      Repeater {
        model: root.rows

        Item {
          id: marker
          required property var modelData
          readonly property bool hasCoordinates: modelData.latitude !== null
            && modelData.longitude !== null
            && isFinite(Number(modelData.latitude)) && isFinite(Number(modelData.longitude))
          visible: hasCoordinates
          x: root.xForLongitude(modelData.longitude, mapArea.width)
          y: root.yForLatitude(modelData.latitude, mapArea.height)
          z: 2

          Rectangle {
            anchors.centerIn: parent
            width: marker.modelData.isHome ? Style.space(10) : Style.space(8)
            height: width
            radius: 0
            color: marker.modelData.isHome ? root.accent : root.foreground
            border.width: Style.space(1)
            border.color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
          }

          Rectangle {
            x: Number(marker.modelData.longitude) > 110 ? -width - Style.space(7) : Style.space(7)
            y: -height / 2
            width: markerLabel.implicitWidth + Style.space(10)
            height: markerLabel.implicitHeight + Style.space(6)
            color: Qt.rgba(0.02, 0.025, 0.04, 0.84)
            border.width: Style.spacing.hairline
            border.color: marker.modelData.isHome ? root.accent
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)

            Text {
              textFormat: Text.PlainText
              id: markerLabel
              anchors.centerIn: parent
              text: marker.modelData.name + "  " + root.displayTime(marker.modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: marker.modelData.isHome
            }
          }
        }
      }

      Rectangle {
        visible: root.selectedTimezone !== ""
        x: root.xForLongitude(root.selectedLongitude, mapArea.width) - width / 2
        y: root.yForLatitude(root.selectedLatitude, mapArea.height) - height / 2
        z: 3
        width: Style.space(10)
        height: width
        radius: 0
        color: root.accent
        border.width: Style.space(1)
        border.color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
      }

      Rectangle {
        id: hoverLabel
        visible: root.hoverTimezone !== "" && root.hoverTimezone !== root.selectedTimezone
        z: 4
        x: Math.max(Style.space(6), Math.min(mapArea.width - width - Style.space(6),
          mapPointer.mouseX + Style.space(12)))
        y: Math.max(Style.space(6), Math.min(mapArea.height - height - Style.space(6),
          mapPointer.mouseY - height - Style.space(8)))
        width: hoverText.implicitWidth + Style.space(12)
        height: hoverText.implicitHeight + Style.space(7)
        color: Qt.rgba(0.02, 0.025, 0.04, 0.9)
        border.width: Style.spacing.hairline
        border.color: root.accent

        Text {
          textFormat: Text.PlainText
          id: hoverText
          anchors.centerIn: parent
          text: root.hoverTimezone
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Rectangle {
        id: timezoneSelection
        visible: root.selectedTimezone !== ""
        z: 5
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(12)
        width: Math.min(mapArea.width - Style.space(24), Style.space(430))
        height: Style.space(66)
        color: Qt.rgba(0.02, 0.025, 0.04, 0.93)
        border.width: Style.spacing.hairline
        border.color: root.accent

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.right: addTimezoneButton.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: root.selectedName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: root.selectedTimezone
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Button {
          id: addTimezoneButton
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: root.selectedAlreadyConfigured ? "Added" : "Add clock"
          tooltipText: root.selectedAlreadyConfigured
            ? "This timezone is already configured" : "Add this timezone to the clock list"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: !root.selectedAlreadyConfigured
          onClicked: root.addTimezoneRequested(root.selectedName, root.selectedTimezone,
            root.selectedLatitude, root.selectedLongitude)
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(7)
        z: 4
        text: "timezone-boundary-builder · ODbL"
        color: Qt.darker(root.foreground, 1.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        visible: root.mapDataError !== ""
        anchors.centerIn: parent
        text: root.mapDataError
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
