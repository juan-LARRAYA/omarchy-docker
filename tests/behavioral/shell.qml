import QtQuick
import Quickshell

ShellRoot {
  id: root

  property string testCase: String(Quickshell.env("DOCKER_SERVICE_TEST_CASE") || "")
  property int stage: 0
  property bool done: false
  property var service: serviceLoader.item

  function finish(passed, message) {
    if (done) return
    done = true
    if (passed) console.info("DOCKER-TEST-PASS: " + testCase)
    else console.error("DOCKER-TEST-FAIL: " + testCase + ": " + message)
    Qt.callLater(Qt.quit)
  }

  function check(condition, message) {
    if (!condition) finish(false, message)
    return condition
  }

  Loader {
    id: serviceLoader
    source: "Service.qml"
    onLoaded: {
      item.settings = { dockerContext: root.testCase === "timeout" ? "hang" :
        (root.testCase === "failed-to-start" ? "disappear" :
        (root.testCase === "action-context-switch" ? "A" : "stderr")) }
      item.refresh()
    }
  }

  Timer {
    interval: 25
    repeat: true
    running: !root.done
    onTriggered: {
      if (!root.service) return
      if (root.testCase === "collector-order" && service.installationChecked && !service.refreshing) {
        if (!root.check(!service.accessible, "failed listing remained accessible")) return
        if (!root.check(service.lastError === "fixture-specific stderr",
                        "collector output was not available at exit: " + service.lastError)) return
        root.finish(true, "")
      } else if (root.testCase === "failed-to-start") {
        if (root.stage === 0 && service.installationChecked && !service.refreshing) {
          if (!root.check(service.accessible, "fixture bootstrap listing failed")) return
          root.stage = 1
          service.refresh()
        } else if (root.stage === 1 && !service.refreshing) {
          if (!root.check(!service.accessible, "FailedToStart left service accessible")) return
          if (!root.check(service.lastError.indexOf("could not be started") !== -1,
                          "specific FailedToStart error was not published: " + service.lastError)) return
          root.finish(true, "")
        }
      } else if (root.testCase === "timeout" && service.installationChecked && !service.refreshing) {
        if (!root.check(service.lastErrorKind === "timeout", "watchdog did not classify timeout")) return
        if (!root.check(service.lastError === "Docker did not respond within 8 seconds.",
                        "unexpected timeout message: " + service.lastError)) return
        root.finish(true, "")
      } else if (root.testCase === "which-timeout" && service.installationChecked && !service.refreshing) {
        if (!root.check(!service.installed, "hung which left Docker installed")) return
        if (!root.check(service.lastErrorKind === "timeout", "hung which was not classified as timeout")) return
        if (!root.check(service.lastError === "Docker CLI detection did not respond within 3 seconds.",
                        "unexpected which timeout message: " + service.lastError)) return
        root.finish(true, "")
      } else if (root.testCase === "action-context-switch") {
        if (root.stage === 0 && service.installationChecked && !service.refreshing) {
          if (!root.check(service.accessible && service.containers.length === 1,
                          "context A bootstrap listing failed")) return
          if (!root.check(service.start(service.containers[0]), "context A start action was rejected")) return
          root.stage = 1
          service.settings = { dockerContext: "B" }
        } else if (root.stage === 1 && !service.acting && !service.refreshing
                   && service.dockerContext === "B" && service.containers.length === 1
                   && service.containers[0].id === "fresh-b") {
          if (!root.check(service.actionStatus === "", "stale context A action status survived")) return
          if (!root.check(service.lastError === "", "stale context A error survived: " + service.lastError)) return
          if (!root.check(service.lastErrorKind === "", "stale context A error kind survived")) return
          if (!root.check(service.accessible, "context B refresh did not become accessible")) return
          root.finish(true, "")
        }
      }
    }
  }

}
