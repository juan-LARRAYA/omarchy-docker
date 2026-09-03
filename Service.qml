import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property bool accessible: false
  property bool refreshing: false
  property bool acting: false
  property var containers: []
  property string lastError: ""
  property string actionStatus: ""

  readonly property string dockerContext: String(setting("dockerContext", "default") || "default")
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 5, 3600)
  readonly property int runningCount: countState("running")
  readonly property int stoppedCount: Math.max(0, containers.length - runningCount)

  property string _listOutput: ""
  property string _listError: ""
  property int _listExitCode: -999
  property bool _listStdoutDone: false
  property bool _listStderrDone: false
  property string _actionError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function countState(state) {
    var count = 0
    for (var i = 0; i < containers.length; i++)
      if (String(containers[i].state || "").toLowerCase() === state) count++
    return count
  }

  function refresh() {
    if (!installed) {
      if (!whichProcess.running) whichProcess.running = true
      return
    }
    if (listProcess.running) return
    refreshing = true
    _listOutput = ""
    _listError = ""
    _listExitCode = -999
    _listStdoutDone = false
    _listStderrDone = false
    listProcess.command = [
      "docker", "--context", dockerContext, "ps", "-a", "--no-trunc",
      "--format", "{{json .}}"
    ]
    listProcess.running = true
  }

  function finishListing() {
    if (_listExitCode === -999 || !_listStdoutDone || !_listStderrDone) return
    refreshing = false
    accessible = _listExitCode === 0
    if (_listExitCode === 0) {
      lastError = ""
      parseListing(_listOutput)
    } else {
      containers = []
      lastError = _listError || "Cannot connect to the Docker daemon."
    }
  }

  function parseListing(output) {
    var result = []
    var lines = String(output || "").trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      try {
        var raw = JSON.parse(line)
        result.push({
          id: String(raw.ID || ""),
          name: String(raw.Names || raw.Name || raw.ID || "Unknown"),
          image: String(raw.Image || ""),
          state: String(raw.State || "unknown").toLowerCase(),
          status: String(raw.Status || ""),
          ports: String(raw.Ports || "")
        })
      } catch (e) {
        lastError = "Docker returned an unreadable container listing."
      }
    }
    result.sort(function(a, b) {
      if (a.state === "running" && b.state !== "running") return -1
      if (a.state !== "running" && b.state === "running") return 1
      return a.name.localeCompare(b.name)
    })
    containers = result
  }

  function runAction(action, container) {
    if (acting || !container || !container.id) return
    acting = true
    actionStatus = action.charAt(0).toUpperCase() + action.slice(1) + " " + container.name + "…"
    lastError = ""
    _actionError = ""
    actionProcess.command = ["docker", "--context", dockerContext, action, container.id]
    actionProcess.running = true
  }

  function start(container) { runAction("start", container) }
  function stop(container) { runAction("stop", container) }
  function restart(container) { runAction("restart", container) }

  Process {
    id: whichProcess
    command: ["which", "docker"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else {
        root.accessible = false
        root.lastError = "Docker CLI is not installed or is not on PATH."
      }
    }
  }

  Process {
    id: listProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._listOutput = text
        root._listStdoutDone = true
        root.finishListing()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._listError = String(text || "").trim()
        root._listStderrDone = true
        root.finishListing()
      }
    }
    onExited: function(exitCode) {
      root._listExitCode = exitCode
      root.finishListing()
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._actionError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.acting = false
      root.actionStatus = ""
      if (exitCode !== 0) root.lastError = root._actionError || "Docker action failed."
      actionRefresh.restart()
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: actionRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  onDockerContextChanged: refresh()
}
