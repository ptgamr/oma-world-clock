import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property var timeline: service ? service.timelineData : ({ ticks: [], rows: [], slotCount: 48 })
  readonly property int labelWidth: Style.space(126)
  readonly property int axisHeight: Style.space(38)
  readonly property int rowHeight: Style.space(42)
  readonly property int footerHeight: Style.space(32)
  readonly property real gridWidth: Math.max(1, width - labelWidth - Style.space(24))
  readonly property real durationMs: Math.max(1,
    Number(timeline.endTimestampMs || 0) - Number(timeline.startTimestampMs || 0))
  readonly property real selectionX: Math.max(0, Math.min(gridWidth,
    (Number(service ? service.planningTimestamp : 0) - Number(timeline.startTimestampMs || 0))
      / durationMs * gridWidth))

  implicitHeight: axisHeight + Math.max(1, (timeline.rows || []).length) * rowHeight
    + footerHeight + Style.space(24)
  color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

  function cellColor(cell) {
    if (!cell) return Qt.rgba(0, 0, 0, 0.18)
    if (cell.availability === "work") return Qt.rgba(0.25, 0.76, 0.43, 0.78)
    if (cell.availability === "edge") return Qt.rgba(0.86, 0.66, 0.24, 0.72)
    if (cell.isDaytime) return Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.46)
    return Qt.rgba(0.04, 0.05, 0.08, 0.78)
  }

  function selectedLabel() {
    if (!root.service || !root.service.homeLocation) return "SELECTED TIME"
    var row = root.service.renderedRow(root.service.homeLocation.id)
    if (!row) return "SELECTED TIME"
    var value = root.service.hourFormat === "24" ? row.time : row.time12 + " " + row.period
    return row.weekday + "  " + value
  }

  function chooseAt(x) {
    if (!root.service || !root.timeline.startTimestampMs) return
    var ratio = Math.max(0, Math.min(1, x / root.gridWidth))
    var raw = Number(root.timeline.startTimestampMs) + ratio * root.durationMs
    var snapped = Math.round(raw / (15 * 60000)) * 15 * 60000
    root.service.setPlanningTimestamp(snapped)
  }

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(12)

    Text {
      anchors.left: parent.left
      anchors.bottom: timelineRows.top
      anchors.bottomMargin: Style.space(8)
      text: "24 HOURS"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 1
    }

    Item {
      id: axis
      x: root.labelWidth
      y: 0
      width: root.gridWidth
      height: root.axisHeight

      Repeater {
        model: root.timeline.ticks || []

        Text {
          required property var modelData
          x: Math.max(0, Math.min(axis.width - implicitWidth,
            modelData.offsetMinutes / (24 * 60) * axis.width - implicitWidth / 2))
          anchors.bottom: parent.bottom
          text: modelData.weekday + "  " + modelData.time
          color: Qt.darker(root.foreground, 1.25)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Item {
      id: timelineRows
      x: 0
      y: root.axisHeight
      width: parent.width
      height: Math.max(1, (root.timeline.rows || []).length) * root.rowHeight

      Column {
        id: labels
        width: root.labelWidth - Style.space(8)
        spacing: 0

        Repeater {
          model: root.timeline.rows || []

          Item {
            required property var modelData
            width: labels.width
            height: root.rowHeight

            Column {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: modelData.isHome
                elide: Text.ElideRight
                width: labels.width
              }

              Text {
                readonly property var selectedRow: root.service
                  ? root.service.renderedRow(modelData.id) : null
                text: selectedRow
                  ? (root.service.hourFormat === "24"
                      ? selectedRow.time
                      : selectedRow.time12 + " " + selectedRow.period)
                  : modelData.timezone
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }

      Item {
        id: grid
        x: root.labelWidth
        width: root.gridWidth
        height: parent.height
        clip: true

        Column {
          anchors.fill: parent
          spacing: 0

          Repeater {
            model: root.timeline.rows || []

            Row {
              id: timelineRow
              required property var modelData
              width: grid.width
              height: root.rowHeight
              spacing: 0

              Repeater {
                model: timelineRow.modelData.cells || []

                Rectangle {
                  required property var modelData
                  width: grid.width / Math.max(1, root.timeline.slotCount || 48)
                  height: root.rowHeight - Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.cellColor(modelData)
                  border.width: Style.spacing.hairline
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                }
              }
            }
          }
        }

        Repeater {
          model: 5

          Rectangle {
            required property int index
            x: Math.min(grid.width - width, index / 4 * grid.width)
            width: Style.spacing.hairline
            height: grid.height
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
          }
        }

        Rectangle {
          x: root.selectionX - width / 2
          width: Style.space(2)
          height: grid.height
          color: root.accent
          z: 3
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onPressed: function(mouse) { root.chooseAt(mouse.x) }
          onPositionChanged: function(mouse) {
            if (pressed) root.chooseAt(mouse.x)
          }
        }
      }
    }

    Item {
      x: root.labelWidth
      y: timelineRows.y + timelineRows.height + Style.space(5)
      width: root.gridWidth
      height: root.footerHeight

      Rectangle {
        x: Math.max(0, Math.min(parent.width - width, root.selectionX - width / 2))
        width: selectedText.implicitWidth + Style.space(16)
        height: selectedText.implicitHeight + Style.space(8)
        color: Style.selectedFillFor(root.foreground, root.accent)
        border.width: Style.spacing.hairline
        border.color: root.accent

        Text {
          id: selectedText
          anchors.centerIn: parent
          text: root.selectedLabel()
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }

    Row {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(10)

      Repeater {
        model: [
          { label: "WORK", color: Qt.rgba(0.25, 0.76, 0.43, 0.78) },
          { label: "EDGE", color: Qt.rgba(0.86, 0.66, 0.24, 0.72) },
          { label: "OFF", color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.46) },
          { label: "NIGHT", color: Qt.rgba(0.04, 0.05, 0.08, 0.78) }
        ]

        Row {
          required property var modelData
          spacing: Style.space(4)

          Rectangle {
            width: Style.space(8)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.color
          }

          Text {
            text: modelData.label
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
