import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool installationChecked: false
  property bool installed: false
  property bool accessible: false
  property bool refreshing: false
  property bool acting: false
  property bool pendingRefresh: false
  property var containers: []
  property string lastError: ""
  property string lastErrorKind: ""
  property string actionStatus: ""
  property string activeActionId: ""
  property double lastUpdatedMs: 0

  readonly property string dockerContext: String(setting("dockerContext", "default") || "default")
  readonly property var containerCounts: Model.counts(containers)
  readonly property int runningCount: containerCounts.running
  readonly property int stoppedCount: containerCounts.stopped
  readonly property int otherCount: containerCounts.other

  property string _listOutput: ""
  property string _listError: ""
  property string _listContext: ""
  property int _listExitCode: -999
  property bool _listTimedOut: false
  property bool _listPreserveActionError: false
  property bool _whichTimedOut: false

  property string _actionName: ""
  property string _actionContainerName: ""
  property string _actionContext: ""
  property string _actionError: ""
  property int _actionExitCode: -999
  property bool _actionTimedOut: false

  readonly property string listingFormat: "{\"ID\":{{json .ID}},\"Names\":{{json .Names}},\"Image\":{{json .Image}},\"State\":{{json .State}},\"Status\":{{json .Status}},\"Ports\":{{json .Ports}}}"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh(preserveActionError) {
    if (acting || listProcess.running || whichProcess.running) {
      pendingRefresh = true
      return
    }
    if (!installationChecked) {
      refreshing = true
      _whichTimedOut = false
      whichWatchdog.restart()
      whichProcess.running = true
      return
    }
    if (!installed) {
      refreshing = false
      accessible = false
      lastErrorKind = "missing"
      lastError = "Docker CLI is not installed or is not on PATH."
      return
    }

    pendingRefresh = false
    refreshing = true
    _listOutput = ""
    _listError = ""
    _listContext = dockerContext
    _listExitCode = -999
    _listTimedOut = false
    _listPreserveActionError = preserveActionError === true
    listProcess.command = [
      "docker", "--context", _listContext, "ps", "-a", "--no-trunc",
      "--format", listingFormat
    ]
    listProcess.running = true
    listWatchdog.restart()
  }

  function finishListing() {
    if (_listExitCode === -999) return
    listWatchdog.stop()
    refreshing = false

    var contextChanged = dockerContext !== _listContext
    if (contextChanged) {
      // The result belongs to a context that is no longer selected. Do not
      // flash its status or error under the new context while the rerun starts.
    } else if (_listTimedOut) {
      accessible = false
      lastErrorKind = "timeout"
      lastError = "Docker did not respond within 8 seconds."
    } else if (_listExitCode === 0) {
      var parsed = Model.parseListing(_listOutput)
      if (parsed.ok) {
        accessible = true
        containers = parsed.containers
        if (!_listPreserveActionError) {
          lastError = ""
          lastErrorKind = ""
        }
        lastUpdatedMs = Date.now()
      } else {
        accessible = false
        lastError = parsed.error
        lastErrorKind = "parse"
      }
    } else if (_listExitCode !== 0) {
      accessible = false
      lastErrorKind = _listError.toLowerCase().indexOf("permission denied") !== -1 ? "permission" : "connection"
      lastError = Model.friendlyError(_listError, "Cannot connect to the Docker daemon.", _listContext)
    }

    var rerun = pendingRefresh || contextChanged
    pendingRefresh = false
    if (rerun) Qt.callLater(root.refresh)
  }

  function finishListingFailedToStart() {
    if (!refreshing || _listExitCode !== -999) return
    listWatchdog.stop()
    _listError = "Docker CLI could not be started."
    _listExitCode = 127
    finishListing()
  }

  function supportsAction(action, container) {
    return container && container.id && Model.actionAllowed(action, container.state)
  }

  function actionAllowed(action, container) {
    return accessible && !acting && supportsAction(action, container)
  }

  function runAction(action, container) {
    if (!actionAllowed(action, container)) return false
    acting = true
    pendingRefresh = false
    activeActionId = container.id
    _actionName = action
    _actionContainerName = container.name
    _actionContext = dockerContext
    actionStatus = action.charAt(0).toUpperCase() + action.slice(1) + " " + container.name + "…"
    lastError = ""
    lastErrorKind = ""
    _actionError = ""
    _actionExitCode = -999
    _actionTimedOut = false
    actionProcess.command = ["docker", "--context", _actionContext, action, container.id]
    actionProcess.running = true
    actionWatchdog.restart()
    return true
  }

  function finishAction() {
    if (_actionExitCode === -999) return
    actionWatchdog.stop()
    acting = false
    activeActionId = ""

    var contextChanged = dockerContext !== _actionContext
    if (contextChanged) {
      actionStatus = ""
      lastError = ""
      lastErrorKind = ""
      pendingRefresh = false
      Qt.callLater(function() { root.refresh(false) })
      return
    }

    var actionFailed = _actionTimedOut || _actionExitCode !== 0
    if (_actionTimedOut) {
      actionStatus = ""
      lastErrorKind = "action"
      lastError = "Docker took too long while trying to " + _actionName + " " + _actionContainerName + "."
    } else if (_actionExitCode === 0) {
      var past = _actionName === "stop" ? "Stopped" : (_actionName === "start" ? "Started" : "Restarted")
      actionStatus = past + " " + _actionContainerName
      actionStatusClear.restart()
    } else {
      actionStatus = ""
      lastErrorKind = "action"
      lastError = Model.friendlyError(_actionError, "Docker action failed.", _actionContext)
    }

    pendingRefresh = false
    Qt.callLater(function() { root.refresh(actionFailed) })
  }

  function finishActionFailedToStart() {
    if (!acting || _actionExitCode !== -999) return
    actionWatchdog.stop()
    _actionError = "Docker CLI could not be started."
    _actionExitCode = 127
    finishAction()
  }

  function start(container) { return runAction("start", container) }
  function stop(container) { return runAction("stop", container) }
  function restart(container) { return runAction("restart", container) }

  Process {
    id: whichProcess
    command: ["which", "docker"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      whichWatchdog.stop()
      root.installationChecked = true
      root.installed = exitCode === 0
      root.pendingRefresh = false
      if (root._whichTimedOut) {
        root.installed = false
        root.refreshing = false
        root.accessible = false
        root.lastErrorKind = "timeout"
        root.lastError = "Docker CLI detection did not respond within 3 seconds."
      } else if (root.installed) Qt.callLater(root.refresh)
      else {
        root.refreshing = false
        root.accessible = false
        root.lastErrorKind = "missing"
        root.lastError = "Docker CLI is not installed or is not on PATH."
      }
    }
    onRunningChanged: if (!running && root.refreshing && !root.installationChecked) {
      whichWatchdog.stop()
      root.installationChecked = true
      root.installed = false
      root.refreshing = false
      root.accessible = false
      root.pendingRefresh = false
      root.lastErrorKind = "missing"
      root.lastError = "Docker CLI detection could not be started."
    }
  }

  Process {
    id: listProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._listOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._listError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root._listExitCode = exitCode
      root.finishListing()
    }
    onRunningChanged: if (!running) root.finishListingFailedToStart()
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._actionError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root._actionExitCode = exitCode
      root.finishAction()
    }
    onRunningChanged: if (!running) root.finishActionFailedToStart()
  }

  Timer {
    id: whichWatchdog
    interval: 3000
    repeat: false
    onTriggered: {
      root._whichTimedOut = true
      if (whichProcess.running) whichProcess.signal(9)
    }
  }

  Timer {
    id: listWatchdog
    interval: 8000
    repeat: false
    onTriggered: {
      root._listTimedOut = true
      if (listProcess.running) listProcess.signal(9)
    }
  }

  Timer {
    id: actionWatchdog
    interval: 45000
    repeat: false
    onTriggered: {
      root._actionTimedOut = true
      if (actionProcess.running) actionProcess.signal(9)
    }
  }

  // Keep the bar and an open panel in sync with containers changed outside
  // the widget (CLI, Portainer, other tools).
  Timer {
    id: pollTimer
    interval: 10000
    repeat: true
    running: root.installed
    onTriggered: {
      if (!root.acting && !root.refreshing) root.refresh(true)
    }
  }

  Timer {
    id: actionStatusClear
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  onDockerContextChanged: {
    if (!installationChecked && lastUpdatedMs <= 0 && !refreshing && !acting) return
    accessible = false
    lastError = ""
    lastErrorKind = ""
    refresh()
  }
}
