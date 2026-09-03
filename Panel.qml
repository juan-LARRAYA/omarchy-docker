import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "juan.docker"
  ipcTarget: "juan.docker"
  manageIpc: false

  property int containerIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string selectedUi: String(settings.containerUi || "Portainer")
  readonly property string uiUrl: {
    if (selectedUi === "Portainer") return String(settings.portainerUrl || "https://localhost:9443")
    if (selectedUi === "Dockge") return String(settings.dockgeUrl || "http://localhost:5001")
    if (selectedUi === "Custom") return String(settings.customUiUrl || "")
    return ""
  }
  readonly property var selectedContainer: service.containers.length > 0
    ? service.containers[Math.max(0, Math.min(containerIndex, service.containers.length - 1))]
    : null

  function clampCursor() {
    containerIndex = Math.max(0, Math.min(containerIndex, service.containers.length - 1))
  }

  function moveCursor(dx, dy) {
    if (service.containers.length === 0 || dy === 0) return
    containerIndex = (containerIndex + (dy > 0 ? 1 : -1) + service.containers.length) % service.containers.length
  }

  function toggleSelected() {
    if (!selectedContainer) return
    if (selectedContainer.state === "running") service.stop(selectedContainer)
    else service.start(selectedContainer)
  }

  function openUi() {
    if (uiUrl === "") return
    Quickshell.execDetached(["xdg-open", uiUrl])
    root.close()
  }

  function openDockerAccessSetup() {
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation",
      "omarchy-setup-security-sudoless-docker"
    ])
    root.close()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    service.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onSelectedContainerChanged: clampCursor()

  Service {
    id: service
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { service.refresh(); return "ok" }
    function status() { return service.runningCount + " running" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        DockerIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.barForeground
          badgeColor: root.urgent
          runningCount: service.runningCount
          warning: service.lastError !== ""
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) service.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.toggleSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") service.refresh()
        else if (t === "o" || t === "O") root.openUi()
        else if ((t === "s" || t === "S") && root.selectedContainer) root.toggleSelected()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Docker"
            meta: service.accessible
              ? service.runningCount + " running · " + service.stoppedCount + " stopped"
              : "Container engine unavailable"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: service.accessible ? 1.0 : 0.5
            iconComponent: Component {
              DockerIcon {
                iconSize: Style.font.display
                color: service.accessible ? root.foreground : root.dim
                badgeColor: root.urgent
                warning: service.lastError !== ""
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh containers"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !service.refreshing
                onClicked: service.refresh()
              }
            }
          }

          Text {
            visible: service.lastError !== "" || service.actionStatus !== ""
            width: parent.width
            text: service.actionStatus !== "" ? service.actionStatus : service.lastError
            color: service.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: service.installed && !service.accessible
            width: parent.width
            implicitHeight: accessContent.implicitHeight + Style.space(20)
            foreground: root.foreground
            fill: root.hoverFill
            radius: Style.cornerRadius

            RowLayout {
              id: accessContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                text: "󰌾"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              Column {
                Layout.fillWidth: true
                spacing: Style.space(1)
                Text {
                  width: parent.width
                  text: "Configure Docker access"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  text: "Opens Omarchy’s security wizard · root-equivalent permission"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
              Text {
                text: "󰁔"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openDockerAccessSetup()
            }
          }

          Text {
            visible: service.accessible && service.containers.length === 0 && !service.refreshing
            width: parent.width
            text: "No containers found in Docker context “" + service.dockerContext + "”."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: service.containers

              ContainerRow {
                required property var modelData
                required property int index
                width: parent.width
                container: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.uiUrl !== ""
            foreground: root.foreground
          }

          CursorSurface {
            visible: root.uiUrl !== ""
            width: parent.width
            implicitHeight: Style.space(48)
            foreground: root.foreground
            fill: root.hoverFill
            radius: Style.cornerRadius

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)

              Text {
                text: "󰖟"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                Layout.fillWidth: true
                text: "Open " + root.selectedUi
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: "󰁔"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openUi()
            }
          }
        }
      }
    }
  }

  component ContainerRow: CursorSurface {
    id: row
    property var container: null
    property int rowIndex: 0
    readonly property bool running: container && container.state === "running"

    hasCursor: root.cursorActive && root.containerIndex === rowIndex
    current: running
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: content.implicitHeight + Style.space(16)
    radius: Style.cornerRadius

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: root.containerIndex = row.rowIndex
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(8)
        height: width
        radius: width / 2
        color: row.running ? Color.accent : root.dim
      }

      Column {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: row.container ? row.container.name : "Unknown"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.running
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: row.container
            ? [row.container.image, row.container.status].filter(function(v) { return v !== "" }).join(" · ")
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: row.running ? "󰓛" : "󰐊"
        tooltipText: row.running ? "Stop" : "Start"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !service.acting
        onClicked: {
          root.containerIndex = row.rowIndex
          if (row.running) service.stop(row.container)
          else service.start(row.container)
        }
      }

      PanelActionButton {
        visible: row.running
        iconText: "󰜉"
        tooltipText: "Restart"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !service.acting
        onClicked: {
          root.containerIndex = row.rowIndex
          service.restart(row.container)
        }
      }
    }
  }
}
