function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function safeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function safeArray(value) {
  return Array.isArray(value) ? value : []
}

function emptyState() {
  return {
    engine: "postgresql",
    connected: false,
    stale: false,
    sequence: 0,
    collectedAtMs: 0,
    identity: {},
    capabilities: {},
    connections: {
      used: 0,
      max: 0,
      active: 0,
      idle: 0,
      idleInTransaction: 0,
      waiting: 0,
      lockWaiting: 0,
      blocked: 0,
      oldestLockWaitSeconds: 0,
      oldestXactSeconds: 0,
      oldestIdleXactSeconds: 0,
      oldestQuerySeconds: 0
    },
    counters: {},
    mvcc: {
      liveTuples: 0,
      deadTuples: 0,
      relationsWithDeadTuples: 0,
      autovacuumCount: 0,
      vacuumCount: 0,
      autovacuumWorkers: 0,
      vacuumWorkers: 0,
      lastAutovacuum: null,
      lastVacuum: null
    },
    maintenance: {
      kind: "vacuum",
      backlogLabel: "DEAD TUPLES",
      surfaceLabel: "MVCC SURFACE",
      backlog: 0,
      workerCount: 0,
      autoWorkerCount: 0,
      dirtyPages: 0,
      totalPages: 0,
      bufferWaitFree: 0,
      lastMaintenance: null
    },
    replication: {},
    rates: { work: 0, logBytes: 0, transactions: 0, walBytes: 0, rowsModified: 0, rowsReturned: 0 },
    cacheHitPercent: 0,
    connectionPercent: 0,
    deadTuplePercent: 0,
    peakTransactions: 0,
    pressures: { workload: 0, contention: 0, connections: 0, maintenance: 0, mvcc: 0 },
    histories: {
      work: [],
      logBytes: [],
      maintenanceBacklog: [],
      transactions: [],
      walBytes: [],
      active: [],
      waiting: [],
      lockWaiting: [],
      blocked: [],
      connectionsUsed: [],
      deadTuples: [],
      autovacuumCount: [],
      vacuumWorkers: []
    },
    activity: [],
    relations: [],
    blocking: [],
    vacuum: [],
    severity: "normal",
    statusLabel: "Connecting"
  }
}

function counterDelta(current, previous) {
  var next = finiteNumber(current, -1)
  var old = finiteNumber(previous, -1)
  if (next < 0 || old < 0 || next < old) return null
  return next - old
}

function resetMatches(current, previous, key) {
  var next = String(safeObject(current)[key] || "")
  var old = String(safeObject(previous)[key] || "")
  return next === old
}

function rate(current, previous, keys, elapsedSeconds, resetKey) {
  if (!previous || elapsedSeconds <= 0 || elapsedSeconds > 300) return 0
  if (resetKey && !resetMatches(current, previous, resetKey)) return 0
  var delta = 0
  for (var i = 0; i < keys.length; i++) {
    var part = counterDelta(current[keys[i]], previous[keys[i]])
    if (part === null) return 0
    delta += part
  }
  return delta / elapsedSeconds
}

function appendHistory(history, timestamp, value, policy) {
  var source = safeArray(history)
  if (!policy || typeof policy !== "object") {
    var limit = Math.max(1, Math.floor(finiteNumber(policy, 120)))
    var sampleNext = source.slice(Math.max(0, source.length - Math.max(0, limit - 1)))
    sampleNext.push({ time: timestamp, value: finiteNumber(value, 0) })
    return sampleNext
  }

  var windowMs = clamp(finiteNumber(policy.windowMs, 6 * 60 * 60 * 1000), 60 * 1000, 24 * 60 * 60 * 1000)
  var bucketMs = clamp(finiteNumber(policy.bucketMs, 5000), 1000, 60 * 1000)
  var maxPoints = clamp(Math.floor(finiteNumber(policy.maxPoints, Math.ceil(windowMs / bucketMs) + 2)), 30, 20000)
  var cutoff = timestamp - windowMs
  var start = 0
  while (start < source.length && finiteNumber(source[start].time, 0) < cutoff) start++
  var next = source.slice(start)
  var point = { time: timestamp, value: finiteNumber(value, 0) }
  var bucket = Math.floor(timestamp / bucketMs)
  if (next.length > 0 && Math.floor(finiteNumber(next[next.length - 1].time, 0) / bucketMs) === bucket)
    next[next.length - 1] = point
  else
    next.push(point)

  if (next.length > maxPoints) next = next.slice(next.length - maxPoints)
  return next
}

function percentile(sortedValues, probability) {
  var values = safeArray(sortedValues)
  if (values.length === 0) return 0
  if (values.length === 1) return finiteNumber(values[0], 0)
  var position = clamp(finiteNumber(probability, 0), 0, 1) * (values.length - 1)
  var lower = Math.floor(position)
  var upper = Math.ceil(position)
  var weight = position - lower
  return finiteNumber(values[lower], 0) * (1 - weight) + finiteNumber(values[upper], 0) * weight
}

function historyStats(history) {
  var points = safeArray(history)
  var values = []
  for (var i = 0; i < points.length; i++) values.push(finiteNumber(points[i] && points[i].value, 0))
  values.sort(function(a, b) { return a - b })
  return {
    count: values.length,
    p25: percentile(values, 0.25),
    p50: percentile(values, 0.50),
    p90: percentile(values, 0.90),
    low: values.length > 0 ? values[0] : 0,
    high: values.length > 0 ? values[values.length - 1] : 0,
    firstAt: points.length > 0 ? finiteNumber(points[0].time, 0) : 0,
    lastAt: points.length > 0 ? finiteNumber(points[points.length - 1].time, 0) : 0
  }
}

function historyDelta(history, windowMs) {
  var points = safeArray(history)
  if (points.length < 2) return 0
  var latest = points[points.length - 1]
  var cutoff = finiteNumber(latest.time, 0) - Math.max(0, finiteNumber(windowMs, 0))
  var first = points[0]
  for (var i = points.length - 2; i >= 0; i--) {
    if (finiteNumber(points[i].time, 0) < cutoff) break
    first = points[i]
  }
  return finiteNumber(latest.value, 0) - finiteNumber(first.value, 0)
}

function historyRate(history, windowMs, perSeconds) {
  var points = safeArray(history)
  if (points.length < 2) return 0
  var latest = points[points.length - 1]
  var cutoff = finiteNumber(latest.time, 0) - Math.max(0, finiteNumber(windowMs, 0))
  var first = points[0]
  for (var i = points.length - 2; i >= 0; i--) {
    if (finiteNumber(points[i].time, 0) < cutoff) break
    first = points[i]
  }
  var elapsedSeconds = (finiteNumber(latest.time, 0) - finiteNumber(first.time, 0)) / 1000
  if (elapsedSeconds <= 0) return 0
  return (finiteNumber(latest.value, 0) - finiteNumber(first.value, 0)) / elapsedSeconds * Math.max(1, finiteNumber(perSeconds, 1))
}

function historyLastDrop(history) {
  var points = safeArray(history)
  for (var i = points.length - 1; i > 0; i--) {
    var current = finiteNumber(points[i] && points[i].value, 0)
    var previous = finiteNumber(points[i - 1] && points[i - 1].value, 0)
    if (current < previous)
      return { amount: previous - current, at: finiteNumber(points[i] && points[i].time, 0) }
  }
  return { amount: 0, at: 0 }
}

function percentage(numerator, denominator) {
  var top = finiteNumber(numerator, 0)
  var bottom = finiteNumber(denominator, 0)
  return bottom > 0 ? clamp(100 * top / bottom, 0, 100) : 0
}

function deriveSeverity(connections, connectionPercent, deadTuplePercent) {
  if (connections.blocked > 0 || connectionPercent >= 95 || connections.oldestIdleXactSeconds >= 900)
    return { severity: "critical", label: connections.blocked > 0 ? "Blocked" : (connectionPercent >= 95 ? "Connection limit" : "Stale transaction") }
  if (connections.waiting > 0 || connectionPercent >= 80 || connections.oldestIdleXactSeconds >= 120 || deadTuplePercent >= 25)
    return { severity: "warning", label: connections.waiting > 0 ? "Waiting" : (connectionPercent >= 80 ? "Connection pressure" : (connections.oldestIdleXactSeconds >= 120 ? "Open transaction" : "MVCC pressure")) }
  if (connections.active > 0) return { severity: "normal", label: "Active" }
  return { severity: "normal", label: "Quiet" }
}

function ingestSummary(previousState, payload, historyPolicy) {
  var previous = previousState && previousState.sequence > 0 ? previousState : emptyState()
  var nextPayload = safeObject(payload)
  var next = emptyState()
  var timestamp = finiteNumber(nextPayload.collectedAtMs, Date.now())
  var connections = safeObject(nextPayload.connections)
  var counters = safeObject(nextPayload.counters)
  var mvcc = safeObject(nextPayload.mvcc)
  var maintenancePayload = safeObject(nextPayload.maintenance)
  var elapsedSeconds = previous.collectedAtMs > 0 ? (timestamp - previous.collectedAtMs) / 1000 : 0
  var policy = historyPolicy && typeof historyPolicy === "object"
    ? historyPolicy
    : clamp(Math.floor(finiteNumber(historyPolicy, 120)), 30, 600)

  next.connected = true
  next.engine = String(nextPayload.engine || previous.engine || "postgresql")
  next.sequence = previous.sequence + 1
  next.collectedAtMs = timestamp
  next.identity = safeObject(nextPayload.identity)
  next.capabilities = safeObject(nextPayload.capabilities)
  next.connections = Object.assign(next.connections, connections)
  next.counters = counters
  next.mvcc = Object.assign(next.mvcc, mvcc)
  if (next.engine === "mysql") {
    next.maintenance = Object.assign(next.maintenance, {
      kind: "purge",
      backlogLabel: "PURGE DEBT",
      surfaceLabel: "INNODB SURFACE"
    }, maintenancePayload)
  } else {
    next.maintenance = Object.assign(next.maintenance, {
      kind: "vacuum",
      backlogLabel: "DEAD TUPLES",
      surfaceLabel: "MVCC SURFACE",
      backlog: finiteNumber(next.mvcc.deadTuples, 0),
      workerCount: finiteNumber(next.mvcc.vacuumWorkers, 0),
      autoWorkerCount: finiteNumber(next.mvcc.autovacuumWorkers, 0),
      lastMaintenance: next.mvcc.lastAutovacuum || next.mvcc.lastVacuum || null
    }, maintenancePayload)
  }
  next.replication = safeObject(nextPayload.replication)
  next.activity = safeArray(previous.activity)
  next.relations = safeArray(previous.relations)
  next.blocking = safeArray(previous.blocking)
  next.vacuum = safeArray(previous.vacuum)

  var mysql = next.engine === "mysql"
  next.rates.work = mysql
    ? rate(counters, previous.counters, ["workTotal"], elapsedSeconds, "statsReset")
    : rate(counters, previous.counters, ["xactCommit", "xactRollback"], elapsedSeconds, "databaseStatsReset")
  if (elapsedSeconds > 0)
    next.rates.work = Math.max(0, next.rates.work - Math.max(0, finiteNumber(nextPayload.collectorTransactions, 0)) / elapsedSeconds)
  next.rates.transactions = next.rates.work
  next.rates.rowsModified = mysql
    ? rate(counters, previous.counters, ["rowsModified"], elapsedSeconds, "statsReset")
    : rate(counters, previous.counters, ["tuplesInserted", "tuplesUpdated", "tuplesDeleted"], elapsedSeconds, "databaseStatsReset")
  next.rates.rowsReturned = mysql
    ? rate(counters, previous.counters, ["rowsReturned"], elapsedSeconds, "statsReset")
    : rate(counters, previous.counters, ["tuplesReturned"], elapsedSeconds, "databaseStatsReset")
  next.rates.logBytes = mysql
    ? rate(counters, previous.counters, ["logBytes"], elapsedSeconds, "logStatsReset")
    : rate(counters, previous.counters, ["walBytes"], elapsedSeconds, "walStatsReset")
  next.rates.walBytes = next.rates.logBytes

  next.cacheHitPercent = percentage(counters.blocksHit, finiteNumber(counters.blocksHit, 0) + finiteNumber(counters.blocksRead, 0))
  next.connectionPercent = percentage(next.connections.used, next.connections.max)
  next.deadTuplePercent = percentage(next.mvcc.deadTuples, finiteNumber(next.mvcc.liveTuples, 0) + finiteNumber(next.mvcc.deadTuples, 0))
  next.peakTransactions = Math.max(finiteNumber(previous.peakTransactions, 0), next.rates.work)

  var waitingShare = next.connections.active > 0
    ? next.connections.waiting / next.connections.active
    : (next.connections.waiting > 0 ? 1 : 0)
  next.pressures.workload = next.peakTransactions > 0 ? clamp(next.rates.work / next.peakTransactions, 0, 1) : 0
  next.pressures.contention = clamp(Math.max(waitingShare, next.connections.blocked * 0.5), 0, 1)
  next.pressures.connections = next.connectionPercent / 100
  next.pressures.mvcc = next.deadTuplePercent / 100
  next.pressures.maintenance = next.engine === "mysql" ? 0 : next.pressures.mvcc

  var previousWork = previous.histories.work || previous.histories.transactions
  var previousLog = previous.histories.logBytes || previous.histories.walBytes
  var previousBacklog = previous.histories.maintenanceBacklog || previous.histories.deadTuples
  next.histories.work = appendHistory(previousWork, timestamp, next.rates.work, policy)
  next.histories.logBytes = appendHistory(previousLog, timestamp, next.rates.logBytes, policy)
  next.histories.maintenanceBacklog = appendHistory(previousBacklog, timestamp, next.maintenance.backlog, policy)
  next.histories.transactions = next.histories.work
  next.histories.walBytes = next.histories.logBytes
  next.histories.active = appendHistory(previous.histories.active, timestamp, next.connections.active, policy)
  next.histories.waiting = appendHistory(previous.histories.waiting, timestamp, next.connections.waiting, policy)
  next.histories.lockWaiting = appendHistory(previous.histories.lockWaiting, timestamp, next.connections.lockWaiting, policy)
  next.histories.blocked = appendHistory(previous.histories.blocked, timestamp, next.connections.blocked, policy)
  next.histories.connectionsUsed = appendHistory(previous.histories.connectionsUsed, timestamp, next.connections.used, policy)
  next.histories.deadTuples = next.histories.maintenanceBacklog
  next.histories.autovacuumCount = appendHistory(previous.histories.autovacuumCount, timestamp, next.mvcc.autovacuumCount, policy)
  next.histories.vacuumWorkers = appendHistory(previous.histories.vacuumWorkers, timestamp, next.mvcc.vacuumWorkers, policy)

  var status = deriveSeverity(next.connections, next.connectionPercent, next.deadTuplePercent)
  next.severity = status.severity
  next.statusLabel = status.label
  return next
}

function ingestDetails(state, payload) {
  var previous = state || emptyState()
  var next = {}
  for (var key in previous) next[key] = previous[key]
  var source = safeObject(payload)
  next.activity = safeArray(source.activity)
  next.relations = safeArray(source.relations)
  next.blocking = safeArray(source.blocking)
  next.vacuum = safeArray(source.vacuum)
  return next
}

function markDisconnected(state) {
  var previous = state || emptyState()
  var next = {}
  for (var key in previous) next[key] = previous[key]
  next.connected = false
  next.stale = previous.sequence > 0
  next.severity = "critical"
  next.statusLabel = previous.sequence > 0 ? "Disconnected" : "Unavailable"
  return next
}

function formatRate(value, suffix) {
  var number = finiteNumber(value, 0)
  if (number >= 1000000) return (number / 1000000).toFixed(number >= 10000000 ? 0 : 1) + "M" + suffix
  if (number >= 1000) return (number / 1000).toFixed(number >= 10000 ? 0 : 1) + "k" + suffix
  if (number >= 100) return Math.round(number) + suffix
  if (number >= 10) return number.toFixed(1) + suffix
  return number.toFixed(number > 0 ? 1 : 0) + suffix
}

function formatBytes(value) {
  var number = Math.max(0, finiteNumber(value, 0))
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var index = 0
  while (number >= 1024 && index < units.length - 1) {
    number /= 1024
    index++
  }
  return number.toFixed(number >= 100 || index === 0 ? 0 : 1) + " " + units[index]
}

function formatDuration(seconds) {
  var value = Math.max(0, finiteNumber(seconds, 0))
  if (value < 60) return value.toFixed(value < 10 ? 1 : 0) + "s"
  if (value < 3600) return Math.floor(value / 60) + "m " + Math.floor(value % 60) + "s"
  if (value < 86400) return Math.floor(value / 3600) + "h " + Math.floor((value % 3600) / 60) + "m"
  return Math.floor(value / 86400) + "d " + Math.floor((value % 86400) / 3600) + "h"
}

function barLabel(state, mode, vertical) {
  var data = state || emptyState()
  if (!data.connected) return vertical ? "H\n—" : "HZL  —"
  var selected = String(mode || "Adaptive")
  if (selected === "Adaptive") {
    if (data.connections.blocked > 0) selected = "Waits"
    else if (data.connectionPercent >= 80) selected = "Connections"
    else if (data.connections.waiting > 0) selected = "Activity"
    else selected = "Work"
  }
  var value = ""
  var workSuffix = data.engine === "mysql" ? "q/s" : "t/s"
  if (selected === "Work" || selected === "Transactions") value = formatRate(data.rates.work, workSuffix)
  else if (selected === "Activity") value = data.connections.active + " act"
  else if (selected === "Connections") value = Math.round(data.connectionPercent) + "% conn"
  else if (selected === "Waits") value = data.connections.blocked > 0 ? data.connections.blocked + " block" : data.connections.waiting + " wait"
  else if (selected === "Log" || selected === "WAL") value = formatBytes(data.rates.logBytes) + "/s"
  else if (selected === "Maintenance" || selected === "MVCC") value = formatRate(data.maintenance.backlog, data.engine === "mysql" ? " undo" : " dead")
  else value = formatRate(data.rates.work, workSuffix)
  return vertical ? value.replace(/ .*/, "") : value
}

function fleetSummary(states) {
  var source = safeArray(states)
  var summary = {
    total: source.length,
    connected: 0,
    unavailable: 0,
    active: 0,
    waiting: 0,
    blocked: 0,
    used: 0,
    max: 0,
    work: 0,
    postgresWork: 0,
    mysqlWork: 0,
    logBytes: 0,
    maintenanceBacklog: 0,
    postgresMaintenance: 0,
    mysqlMaintenance: 0,
    postgresCount: 0,
    mysqlCount: 0,
    severity: "normal"
  }
  for (var i = 0; i < source.length; i++) {
    var state = safeObject(source[i])
    var connections = safeObject(state.connections)
    var rates = safeObject(state.rates)
    var maintenance = safeObject(state.maintenance)
    if (state.connected === true) summary.connected++
    else summary.unavailable++
    summary.active += finiteNumber(connections.active, 0)
    summary.waiting += finiteNumber(connections.waiting, 0)
    summary.blocked += finiteNumber(connections.blocked, 0)
    summary.used += finiteNumber(connections.used, 0)
    summary.max += finiteNumber(connections.max, 0)
    summary.work += finiteNumber(rates.work, rates.transactions)
    summary.logBytes += finiteNumber(rates.logBytes, rates.walBytes)
    summary.maintenanceBacklog += finiteNumber(maintenance.backlog, safeObject(state.mvcc).deadTuples)
    if (state.engine === "mysql") {
      summary.mysqlCount++
      summary.mysqlWork += finiteNumber(rates.work, rates.transactions)
      summary.mysqlMaintenance += finiteNumber(maintenance.backlog, 0)
    } else {
      summary.postgresCount++
      summary.postgresWork += finiteNumber(rates.work, rates.transactions)
      summary.postgresMaintenance += finiteNumber(maintenance.backlog, safeObject(state.mvcc).deadTuples)
    }
    if (state.severity === "critical") summary.severity = "critical"
    else if (state.severity === "warning" && summary.severity === "normal") summary.severity = "warning"
  }
  if (summary.unavailable > 0) summary.severity = "critical"
  return summary
}

function fleetBarLabel(states, mode, vertical) {
  var source = safeArray(states)
  if (source.length === 0) return vertical ? "0" : "OFF"
  if (source.length === 1) return barLabel(source[0], mode, vertical)

  var fleet = fleetSummary(source)
  var prefix = vertical ? "" : fleet.connected + "/" + fleet.total + " · "
  if (mode === "Work" || mode === "Transactions") {
    if (fleet.postgresCount > 0 && fleet.mysqlCount > 0)
      return prefix + "PG " + formatRate(fleet.postgresWork, "t/s") + " · MY " + formatRate(fleet.mysqlWork, "q/s")
    return prefix + (fleet.mysqlCount > 0
      ? formatRate(fleet.mysqlWork, "q/s")
      : formatRate(fleet.postgresWork, "t/s"))
  }
  if (mode === "Activity") return prefix + fleet.active + " active"
  if (mode === "Connections") return prefix + fleet.used + "/" + fleet.max
  if (mode === "Waits") return prefix + fleet.waiting + " wait"
  if (mode === "Log" || mode === "WAL") return prefix + formatBytes(fleet.logBytes) + "/s"
  if (mode === "Maintenance" || mode === "MVCC") {
    if (fleet.postgresCount > 0 && fleet.mysqlCount > 0)
      return prefix + "PG " + formatRate(fleet.postgresMaintenance, " dead") + " · MY " + formatRate(fleet.mysqlMaintenance, " undo")
    return prefix + (fleet.mysqlCount > 0
      ? formatRate(fleet.mysqlMaintenance, " undo")
      : formatRate(fleet.postgresMaintenance, " dead"))
  }
  if (fleet.blocked > 0) return prefix + fleet.blocked + " block"
  if (fleet.waiting > 0) return prefix + fleet.waiting + " wait"
  if (fleet.unavailable > 0) return prefix + fleet.unavailable + " down"
  return prefix + fleet.active + " active"
}

function escapeMarkup(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    clamp: clamp,
    emptyState: emptyState,
    ingestSummary: ingestSummary,
    ingestDetails: ingestDetails,
    historyStats: historyStats,
    historyDelta: historyDelta,
    historyRate: historyRate,
    historyLastDrop: historyLastDrop,
    markDisconnected: markDisconnected,
    formatRate: formatRate,
    formatBytes: formatBytes,
    formatDuration: formatDuration,
    barLabel: barLabel,
    fleetSummary: fleetSummary,
    fleetBarLabel: fleetBarLabel,
    escapeMarkup: escapeMarkup
  }
}
