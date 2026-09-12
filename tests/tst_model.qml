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
      { state: "restarting" },
      { state: "removing" }
    ])
    compare(summary.total, 6)
    compare(summary.running, 1)
    compare(summary.stopped, 2)
    compare(summary.other, 3)
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
    verify(!Model.actionAllowed("restart", "restarting"))
    verify(!Model.actionAllowed("start", "paused"))
    verify(!Model.actionAllowed("start", "removing"))
    verify(!Model.actionAllowed("start", "dead"))
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

  function test_publishedServiceUrls() {
    var ports = [
      "8000/tcp",
      "0.0.0.0:8080->80/tcp",
      "[::]:8080->80/tcp",
      "127.0.0.1:9443->9443/tcp",
      "127.0.0.1:5353->5353/udp"
    ].join(", ")
    var published = Model.publishedTcpPorts(ports)
    compare(published.length, 3)
    compare(published.filter(function(port) { return port.hostPort === 8080 }).length, 2)
    compare(published.filter(function(port) { return port.hostPort === 9443 }).length, 1)
    compare(Model.serviceUrls(ports, "localhost"), ["http://localhost:8080", "https://127.0.0.1:9443"])
  }

  function test_ignoresInvalidAndUnpublishedPorts() {
    compare(Model.serviceUrls("8123/tcp, nonsense, 0.0.0.0:70000->80/tcp", "localhost"), [])
    compare(Model.serviceUrls("bad/path:8080->80/tcp", "localhost"), [])
    compare(Model.serviceUrls("999.1.1.1:8080->80/tcp", "localhost"), [])
    compare(Model.serviceUrls("0.0.0.0:8080->80/tcp", "bad/path"), [])
    compare(Model.serviceUrls("[::::]:8080->80/tcp", "localhost"), [])
    compare(Model.serviceUrls("[1:2:3:4:5:6:7:8:9]:8080->80/tcp", "localhost"), [])
  }

  function test_preservesSpecificHostsAndRequiresWildcardFallback() {
    var ports = [
      "192.168.1.20:8080->80/tcp",
      "[2001:db8::20]:8443->8443/tcp",
      "0.0.0.0:9000->9000/tcp",
      "[::]:9000->9000/tcp"
    ].join(", ")
    compare(Model.serviceUrls(ports, ""), [
      "http://192.168.1.20:8080",
      "https://[2001:db8::20]:8443"
    ])
    compare(Model.serviceUrls(ports, "docker.example"), [
      "http://192.168.1.20:8080",
      "https://[2001:db8::20]:8443",
      "http://docker.example:9000"
    ])
  }
}
