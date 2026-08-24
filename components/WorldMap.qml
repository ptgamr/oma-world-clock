import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

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
  property var continents: []
  property string mapDataError: ""

  implicitHeight: Style.space(268)
  color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

  function xForLongitude(longitude, width) {
    return (Number(longitude) + 180) / 360 * width
  }

  function yForLatitude(latitude, height) {
    return (90 - Number(latitude)) / 180 * height
  }

  function displayTime(row) {
    if (!row) return ""
    return root.service && root.service.hourFormat === "24"
      ? row.time
      : row.time12 + " " + row.period
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

  FileView {
    id: mapDataFile
    path: root.mapDataPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadMapData(text())
    onLoadFailed: root.mapDataError = "Map data unavailable"
  }

  onContinentsChanged: Qt.callLater(function() { mapCanvas.requestPaint() })

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(12)

    Row {
      id: mapHeader
      anchors.left: parent.left
      anchors.top: parent.top
      spacing: Style.space(9)

      Text {
        text: "WORLD MAP"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        font.letterSpacing: 1
      }

      Text {
        text: "DAY / NIGHT AT SELECTED TIME"
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Item {
      id: mapArea
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: mapHeader.bottom
      anchors.topMargin: Style.space(9)
      anchors.bottom: parent.bottom
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

      Text {
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
