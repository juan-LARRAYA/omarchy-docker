.pragma library

var uiChoices = ["Portainer", "Dockge", "Custom", "None"]

function normalizeUi(value) {
  var selected = String(value || "Portainer")
  return uiChoices.indexOf(selected) === -1 ? "Portainer" : selected
}

function nextUi(value) {
  var selected = normalizeUi(value)
  return uiChoices[(uiChoices.indexOf(selected) + 1) % uiChoices.length]
}

function uiUrl(value, settings) {
  var selected = normalizeUi(value)
  var config = settings || {}
  if (selected === "Portainer") return String(config.portainerUrl || "https://localhost:9443")
  if (selected === "Dockge") return String(config.dockgeUrl || "http://localhost:5001")
  if (selected === "Custom") return String(config.customUiUrl || "")
  return ""
}

function normalizeContainer(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = String(raw.ID || "").trim()
  if (id === "") return null
  return {
    id: id,
    name: String(raw.Names || raw.Name || id),
    image: String(raw.Image || ""),
    state: String(raw.State || "unknown").toLowerCase(),
    status: String(raw.Status || ""),
    ports: String(raw.Ports || "")
  }
}

function stateRank(state) {
  var value = String(state || "").toLowerCase()
  if (value === "running") return 0
  if (value === "restarting") return 1
  if (value === "paused") return 2
  if (value === "created") return 3
  if (value === "exited") return 4
  if (value === "dead") return 5
  if (value === "removing") return 6
  return 7
}

function compareContainers(left, right) {
  var stateDifference = stateRank(left.state) - stateRank(right.state)
  if (stateDifference !== 0) return stateDifference
  return String(left.name).localeCompare(String(right.name))
}

function parseListing(output) {
  var result = []
  var value = String(output || "").trim()
  if (value === "") return { ok: true, containers: result, error: "" }

  var lines = value.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    try {
      var container = normalizeContainer(JSON.parse(line))
      if (!container)
        return { ok: false, containers: [], error: "Docker returned a container without an ID." }
      result.push(container)
    } catch (e) {
      return { ok: false, containers: [], error: "Docker returned an unreadable container listing." }
    }
  }

  result.sort(compareContainers)
  return { ok: true, containers: result, error: "" }
}

function counts(containers) {
  var result = { running: 0, stopped: 0, other: 0, total: 0 }
  var list = containers || []
  result.total = list.length
  for (var i = 0; i < list.length; i++) {
    var state = String(list[i].state || "").toLowerCase()
    if (state === "running") result.running++
    else if (state === "exited" || state === "dead") result.stopped++
    else result.other++
  }
  return result
}

function actionAllowed(action, state) {
  var command = String(action || "")
  var value = String(state || "").toLowerCase()
  if (command === "start") return value === "created" || value === "exited"
  if (command === "stop") return value === "running" || value === "restarting"
  if (command === "restart") return value === "running"
  return false
}

function publishedTcpPorts(value) {
  var result = []
  var seen = {}
  var parts = String(value || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var entry = parts[i].trim()
    if (!/\/tcp$/i.test(entry) || entry.indexOf("->") === -1) continue
    var sides = entry.split("->")
    if (sides.length !== 2) continue
    var hostMatch = sides[0].trim().match(/^(.*):(\d+)$/)
    var containerMatch = sides[1].trim().match(/^(\d+)\/tcp$/i)
    if (!hostMatch || !containerMatch) continue
    var host = hostMatch[1].trim()
    if (host[0] === "[" && host[host.length - 1] === "]") host = host.substring(1, host.length - 1)
    var hostPort = Number(hostMatch[2])
    var containerPort = Number(containerMatch[1])
    if (hostPort < 1 || hostPort > 65535 || containerPort < 1 || containerPort > 65535) continue
    var key = host + ":" + hostPort
    if (seen[key]) continue
    seen[key] = true
    result.push({ host: host, hostPort: hostPort, containerPort: containerPort })
  }
  result.sort(function(left, right) {
    var portDifference = left.hostPort - right.hostPort
    return portDifference !== 0 ? portDifference : left.host.localeCompare(right.host)
  })
  return result
}

function normalizedUrlHost(value) {
  var host = String(value || "").trim()
  if (host === "") return ""
  if (host[0] === "[" && host[host.length - 1] === "]") host = host.substring(1, host.length - 1)
  if (host === "localhost") return host
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) {
    var octets = host.split(".")
    for (var i = 0; i < octets.length; i++) if (Number(octets[i]) > 255) return ""
    return host
  }
  if (/^[0-9a-f:]+$/i.test(host) && host.indexOf(":") !== -1) return "[" + host + "]"
  if (/^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(host))
    return host
  return ""
}

function serviceUrls(value, wildcardHost) {
  var securePorts = { 443: true, 8443: true, 9443: true }
  var fallback = String(wildcardHost || "").trim()
  var result = []
  var seen = {}
  publishedTcpPorts(value).forEach(function(port) {
    var host = port.host
    if (host === "0.0.0.0" || host === "::" || host === "") host = fallback
    if (host === "") return
    var urlHost = normalizedUrlHost(host)
    if (urlHost === "") return
    var scheme = securePorts[port.containerPort] ? "https" : "http"
    var url = scheme + "://" + urlHost + ":" + port.hostPort
    if (!seen[url]) {
      seen[url] = true
      result.push(url)
    }
  })
  return result
}

function friendlyError(stderrText, fallback, context) {
  var raw = String(stderrText || "").replace(/\s+/g, " ").trim()
  var lower = raw.toLowerCase()
  var suffix = context ? " in Docker context “" + String(context) + "”." : "."
  if (lower.indexOf("permission denied") !== -1)
    return "Permission denied while connecting to Docker" + suffix
  if (lower.indexOf("cannot connect to the docker daemon") !== -1
      || lower.indexOf("is the docker daemon running") !== -1)
    return "Cannot connect to the Docker daemon" + suffix
  if (lower.indexOf("context") !== -1 && lower.indexOf("not found") !== -1)
    return "Docker context “" + String(context || "") + "” was not found."
  if (raw !== "") return raw.length > 240 ? raw.substring(0, 237) + "…" : raw
  return String(fallback || "Docker command failed.")
}
