import QtQuick 2.15
import QtTest 1.3
import "../Model.js" as Model

TestCase {
  name: "DockerModel"

  function record(id, name, state, image, status) {
    return JSON.stringify({
      ID: id,
      Names: name,
      State: state,
      Image: image || "example:latest",
      Status: status || state,
      Ports: ""
    })
  }

  function test_emptyListing() {
    var parsed = Model.parseListing("")
    verify(parsed.ok)
    compare(parsed.containers.length, 0)
  }

  function test_normalizesAndSortsContainers() {
    var output = [
      record("2", "zebra", "exited"),
      record("3", "beta", "running"),
      record("1", "alpha", "running")
    ].join("\n")
    var parsed = Model.parseListing(output)
    verify(parsed.ok)
    compare(parsed.containers.length, 3)
    compare(parsed.containers[0].name, "alpha")
    compare(parsed.containers[1].name, "beta")
    compare(parsed.containers[2].name, "zebra")
    compare(parsed.containers[0].state, "running")
  }

  function test_rejectsMalformedListingAtomically() {
    var parsed = Model.parseListing(record("1", "valid", "running") + "\nnot-json")
    verify(!parsed.ok)
    compare(parsed.containers.length, 0)
    compare(parsed.error, "Docker returned an unreadable container listing.")
  }

  function test_rejectsMissingContainerId() {
    var parsed = Model.parseListing(JSON.stringify({ Names: "missing", State: "running" }))
    verify(!parsed.ok)
    compare(parsed.error, "Docker returned a container without an ID.")
  }

  function test_countsStatesWithoutCallingEverythingStopped() {
    var summary = Model.counts([
      { state: "running" },
      { state: "exited" },
      { state: "dead" },
      { state: "paused" },
      { state: "restarting" }
    ])
    compare(summary.total, 5)
    compare(summary.running, 1)
    compare(summary.stopped, 2)
    compare(summary.other, 2)
  }

  function test_actionPolicy() {
    verify(Model.actionAllowed("start", "created"))
    verify(Model.actionAllowed("start", "exited"))
    verify(!Model.actionAllowed("start", "running"))
    verify(Model.actionAllowed("stop", "running"))
    verify(Model.actionAllowed("stop", "restarting"))
    verify(!Model.actionAllowed("stop", "paused"))
    verify(Model.actionAllowed("restart", "running"))
    verify(!Model.actionAllowed("restart", "exited"))
    verify(!Model.actionAllowed("remove", "exited"))
  }

  function test_friendlyErrors() {
    compare(
      Model.friendlyError("permission denied while trying to connect", "fallback", "default"),
      "Permission denied while connecting to Docker in Docker context “default”."
    )
    compare(
      Model.friendlyError("Cannot connect to the Docker daemon. Is the docker daemon running?", "fallback", "rootless"),
      "Cannot connect to the Docker daemon in Docker context “rootless”."
    )
    compare(
      Model.friendlyError("context missing: context not found", "fallback", "missing"),
      "Docker context “missing” was not found."
    )
  }

  function test_longErrorsAreBounded() {
    var message = Model.friendlyError("x".repeat(400), "fallback", "default")
    verify(message.length <= 240)
    verify(message.endsWith("…"))
  }

  function test_uiSelectionAndUrls() {
    compare(Model.normalizeUi("unexpected"), "Portainer")
    compare(Model.nextUi("Portainer"), "Dockge")
    compare(Model.nextUi("Dockge"), "Custom")
    compare(Model.nextUi("Custom"), "None")
    compare(Model.nextUi("None"), "Portainer")
    compare(Model.uiUrl("Portainer", {}), "https://localhost:9443")
    compare(Model.uiUrl("Dockge", { dockgeUrl: "http://dockge.test:5001" }), "http://dockge.test:5001")
    compare(Model.uiUrl("Custom", { customUiUrl: "https://containers.example" }), "https://containers.example")
    compare(Model.uiUrl("None", {}), "")
  }
}
