import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property int hour: 0
  property int minute: 0
  property int second: 0
  property color foreground: Color.foreground
  property color background: Color.popups.background
  property color accent: Color.accent
  property color secondHandColor: Color.urgent
  readonly property bool daytime: Model.isDaytime(hour)
  readonly property color dialForeground: daytime ? background : foreground

  implicitWidth: Style.space(46)
  implicitHeight: Style.space(46)

  Rectangle {
    id: face
    anchors.fill: parent
    radius: width / 2
    color: root.daytime
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.94)
      : Qt.darker(root.background, 1.28)
    border.width: Style.spacing.hairline
    border.color: root.daytime
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.94)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38)

    Repeater {
      model: 12

      Item {
        required property int index
        anchors.fill: parent
        rotation: index * 30

        Rectangle {
          anchors.top: parent.top
          anchors.topMargin: Style.space(4)
          anchors.horizontalCenter: parent.horizontalCenter
          width: index % 3 === 0 ? Style.space(2) : Style.spacing.hairline
          height: index % 3 === 0 ? Style.space(4) : Style.space(2)
          radius: width / 2
          color: root.dialForeground
          opacity: index % 3 === 0 ? 0.78 : 0.4
        }
      }
    }

    Rectangle {
      id: hourHand
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 - height
      width: Style.space(2)
      height: Style.space(11)
      radius: width / 2
      color: root.dialForeground
      transform: Rotation {
        origin.x: hourHand.width / 2
        origin.y: hourHand.height
        angle: Model.analogHourAngle(root.hour, root.minute)
      }
    }

    Rectangle {
      id: minuteHand
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 - height
      width: Style.spacing.hairline
      height: Style.space(16)
      color: root.dialForeground
      transform: Rotation {
        origin.x: minuteHand.width / 2
        origin.y: minuteHand.height
        angle: Model.analogMinuteAngle(root.minute)
      }
    }

    Rectangle {
      id: secondHand
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 - height
      width: Style.spacing.hairline
      height: Style.space(18)
      color: root.secondHandColor
      transform: Rotation {
        origin.x: secondHand.width / 2
        origin.y: secondHand.height
        angle: Model.analogSecondAngle(root.second)
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Style.space(4)
      height: width
      radius: width / 2
      color: root.secondHandColor
    }
  }
}
