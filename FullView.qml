import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "Model.js" as Model

// Resizable workspace for the timeline and map. The shell injects the same
// service instance used by the compact bar panel, so both surfaces always
// point at the same locations and canonical planning instant.
Item {
  id: root

  readonly property string moduleName: "io.github.ptgamr.world-clock"
  property var shell: null
  property var service: null
  property bool closingFromHost: false
  readonly property bool opened: window.visible

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: Style.font.family

  function renderedRow(id) {
    return root.service ? root.service.renderedRow(id) : null
  }

  function displayTime(row) {
    if (!row) return "--:--"
    return root.service && root.service.hourFormat === "24" ? row.time : row.time12
  }

  function displayPeriod(row) {
    return root.service && root.service.hourFormat === "12" && row ? row.period : ""
  }

  function durationLabel() {
    if (!root.service) return "1 hr"
    var minutes = root.service.meetingDurationMinutes
    if (minutes < 60) return minutes + " min"
    var hours = Math.floor(minutes / 60)
    var remainder = minutes % 60
    return hours + " hr" + (hours === 1 ? "" : "s")
      + (remainder ? " " + remainder + " min" : "")
  }

  function open(payloadJson) {
    root.closingFromHost = false
    window.visible = true
    if (root.service) root.service.requestRender()
    if (root.service) root.service.centerTimelineOnSelection()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.closingFromHost = true
    window.visible = false
    root.closingFromHost = false
  }

  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.moduleName)
    else window.visible = false
  }

  FloatingWindow {
    id: window
    visible: false
    title: "World Clock Planner"
    color: root.background
    implicitWidth: 1040
    implicitHeight: 720
    minimumSize: Qt.size(760, 540)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.moduleName)
    }

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.requestClose()

      QQC.ScrollView {
        id: scrollArea
        anchors.fill: parent
        contentWidth: availableWidth
        QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff

        Item {
          width: scrollArea.availableWidth
          implicitHeight: content.implicitHeight + Style.space(36)

          PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.requestClose()
          }

          Column {
            id: content
            x: Style.space(18)
            y: Style.space(18)
            width: parent.width - Style.space(36)
            spacing: Style.space(16)

            Item {
              width: parent.width
              height: Math.max(titleBlock.implicitHeight, headerActions.implicitHeight)

              Column {
                id: titleBlock
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  text: "WORLD CLOCK PLANNER"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  font.letterSpacing: 1
                }

                Text {
                  text: root.service && root.service.homeLocation
                    ? "Home · " + root.service.homeLocation.name
                    : "Loading clocks…"
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Row {
                id: headerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Button {
                  text: "Today"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: if (root.service) root.service.resetToNow()
                }

                Button {
                  text: "Close"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.requestClose()
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            QQC.ScrollView {
              width: parent.width
              height: Style.space(124)
              QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AlwaysOff
              QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AsNeeded

              Row {
                spacing: Style.space(8)

                Repeater {
                  model: root.service ? root.service.locations : []

                  BorderSurface {
                    required property var modelData
                    readonly property var rendered: root.renderedRow(modelData.id)
                    width: Style.space(224)
                    height: Style.space(110)
                    color: modelData.isHome
                      ? Style.selectedFillFor(root.foreground, root.accent)
                      : Style.normalFillFor(root.foreground, root.accent, root.urgent)
                    borderSpec: Border.controlSpec(
                      modelData.isHome ? "selected" : "normal", root.foreground, root.accent)

                    Column {
                      anchors.fill: parent
                      anchors.margins: Style.space(12)
                      spacing: Style.space(4)

                      Row {
                        spacing: Style.space(7)

                        Text {
                          text: modelData.name
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.subtitle
                          font.bold: true
                        }

                        Text {
                          visible: modelData.isHome
                          text: "HOME"
                          color: root.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }

                      Row {
                        spacing: Style.space(5)

                        Text {
                          text: root.displayTime(parent.parent.parent.rendered)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.display
                          font.bold: true
                        }

                        Text {
                          anchors.baseline: parent.children[0].baseline
                          text: root.displayPeriod(parent.parent.parent.rendered)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }

                      Text {
                        text: parent.parent.rendered
                          ? parent.parent.rendered.weekday + " · " + parent.parent.rendered.abbreviation
                          : modelData.timezone
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                }
              }
            }

            BorderSurface {
              id: meetingControls
              width: parent.width
              height: Style.space(72)
              color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  text: "MEETING TIME"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  font.letterSpacing: 1
                }

                Text {
                  text: root.service && root.service.meetingData.homeDateLabel
                    ? root.service.meetingData.homeDateLabel
                    : "Choose a start time on the timeline"
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Row {
                id: meetingActions
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(5)

                Button {
                  text: "−"
                  tooltipText: "Shorten by 15 minutes"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: if (root.service)
                    root.service.setMeetingDuration(root.service.meetingDurationMinutes - 15)
                }

                Text {
                  width: Style.space(88)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: root.durationLabel()
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Button {
                  text: "+"
                  tooltipText: "Extend by 15 minutes"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: if (root.service)
                    root.service.setMeetingDuration(root.service.meetingDurationMinutes + 15)
                }

                Item { width: Style.space(7); height: 1 }

                Text {
                  visible: root.service && root.service.copyStatus !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.service ? root.service.copyStatus : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Button {
                  text: "Copy meeting time"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: root.service && root.service.copyStatus !== ""
                  bordered: true
                  onClicked: if (root.service) root.service.copyMeetingTime()
                }
              }
            }

            TimelineView {
              id: timelineView
              width: parent.width
              service: root.service
              foreground: root.foreground
              accent: root.accent
              urgent: root.urgent
              fontFamily: root.fontFamily
            }

            BorderSurface {
              width: parent.width
              height: Style.space(230)
              color: Style.normalFillFor(root.foreground, root.accent, root.urgent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                anchors.centerIn: parent
                spacing: Style.space(7)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "WORLD MAP"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  font.letterSpacing: 1
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Local vector map and day/night overlay will use this space."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
