import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "juan.docker"
  ipcTarget: "juan.docker"
  manageIpc: false

  implicitWidth: Style.space(76)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  property int containerIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string selectedUi: Model.normalizeUi(settings.containerUi)
  readonly property string uiUrl: Model.uiUrl(selectedUi, settings)
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

  function heroMeta() {
    if (service.refreshing && service.containers.length === 0) return "Loading containers…"
    if (!service.accessible && service.containers.length > 0) return "Last known container state"
    if (!service.accessible) return "Container engine unavailable"
    var parts = [service.runningCount + " running", service.stoppedCount + " stopped"]
    if (service.otherCount > 0) parts.push(service.otherCount + " other")
    return parts.join(" · ")
  }

  function persistSetting(name, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return false
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry[name] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
    return true
  }

  function cycleUi() {
    persistSetting("containerUi", Model.nextUi(selectedUi))
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
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
    function status(): string {
      if (!service.installationChecked) return "Not refreshed"
      if (!service.installed) return "Docker CLI unavailable"
      if (service.refreshing) return "Refreshing"
      if (!service.accessible) return "Docker unavailable"
      return service.runningCount + " running · " + service.containers.length + " total"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰡨  Docker"
    foreground: "#2496ed"
    fontSize: Style.font.caption
    horizontalMargin: 7
    tooltipText: "Docker containers"
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
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

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
            meta: root.heroMeta()
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
            visible: service.installed && !service.accessible && service.lastErrorKind === "permission"
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
            foreground: root.foreground
          }

          CursorSurface {
            width: parent.width
            implicitHeight: Style.space(44)
            foreground: root.foreground
            fill: root.hoverFill
            radius: Style.cornerRadius

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                text: "󰒓"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                Layout.fillWidth: true
                text: "Container UI"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: root.selectedUi
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                text: "󰒭"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.cycleUi()
            }
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
    readonly property bool actionBusy: container && service.acting && service.activeActionId === container.id
    readonly property bool canStart: service.supportsAction("start", container)
    readonly property bool canStop: service.supportsAction("stop", container)
    readonly property bool canRestart: service.supportsAction("restart", container)

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
        color: row.running ? Color.accent : (row.container && row.container.state === "dead" ? root.urgent : root.dim)
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
        visible: row.canStart || row.canStop || row.actionBusy
        iconText: row.actionBusy ? "󰑓" : (row.canStop ? "󰓛" : "󰐊")
        tooltipText: row.canStop ? "Stop" : "Start"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: service.accessible && !service.acting && (row.canStart || row.canStop)
        onClicked: {
          root.containerIndex = row.rowIndex
          if (row.canStop) service.stop(row.container)
          else if (row.canStart) service.start(row.container)
        }
      }

      PanelActionButton {
        visible: row.canRestart && !row.actionBusy
        iconText: "󰜉"
        tooltipText: "Restart"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: service.accessible && !service.acting && row.canRestart
        onClicked: {
          root.containerIndex = row.rowIndex
          service.restart(row.container)
        }
      }
    }
  }
}
