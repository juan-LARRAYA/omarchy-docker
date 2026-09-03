import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: "#2496ed"
  property color badgeColor: Color.urgent
  property int runningCount: 0
  property bool warning: false

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Rectangle {
    anchors.centerIn: parent
    width: root.iconSize + Style.space(5)
    height: root.iconSize + Style.space(3)
    radius: Style.space(4)
    color: Qt.rgba(0.14, 0.59, 0.93, 0.18)
    border.color: "#2496ed"
    border.width: 1
  }

  Image {
    id: dockerImage
    anchors.centerIn: parent
    width: root.iconSize
    height: root.iconSize
    source: "file:///usr/share/icons/hicolor/48x48/apps/docker.png"
    sourceSize.width: Math.max(48, root.iconSize * 3)
    sourceSize.height: Math.max(48, root.iconSize * 3)
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  Text {
    anchors.centerIn: parent
    visible: dockerImage.status !== Image.Ready
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
