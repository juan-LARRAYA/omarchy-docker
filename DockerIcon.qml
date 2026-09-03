import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property int runningCount: 0
  property bool warning: false

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Text {
    anchors.centerIn: parent
    text: "󰡨"
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.iconSize
  }

  Rectangle {
    visible: root.warning
    width: Math.max(4, root.iconSize * 0.28)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.top: parent.top
  }
}
