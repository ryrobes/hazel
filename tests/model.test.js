const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../Model.js")

function summary(at, counters, connections = {}, mvcc = {}) {
  return {
    kind: "summary",
    collectedAtMs: at,
    identity: { database: "hazel_test", version: "18.4", inRecovery: false },
    capabilities: { fullStats: true, statStatements: false },
    connections: Object.assign({
      used: 3, max: 100, active: 1, idle: 2, idleInTransaction: 0,
      waiting: 0, lockWaiting: 0, blocked: 0,
      oldestLockWaitSeconds: 0, oldestXactSeconds: 0,
      oldestIdleXactSeconds: 0, oldestQuerySeconds: 1
    }, connections),
    counters: Object.assign({
      xactCommit: 100, xactRollback: 5, tuplesReturned: 1000,
      tuplesInserted: 20, tuplesUpdated: 10, tuplesDeleted: 5,
      blocksRead: 10, blocksHit: 990, walBytes: 10000,
      databaseStatsReset: "2026-01-01T00:00:00Z",
      walStatsReset: "2026-01-01T00:00:00Z"
    }, counters),
    mvcc: Object.assign({
      liveTuples: 900, deadTuples: 100, relationsWithDeadTuples: 1,
      autovacuumCount: 2, vacuumCount: 1,
      autovacuumWorkers: 0, vacuumWorkers: 0,
      lastAutovacuum: null, lastVacuum: null
    }, mvcc),
    replication: { replicaCount: 0, maxByteLag: 0 }
  }
}

function mysqlSummary(at, counters = {}, connections = {}, maintenance = {}, engine = "mysql") {
  return {
    kind: "summary",
    engine,
    collectedAtMs: at,
    identity: { database: "hazel", version: "8.4.11", inRecovery: false },
    capabilities: { fullStats: true, performanceSchema: 1 },
    connections: Object.assign({
      used: 4, max: 151, active: 1, idle: 3, idleInTransaction: 0,
      waiting: 0, lockWaiting: 0, blocked: 0,
      oldestLockWaitSeconds: 0, oldestXactSeconds: 0,
      oldestIdleXactSeconds: 0, oldestQuerySeconds: 1
    }, connections),
    counters: Object.assign({
      workTotal: 100, rowsReturned: 1000, rowsModified: 50,
      blocksRead: 10, blocksHit: 9990, logBytes: 10000,
      statsReset: "2026-08-22T00:00:00", logStatsReset: "2026-08-22T00:00:00"
    }, counters),
    maintenance: Object.assign({
      kind: "purge", backlogLabel: "PURGE DEBT", surfaceLabel: "INNODB SURFACE",
      backlog: 7, workerCount: 1, autoWorkerCount: 1
    }, maintenance),
    replication: { replicaCount: 0, maxByteLag: 0 }
  }
}

function clickhouseSummary(at, counters = {}, connections = {}, maintenance = {}, capacity = {}) {
  return {
    kind: "summary",
    engine: "clickhouse",
    collectedAtMs: at,
    identity: { database: "hazel", user: "hazel", version: "25.8.32.4", family: "clickhouse", inRecovery: false },
    capabilities: { fullStats: true, processes: true, merges: true, mutations: true },
    connections: Object.assign({
      used: 2, max: 4096, active: 1, idle: 0, idleInTransaction: 0,
      waiting: 0, lockWaiting: 0, blocked: 0, oldestQuerySeconds: 1
    }, connections),
    counters: Object.assign({
      workTotal: 100, rowsReturned: 1000, rowsModified: 50,
      blocksRead: 10000, logBytes: 10000, failedQueries: 0,
      statsReset: "2026-08-22T00:00:00", logStatsReset: "2026-08-22T00:00:00"
    }, counters),
    maintenance: Object.assign({
      kind: "merge", backlogLabel: "MERGE DEBT", surfaceLabel: "PART SURFACE",
      backlog: 0, workerCount: 0, autoWorkerCount: 0, activeMerges: 0,
      pendingMutations: 0, mutationParts: 0, failedMutations: 0,
      activeParts: 4, maxPartCount: 8
    }, maintenance),
    capacity: Object.assign({ memoryUsed: 256 * 1024 * 1024, memoryMax: 1024 * 1024 * 1024 }, capacity),
    replication: { replicaCount: 0, failures: 0 }
  }
}

function sqlserverSummary(at, counters = {}, connections = {}, maintenance = {}, capacity = {}) {
  return {
    kind: "summary",
    engine: "sqlserver",
    collectedAtMs: at,
    identity: { database: "hazel", user: "hazel", version: "16.0.4265.3", family: "sqlserver", inRecovery: false },
    capabilities: { fullStats: true, dataLocks: true },
    connections: Object.assign({
      used: 4, max: 704, active: 1, idle: 3, idleInTransaction: 0,
      waiting: 0, lockWaiting: 0, blocked: 0, oldestLockWaitSeconds: 0,
      oldestXactSeconds: 0, oldestIdleXactSeconds: 0, oldestQuerySeconds: 1
    }, connections),
    counters: Object.assign({
      workTotal: 100, rowsReturned: 0, rowsModified: 0,
      blocksRead: 100, blocksHit: 9900, logBytes: 10000,
      statsReset: "2026-08-22T00:00:00", logStatsReset: "2026-08-22T00:00:00"
    }, counters),
    maintenance: Object.assign({
      kind: "log", backlogLabel: "LOG USED", surfaceLabel: "TABLE PRESSURE",
      backlog: 10 * 1024 * 1024, logUsedPercent: 10, logReuseWait: "NOTHING"
    }, maintenance),
    capacity: Object.assign({
      memoryUsed: 50, memoryMax: 704, workersUsed: 50, workersMax: 704,
      logUsed: 10 * 1024 * 1024, logTotal: 100 * 1024 * 1024
    }, capacity),
    replication: { replicaCount: 0, maxByteLag: 0 }
  }
}

test("normalizes MySQL work, redo, and purge debt without PostgreSQL vocabulary", () => {
  const first = Model.ingestSummary(Model.emptyState(), mysqlSummary(1000), 120)
  const second = Model.ingestSummary(first, mysqlSummary(6000, {
    workTotal: 125, rowsReturned: 1100, rowsModified: 65, logBytes: 15120
  }, {}, { backlog: 19 }), 120)
  assert.equal(second.engine, "mysql")
  assert.equal(second.rates.work, 5)
  assert.equal(second.rates.transactions, 5)
  assert.equal(second.rates.rowsReturned, 20)
  assert.equal(second.rates.rowsModified, 3)
  assert.equal(second.rates.logBytes, 1024)
  assert.equal(second.maintenance.backlog, 19)
  assert.equal(second.histories.maintenanceBacklog.at(-1).value, 19)
  assert.match(Model.barLabel(second, "Work", false), /q\/s/)
  assert.match(Model.barLabel(second, "Maintenance", false), /undo/)
})

test("MariaDB and Percona retain distinct identity while sharing MySQL-family semantics", () => {
  for (const engine of ["mariadb", "percona"]) {
    const first = Model.ingestSummary(Model.emptyState(), mysqlSummary(1000, {}, {}, {}, engine), 120)
    const second = Model.ingestSummary(first, mysqlSummary(6000, {
      workTotal: 125, rowsReturned: 1100, rowsModified: 65, logBytes: 15120
    }, {}, { backlog: 19 }, engine), 120)
    assert.equal(second.engine, engine)
    assert.equal(Model.engineFamily(engine), "mysql")
    assert.equal(second.rates.work, 5)
    assert.match(Model.barLabel(second, "Work", false), /q\/s/)
    assert.match(Model.barLabel(second, "Maintenance", false), /undo/)
  }
  assert.equal(Model.engineLabel("mariadb"), "MariaDB")
  assert.equal(Model.engineLabel("percona"), "Percona")
})

test("ClickHouse uses query flow, memory capacity, and merge debt without lock or MVCC semantics", () => {
  const first = Model.ingestSummary(Model.emptyState(), clickhouseSummary(1000), 120)
  const second = Model.ingestSummary(first, clickhouseSummary(6000, {
    workTotal: 150, rowsReturned: 1500, rowsModified: 100, logBytes: 15120
  }, { active: 3 }, {
    backlog: 7, activeMerges: 1, workerCount: 1, pendingMutations: 1, autoWorkerCount: 1,
    mutationParts: 3, activeParts: 11
  }, { memoryUsed: 900 * 1024 * 1024 }), 120)

  assert.equal(Model.engineFamily("clickhouse"), "clickhouse")
  assert.deepEqual(Model.engineDefaults("clickhouse"), { port: 9000, database: "default", user: "default" })
  assert.equal(second.rates.work, 10)
  assert.equal(second.rates.rowsReturned, 100)
  assert.equal(second.rates.rowsModified, 10)
  assert.equal(second.rates.logBytes, 1024)
  assert.equal(second.capacityPercent, 87.890625)
  assert.equal(second.maintenance.backlogLabel, "MERGE DEBT")
  assert.equal(second.maintenance.pendingMutations, 1)
  assert.equal(second.histories.capacityUsed.at(-1).value, 900 * 1024 * 1024)
  assert.equal(second.severity, "warning")
  assert.equal(second.statusLabel, "Memory pressure")
  assert.match(Model.barLabel(second, "Work", false), /q\/s/)
  assert.match(Model.barLabel(second, "Adaptive", false), /mem/)
  assert.match(Model.barLabel(second, "Maintenance", false), /jobs/)

  const third = Model.ingestSummary(second, clickhouseSummary(11000, {
    workTotal: 175, rowsReturned: 1700, rowsModified: 110, logBytes: 17680
  }, {}, { backlog: 3 }), 120)
  assert.equal(third.pressures.maintenance, 3 / 7)
})

test("SQL Server uses batch flow, waiting tasks, worker occupancy, and transaction-log pressure", () => {
  const first = Model.ingestSummary(Model.emptyState(), sqlserverSummary(1000), 120)
  const second = Model.ingestSummary(first, sqlserverSummary(6000, {
    workTotal: 150, logBytes: 15120
  }, { active: 2, waiting: 1 }, {
    backlog: 80 * 1024 * 1024, logUsedPercent: 80, logReuseWait: "ACTIVE_TRANSACTION"
  }, {
    memoryUsed: 580, workersUsed: 580, logUsed: 80 * 1024 * 1024
  }), 120)

  assert.equal(Model.engineFamily("sqlserver"), "sqlserver")
  assert.equal(Model.engineLabel("sqlserver"), "SQL Server")
  assert.deepEqual(Model.engineDefaults("sqlserver"), { port: 1433, database: "master", user: "sa" })
  assert.equal(second.rates.work, 10)
  assert.equal(second.rates.logBytes, 1024)
  assert.equal(second.maintenance.kind, "log")
  assert.equal(second.maintenance.backlogLabel, "LOG USED")
  assert.equal(second.capacityPercent, 580 / 704 * 100)
  assert.equal(second.histories.capacityUsed.at(-1).value, 580)
  assert.equal(second.histories.maintenanceBacklog.at(-1).value, 80 * 1024 * 1024)
  assert.equal(second.severity, "warning")
  assert.equal(second.statusLabel, "Waiting")
  assert.match(Model.barLabel(second, "Work", false), /b\/s/)
  assert.match(Model.barLabel(second, "Capacity", false), /workers/)
  assert.match(Model.barLabel(second, "Maintenance", false), /MiB log/)
  assert.equal(Model.dependencyInstallCommand("sqlserver", "sqlcmd is not installed"), "omarchy pkg aur add mssql-tools")
})

test("SSH tunnel ports probe past collisions while preserving safe assignments", () => {
  const first = Model.internalTunnelPort("profile-a", [], 0)
  const profiles = [{ id: "another-profile", sshLocalPort: first }]
  const second = Model.internalTunnelPort("profile-a", profiles, first)
  assert.ok(first >= 56000 && first < 61000)
  assert.ok(second >= 56000 && second < 61000)
  assert.notEqual(second, first)
  assert.equal(Model.internalTunnelPort("profile-a", [], first), first)
})

test("derives rates from consecutive counter snapshots", () => {
  const first = Model.ingestSummary(Model.emptyState(), summary(1000, {}), 120)
  const second = Model.ingestSummary(first, summary(6000, {
    xactCommit: 120,
    xactRollback: 10,
    tuplesReturned: 1100,
    tuplesInserted: 30,
    tuplesUpdated: 15,
    tuplesDeleted: 5,
    walBytes: 15120
  }), 120)
  assert.equal(second.rates.transactions, 5)
  assert.equal(second.rates.rowsModified, 3)
  assert.equal(second.rates.rowsReturned, 20)
  assert.equal(second.rates.walBytes, 1024)
})

test("counter resets never produce negative or explosive rates", () => {
  const first = Model.ingestSummary(Model.emptyState(), summary(1000, { xactCommit: 1000 }), 120)
  const second = Model.ingestSummary(first, summary(6000, {
    xactCommit: 2,
    databaseStatsReset: "2026-02-01T00:00:00Z"
  }), 120)
  assert.equal(second.rates.transactions, 0)
  assert.equal(second.rates.rowsModified, 0)
})

test("fresh clusters with null reset timestamps still produce rates", () => {
  const first = Model.ingestSummary(Model.emptyState(), summary(1000, {
    databaseStatsReset: null,
    walStatsReset: null
  }), 120)
  const second = Model.ingestSummary(first, summary(6000, {
    xactCommit: 110,
    xactRollback: 5,
    walBytes: 15120,
    databaseStatsReset: null,
    walStatsReset: null
  }), 120)
  assert.equal(second.rates.transactions, 2)
  assert.equal(second.rates.walBytes, 1024)
})

test("transaction flow excludes Hazel's own completed snapshot transactions", () => {
  const first = Model.ingestSummary(Model.emptyState(), summary(1000, {}), 120)
  const payload = summary(6000, { xactCommit: 110 })
  payload.collectorTransactions = 2
  const second = Model.ingestSummary(first, payload, 120)
  assert.equal(second.rates.transactions, 1.6)
})

test("blocking wins adaptive toolbar priority", () => {
  const state = Model.ingestSummary(Model.emptyState(), summary(1000, {}, {
    active: 4, waiting: 2, lockWaiting: 1, blocked: 1
  }), 120)
  assert.equal(state.severity, "critical")
  assert.match(Model.barLabel(state, "Adaptive", false), /1 block/)
})

test("fleet toolbar aggregates every enabled collector without hiding failures", () => {
  const healthy = Model.ingestSummary(Model.emptyState(), summary(1000, {}, {
    active: 3, used: 8, max: 100
  }), 120)
  const blocked = Model.ingestSummary(Model.emptyState(), summary(1000, {}, {
    active: 2, waiting: 1, blocked: 1, used: 7, max: 50
  }), 120)
  const fleet = Model.fleetSummary([healthy, blocked])
  assert.equal(fleet.total, 2)
  assert.equal(fleet.connected, 2)
  assert.equal(fleet.active, 5)
  assert.equal(fleet.used, 15)
  assert.equal(fleet.max, 150)
  assert.equal(fleet.severity, "critical")
  assert.match(Model.fleetBarLabel([healthy, blocked], "Adaptive", false), /2\/2 · 1 block/)
})

test("mixed-engine fleet labels keep transaction, query, dead-row, undo, and merge units separate", () => {
  const postgres = Model.ingestSummary(Model.emptyState(), summary(1000, {}), 120)
  const mysql = Model.ingestSummary(Model.emptyState(), mysqlSummary(1000), 120)
  const clickhouse = Model.ingestSummary(Model.emptyState(), clickhouseSummary(1000, {}, {}, { backlog: 3 }), 120)
  const work = Model.fleetBarLabel([postgres, mysql, clickhouse], "Work", false)
  const maintenance = Model.fleetBarLabel([postgres, mysql, clickhouse], "Maintenance", false)
  assert.match(work, /PG .*t\/s · MY .*q\/s · CH .*q\/s/)
  assert.match(maintenance, /PG .*dead · MY .*undo · CH .*jobs/)
  assert.doesNotMatch(work, /ops\/s/)
})

test("fleet toolbar reports paused and unavailable sets explicitly", () => {
  assert.equal(Model.fleetBarLabel([], "Adaptive", false), "OFF")
  const healthy = Model.ingestSummary(Model.emptyState(), summary(1000, {}, { active: 2 }), 120)
  const down = Model.markDisconnected(Model.emptyState())
  assert.match(Model.fleetBarLabel([healthy, down], "Adaptive", false), /1\/2 · 1 down/)
})

test("a delayed snapshot keeps a previously sampled profile online but stale", () => {
  const sampled = Model.ingestSummary(Model.emptyState(), summary(1000, {}), 120)
  const stale = Model.markStale(sampled, "Snapshot delayed")
  assert.equal(stale.connected, true)
  assert.equal(stale.stale, true)
  assert.equal(stale.severity, "warning")
  assert.equal(stale.statusLabel, "Snapshot delayed")

  const neverSampled = Model.markStale(Model.emptyState(), "Snapshot delayed")
  assert.equal(neverSampled.connected, false)
  assert.equal(neverSampled.severity, "critical")
})

test("session histories obey their configured cap", () => {
  let state = Model.emptyState()
  for (let i = 0; i < 40; i++)
    state = Model.ingestSummary(state, summary(i * 2000, { xactCommit: 100 + i }), 30)
  assert.equal(state.histories.transactions.length, 30)
  assert.equal(state.histories.active.length, 30)
})

test("time-window histories use stable buckets and retain pressure context", () => {
  let state = Model.emptyState()
  const policy = { windowMs: 60_000, bucketMs: 5_000, maxPoints: 20 }
  for (let i = 0; i < 36; i++) {
    state = Model.ingestSummary(state, summary(100_000 + i * 2_000, {
      xactCommit: 100 + i * 2
    }, {
      active: 4,
      waiting: i % 5 === 0 ? 1 : 0,
      used: 10 + i % 3
    }, {
      liveTuples: 900,
      deadTuples: 100 + i
    }), policy)
  }
  const history = state.histories.transactions
  assert.ok(history.length >= 12 && history.length <= 14)
  assert.ok(history[0].time >= history.at(-1).time - policy.windowMs)
  assert.equal(new Set(history.map((point) => Math.floor(point.time / policy.bucketMs))).size, history.length)
  assert.equal(state.histories.lockWaiting.length, history.length)
  assert.equal(state.histories.connectionsUsed.length, history.length)
  assert.equal(state.histories.deadTuples.length, history.length)
  assert.equal(state.histories.autovacuumCount.length, history.length)
})

test("history statistics expose p25, p50, p90, and the high-water mark", () => {
  const stats = Model.historyStats([0, 1, 2, 3, 10].map((value, index) => ({ time: index, value })))
  assert.equal(stats.count, 5)
  assert.equal(stats.p25, 1)
  assert.equal(stats.p50, 2)
  assert.ok(Math.abs(stats.p90 - 7.2) < 1e-9)
  assert.equal(stats.low, 0)
  assert.equal(stats.high, 10)
})

test("history rates distinguish accumulating and clearing dead tuples", () => {
  const growing = [
    { time: 0, value: 1000 },
    { time: 60_000, value: 1300 },
    { time: 120_000, value: 1600 }
  ]
  const clearing = growing.concat({ time: 180_000, value: 400 })
  assert.equal(Model.historyRate(growing, 5 * 60_000, 60), 300)
  assert.equal(Model.historyRate(clearing, 60_000, 60), -1200)
  assert.equal(Model.historyDelta(clearing, 60_000), -1200)
  assert.deepEqual(Model.historyLastDrop(clearing), { amount: 1200, at: 180_000 })
})

test("details preserve summary state and remain read-only metadata", () => {
  const state = Model.ingestSummary(Model.emptyState(), summary(1000, {}), 120)
  const next = Model.ingestDetails(state, {
    activity: [{ pid: 42, queryId: 1001, state: "active", queryText: "SELECT * FROM events WHERE id = ?" }],
    relations: [{ relation: "events", deadTuples: 8 }],
    blocking: [],
    vacuum: []
  })
  assert.equal(next.identity.database, "hazel_test")
  assert.equal(next.activity[0].queryId, 1001)
  assert.equal(next.activity[0].queryText, "SELECT * FROM events WHERE id = ?")
  assert.equal(next.relations[0].relation, "events")
})

test("manifest keeps connection profiles in Hazel and secrets out of settings", () => {
  const root = path.join(__dirname, "..")
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "ryrobes.hazel")
  assert.equal(manifest.barWidget.allowMultiple, true)
  assert.equal(manifest.barWidget.defaults.historyHours, 6)
  assert.ok(manifest.barWidget.schema.some((item) => item.key === "historyHours"))
  assert.ok(!manifest.barWidget.schema.some((item) => ["profileName", "host", "port", "database", "user", "sslMode"].includes(item.key)))
  assert.ok(!manifest.barWidget.schema.some((item) => item.key === "serviceName"))
  assert.ok(!manifest.barWidget.schema.some((item) => /password|secret|token/i.test(item.key)))
})

test("missing database clients expose exact Omarchy package commands", () => {
  assert.equal(Model.dependencyInstallCommand("postgresql", "psql is not installed"), "omarchy pkg add postgresql-libs")
  assert.equal(Model.dependencyInstallCommand("mysql", "mariadb client is not installed"), "omarchy pkg add mariadb-clients")
  assert.equal(Model.dependencyInstallCommand("mariadb", "mariadb client is not installed"), "omarchy pkg add mariadb-clients")
  assert.equal(Model.dependencyInstallCommand("percona", "mariadb client is not installed"), "omarchy pkg add mariadb-clients")
  assert.equal(Model.dependencyInstallCommand("clickhouse", "clickhouse client is not installed"), "omarchy pkg add clickhouse")
  assert.equal(Model.dependencyInstallCommand("postgresql", "ssh is not installed"), "omarchy pkg add openssh")
  assert.equal(Model.dependencyInstallCommand("postgresql", "connection refused"), "")
})

test("AutoText boundaries neutralize markup without hiding the identifier", () => {
  const hostile = '<img src="file:///etc/passwd"> R&D > production'
  const safe = Model.neutralizeAutoText(hostile)
  assert.equal(safe, '‹img src="file:///etc/passwd"› R＆D › production')
  assert.doesNotMatch(safe, /[<>&]/)
})

test("publishing surface uses the permanent plugin identity", () => {
  const root = path.join(__dirname, "..")
  const readme = fs.readFileSync(path.join(root, "README.md"), "utf8")
  const notices = fs.readFileSync(path.join(root, "THIRD_PARTY_NOTICES.md"), "utf8")

  assert.match(readme, /omarchy plugin add https:\/\/github\.com\/ryrobes\/hazel\.git --enable/)
  assert.match(readme, /omarchy plugin remove ryrobes\.hazel/)
  assert.match(readme, /!\[Hazel monitoring multiple database profiles\]\(preview\.png\)/)
  assert.match(notices, /Third-party notices/)
  assert.ok(fs.existsSync(path.join(root, "preview.png")))
})

test("enabled named profiles own collectors, theme tone, and optional SSH transport", () => {
  const root = path.join(__dirname, "..")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const setup = fs.readFileSync(path.join(root, "ConnectionSetup.qml"), "utf8")
  const workspace = fs.readFileSync(path.join(root, "ProfileWorkspace.qml"), "utf8")
  const controller = fs.readFileSync(path.join(root, "HazelController.qml"), "utf8")

  assert.match(panel, /"profiles": profiles/)
  assert.match(panel, /delegate:\s*HazelController/)
  assert.match(panel, /active:\s*root\.collectorActive && profileData\.enabled !== false/)
  assert.match(panel, /Model\.fleetBarLabel/)
  assert.match(panel, /text:\s*"Config"/)
  assert.match(panel, /Number\(stored\.length\) > 0/)
  assert.match(setup, /"sshEnabled": sshToggle\.checked/)
  assert.match(setup, /"tone": toneField\.value/)
  assert.match(setup, /"rememberPassword": rememberToggle\.checked/)
  assert.doesNotMatch(setup, /localPortField|Local port/)
  assert.match(workspace, /MONITORED PROFILES/)
  assert.match(workspace, /profileEnabledChanged/)
  assert.doesNotMatch(workspace, /text:\s*"Use"/)
  assert.match(controller, /StrictHostKeyChecking=accept-new/)
  assert.match(panel, /profile\.sshLocalPort = Model\.internalTunnelPort\(profile\.id, profiles, profile\.sshLocalPort\)/)
  assert.match(panel, /Model\.internalTunnelPort\(profile\.id, profiles, previous\.sshLocalPort\)/)
  assert.match(controller, /ExitOnForwardFailure=yes/)
  assert.match(controller, /preserveExisting/)
  assert.match(controller, /state = Model\.emptyState\(\)/)
})

test("closed panels continue summary collection without fetching query details", () => {
  const root = path.join(__dirname, "..")
  const controller = fs.readFileSync(path.join(root, "HazelController.qml"), "utf8")
  assert.match(controller, /interval:\s*root\.panelOpen\s*\?\s*root\.openRefreshMs\s*:\s*root\.closedRefreshMs/)
  assert.match(controller, /onTriggered:\s*root\.panelOpen\s*\?\s*root\.refresh\(\)\s*:\s*root\.requestSummary\(\)/)
  assert.match(controller, /function requestDetails\(\)\s*\{\s*if \(panelOpen\)/)
})

test("profile expansion is exclusive, additive, and card-driven", () => {
  const root = path.join(__dirname, "..")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const queries = fs.readFileSync(path.join(root, "LiveQueries.qml"), "utf8")
  const locks = fs.readFileSync(path.join(root, "LockFlow.qml"), "utf8")

  assert.match(panel, /property string expandedProfileId:\s*""/)
  assert.match(panel, /expandedProfileId = expandedProfileId === wanted \? "" : wanted/)
  assert.match(panel, /Layout\.columnSpan:\s*instanceRows\.count > 1 && expanded \? 2 : 1/)
  assert.match(panel, /onExpansionRequested:\s*root\.toggleProfileExpansion\(entryId\)/)
  assert.match(panel, /minimized:\s*root\.hasExpandedProfile && !expanded/)
  assert.match(panel, /Layout\.row:\s*expanded \? 0/)
  assert.doesNotMatch(panel, /text:\s*root\.expanded \? "Collapse" : "Expand"/)
  assert.match(block, /signal expansionRequested\(\)/)
  assert.match(block, /property bool minimized:\s*false/)
  assert.match(block, /Layout\.maximumWidth:\s*root\.expanded \? root\.width : Style\.space\(190\)/)
  assert.match(block, /elide:\s*root\.expanded \? Text\.ElideNone : Text\.ElideRight/)
  assert.match(block, /elide:\s*root\.expanded \? Text\.ElideNone : Text\.ElideMiddle/)
  assert.match(block, /visible:\s*!root\.minimized && root\.connected\s*\n\s*Layout\.fillWidth:\s*true\s*\n\s*Layout\.fillHeight:\s*true/)
  assert.match(block, /LIVE WORK \u00b7 .* CAPTURED/)
  assert.match(queries, /root\.activity\.length \+ " CAPTURED"/)
  assert.match(queries, /visibleQueries:\s*firstRows\(activity, 3\)/)
  assert.match(locks, /visibleEdges:\s*firstRows\(edges, 3\)/)
  assert.match(locks, /mode \+ " · " \+ target/)
  assert.doesNotMatch(queries + locks, /Array\.isArray/)
})

test("refreshes update stable instance roles in place and use a restrained wash", () => {
  const root = path.join(__dirname, "..")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")

  assert.match(panel, /id:\s*instanceRows\s*\n\s*dynamicRoles:\s*true/)
  assert.match(panel, /model:\s*instanceRows/)
  assert.match(panel, /instanceRows\.setProperty\(updated, "stateData", next\.state\)/)
  assert.doesNotMatch(panel, /model:\s*root\.instances/)
  assert.match(block, /id:\s*refreshWash/)
  assert.match(block, /from:\s*0\.045\s*\n\s*to:\s*0/)
  assert.match(block, /Behavior on cardHeight/)
})

test("duplicate bar instances continuously recover collector leadership", () => {
  const root = path.join(__dirname, "..")
  const bar = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
  assert.match(bar, /id:\s*leaderElection[\s\S]*?repeat:\s*true/)
  assert.match(bar, /sourcePanel = leader !== root && leader && leader\.panelItem \? leader\.panelItem : null/)
})

test("behavior memory retains 24 hours and exposes honest viewport lenses", () => {
  const root = path.join(__dirname, "..")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const aperture = fs.readFileSync(path.join(root, "PressureAperture.qml"), "utf8")
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

  assert.match(panel, /property int viewWindowHours:\s*normalizedHistoryWindow/)
  assert.match(panel, /result\.historyHours = 24/)
  assert.match(panel, /onHistoryWindowRequested:\s*function\(hours\)/)
  assert.match(block, /expandedLayout:\s*root\.expanded/)
  assert.match(block, /if \(!root\.windowControlActive\)\s*\n\s*root\.expansionRequested\(\)/)
  assert.match(aperture, /signal windowRequested\(int hours\)/)
  assert.match(aperture, /onPressed:\s*root\.windowInteractionStarted\(\)/)
  assert.match(aperture, /\[1, 3, 6, 24\]/)
  assert.match(aperture, /cutoff = latest - windowHours \* 60 \* 60 \* 1000/)
  assert.match(aperture, /H LENS.*OBSERVED/)
  assert.match(manifest.barWidget.schema.find((item) => item.key === "historyHours").description, /retains up to 24 hours/)
})

test("expanded memory lanes get room while compact flow clears its rate label", () => {
  const root = path.join(__dirname, "..")
  const aperture = fs.readFileSync(path.join(root, "PressureAperture.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")

  assert.match(aperture, /implicitHeight: Style\.space\(expandedLayout \? 236 : 146\)/)
  assert.match(aperture, /Layout\.preferredHeight: Style\.space\(root\.expandedLayout \? 42 : 24\)/)
  assert.match(aperture, /height: Style\.space\(root\.expandedLayout \? 24 : 9\)/)
  assert.doesNotMatch(block, /OPEN DETAILS|CLOSE DETAILS/)
  assert.match(block, /anchors\.topMargin: Style\.space\(root\.expanded \? 8 : 15\)/)
})

test("collapsed engine watermark swaps to pg_rvbbit when the extension is present", () => {
  const root = path.join(__dirname, "..")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const watermark = fs.readFileSync(path.join(root, "DatabaseWatermark.qml"), "utf8")
  const sql = fs.readFileSync(path.join(root, "postgres", "summary.sql"), "utf8")

  assert.match(block, /visible: !root\.expanded && !root\.minimized && root\.connected/)
  assert.match(block, /pgRvbbit: root\.snapshot\.capabilities\.pgRvbbit === true/)
  assert.match(watermark, /implicitWidth: 108/)
  assert.match(watermark, /implicitHeight: 81/)
  assert.match(watermark, /pgRvbbit \? "assets\/pg-rvbbit\.svg" : "assets\/postgresql\.svg"/)
  assert.match(watermark, /engine === "mysql"[\s\S]*?assets\/mysql\.svg/)
  assert.match(watermark, /engine === "mariadb"[\s\S]*?assets\/mariadb\.svg/)
  assert.match(watermark, /engine === "percona"[\s\S]*?assets\/percona\.svg/)
  assert.match(watermark, /engine === "clickhouse"[\s\S]*?assets\/clickhouse\.svg/)
  assert.match(watermark, /engine === "sqlserver"[\s\S]*?assets\/sqlserver\.svg/)
  assert.match(watermark, /colorizationColor: root\.accent/)
  assert.match(sql, /FROM pg_extension WHERE extname = 'pg_rvbbit'/)
  assert.match(sql, /'pgRvbbit', identity\.has_pg_rvbbit/)
})

test("profiles select a real engine adapter while sharing one normalized UI contract", () => {
  const root = path.join(__dirname, "..")
  const setup = fs.readFileSync(path.join(root, "ConnectionSetup.qml"), "utf8")
  const controller = fs.readFileSync(path.join(root, "HazelController.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const aperture = fs.readFileSync(path.join(root, "PressureAperture.qml"), "utf8")
  const background = fs.readFileSync(path.join(root, "BackgroundWork.qml"), "utf8")
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

  assert.match(setup, /"engine": engineField\.value/)
  assert.match(setup, /"value": "mysql", "label": "MySQL 8\+"/)
  assert.match(setup, /"value": "mariadb", "label": "MariaDB"/)
  assert.match(setup, /"value": "percona", "label": "Percona 8\+"/)
  assert.match(setup, /"value": "clickhouse", "label": "ClickHouse"/)
  assert.match(setup, /"value": "sqlserver", "label": "SQL Server"/)
  assert.match(controller, /engineName === "mariadb" \? "mariadb"/)
  assert.match(controller, /engineFamily === "clickhouse" \? "clickhouse"/)
  assert.match(controller, /function mysqlCommand\(\)/)
  assert.match(controller, /function clickhouseCommand\(sql\)/)
  assert.match(controller, /function sqlserverCommand\(\)/)
  assert.match(controller, /mariadb.*--skip-column-names.*--unbuffered/)
  assert.match(controller, /environment\.CLICKHOUSE_PASSWORD = sessionPassword/)
  assert.match(controller, /environment\.SQLCMDPASSWORD = sessionPassword/)
  assert.match(controller, /"-w", "65535", "-y", "0", "-r1", "-b", "-x"/)
  assert.match(controller, /function clickhouseCommand\(sql\)/)
  assert.match(controller, /--query", String\(sql \|\| ""\)/)
  assert.match(controller, /engineFamily === "clickhouse" && root\.oneShotSucceeded/)
  assert.match(controller, /function enqueueRequest\(kind\)/)
  assert.match(controller, /function takeQueuedRequest\(fallback\)/)
  assert.match(controller, /if \(summaryQueued\)[\s\S]*?return "summary"/)
  assert.match(controller, /Model\.markStale\(root\.state, "Snapshot delayed"\)/)
  assert.match(controller, /if \(sshEnabled && !tunnelReady\)[\s\S]*?ensureTunnel\(\)/)
  assert.match(controller, /MAX_EXECUTION_TIME=5000/)
  assert.match(controller, /max_statement_time=5/)
  assert.match(block, /root\.snapshot\.maintenance\.surfaceLabel/)
  assert.match(block, /Model\.isSqlServer\(root\.snapshot\.engine\) \? " b\/s"/)
  assert.match(block, /\["RUN", "MERGE", "MUTATE", "MEM"\]/)
  assert.match(block, /BackgroundWork\s*\{/)
  assert.match(aperture, /maintenanceKind === "purge"/)
  assert.match(aperture, /\["flow", "running", "memory", "maintenance"\]/)
  assert.match(aperture, /\["flow", "locks", "workers", "log"\]/)
  assert.match(background, /NumberAnimation on phase/)
  assert.match(background, /running: root\.visible && root\.jobs\.length > 0/)
  assert.match(background, /parts at rest/)
  assert.match(setup, /engineFamily\(engine\) !== "postgresql" && value === "verify-ca"/)
  assert.match(setup, /"Verify certificate"/)
  assert.deepEqual(manifest.barWidget.schema.find((item) => item.key === "toolbarMetric").options,
    ["Adaptive", "Work", "Activity", "Connections", "Waits", "Log", "Maintenance"])
})

test("collector secrets stay out of argv and database streams are bounded", () => {
  const root = path.join(__dirname, "..")
  const controller = fs.readFileSync(path.join(root, "HazelController.qml"), "utf8")
  const reader = fs.readFileSync(path.join(root, "BoundedLineReader.qml"), "utf8")

  assert.doesNotMatch(controller, /\["env"/)
  assert.doesNotMatch(controller, /command\.push\("(?:PGPASSWORD|MYSQL_PWD|CLICKHOUSE_PASSWORD|SQLCMDPASSWORD)=/)
  assert.match(controller, /psqlProc\.environment = databaseEnvironment\(\)/)
  assert.match(controller, /environment\.PGPASSWORD = sessionPassword/)
  assert.match(controller, /environment\.MYSQL_PWD = sessionPassword/)
  assert.match(controller, /environment\.CLICKHOUSE_PASSWORD = sessionPassword/)
  assert.match(controller, /environment\.SQLCMDPASSWORD = sessionPassword/)
  assert.match(controller, /property int credentialGeneration:\s*0/)
  assert.match(controller, /property bool secretLookupStopping:\s*false/)
  assert.match(controller, /secretLookupGeneration !== root\.credentialGeneration/)
  assert.match(controller, /function invalidateCredentialLookup\(\)/)
  assert.equal((controller.match(/stdout:\s*BoundedLineReader/g) || []).length, 1)
  assert.equal((controller.match(/stderr:\s*BoundedLineReader/g) || []).length, 2)
  assert.match(reader, /splitMarker:\s*preserveUtf8Lines \? "\\n" : ""/)
  assert.match(controller, /preserveUtf8Lines:\s*true/)
  assert.match(reader, /pending\.length \+ segment\.length > maximumLineLength/)
  assert.match(reader, /discardingOversizedLine = true/)
  assert.match(reader, /readonly property int bufferedLength: pending\.length/)
})

test("small visual primitives repaint completely and avoid fake mutation progress", () => {
  const root = path.join(__dirname, "..")
  const sparkline = fs.readFileSync(path.join(root, "Sparkline.qml"), "utf8")
  const background = fs.readFileSync(path.join(root, "BackgroundWork.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")

  assert.match(sparkline, /onGridColorChanged:\s*canvas\.requestPaint\(\)/)
  assert.match(sparkline, /onMaximumChanged:\s*canvas\.requestPaint\(\)/)
  assert.match(sparkline, /if \(points\.length === 1\)/)
  assert.match(background, /if \(job\.kind === "merge"\)/)
  assert.match(block, /runningQueries:\s*Number\(root\.snapshot\.connections\.active \|\| 0\)/)
})

test("profile cards keep only the accent rail and mark their database identity", () => {
  const root = path.join(__dirname, "..")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const glyph = fs.readFileSync(path.join(root, "DatabaseGlyph.qml"), "utf8")

  assert.match(block, /borderSpec: Border\.none\(\)/)
  assert.doesNotMatch(block, /borderSpec: Border\.controlSpec/)
  assert.match(block, /DatabaseGlyph\s*\{/)
  assert.match(block, /text: root\.databaseName\(\) \+ " · " \+ root\.routeLabel\(\)/)
  assert.match(glyph, /assets\/database\.svg/)
  assert.match(glyph, /implicitWidth: 11/)
  assert.match(glyph, /colorizationColor: root\.accent/)
})

test("missing-client cards render a selectable console install command", () => {
  const root = path.join(__dirname, "..")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const controller = fs.readFileSync(path.join(root, "HazelController.qml"), "utf8")

  assert.match(block, /Model\.dependencyInstallCommand\(profile\.engine, errorText\)/)
  assert.match(block, /text:\s*"\$"/)
  assert.match(block, /TextEdit\s*\{[\s\S]*?readOnly:\s*true[\s\S]*?selectByMouse:\s*true[\s\S]*?text:\s*root\.installCommand/)
  assert.match(block, /text:\s*"COPY \/ PASTE"/)
  assert.match(controller, /if \(exitCode === 127\)\s*root\.errorText = root\.missingClientError\(\)/)
  assert.match(controller, /root\.errorText = exitCode === 127\s*\? "ssh is not installed"/)
})

test("database and profile controlled labels never reach QML AutoText", () => {
  const root = path.join(__dirname, "..")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")
  const workspace = fs.readFileSync(path.join(root, "ProfileWorkspace.qml"), "utf8")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const bar = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")

  assert.match(block, /text:\s*root\.identityMeta\(\)\.toUpperCase\(\)\s*\n\s*textFormat:\s*Text\.PlainText/)
  assert.match(block, /text:\s*modelData\.schema \+ "\." \+ modelData\.relation\s*\n\s*textFormat:\s*Text\.PlainText/)
  assert.match(block, /text:\s*root\.relationDetail\(modelData\)\s*\n\s*textFormat:\s*Text\.PlainText/)
  assert.match(workspace, /text:\s*String\(profileCard\.modelData\.name[\s\S]*?textFormat:\s*Text\.PlainText/)
  assert.match(workspace, /text:\s*String\(profileCard\.modelData\.database[\s\S]*?textFormat:\s*Text\.PlainText/)
  assert.match(workspace, /text:\s*profileCard\.modelData\.sshEnabled[\s\S]*?textFormat:\s*Text\.PlainText/)
  assert.match(panel, /Model\.neutralizeAutoText\(row\.profile\.name/)
  assert.match(panel, /Model\.neutralizeAutoText\(row\.errorText/)
  assert.equal((bar.match(/textFormat:\s*Text\.PlainText/g) || []).length, 2)
})

test("bar branding uses native vector Hazel marks without redistributing font software", () => {
  const root = path.join(__dirname, "..")
  const bar = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const mark = fs.readFileSync(path.join(root, "HazelMark.qml"), "utf8")
  const wordmark = fs.readFileSync(path.join(root, "HazelWordmark.qml"), "utf8")
  const rabbit = fs.readFileSync(path.join(root, "assets", "bar-rabbit.svg"), "utf8")
  const wordmarkSvg = fs.readFileSync(path.join(root, "assets", "hazel-wordmark.svg"), "utf8")

  assert.match(bar, /HazelMark\s*\{/)
  assert.doesNotMatch(bar, /component RabbitMark: Item/)
  assert.match(bar, /labelVisible: false/)
  assert.doesNotMatch(bar, /"HZL/)
  assert.match(mark, /import QtQuick\.Shapes/)
  assert.match(mark, /preferredRendererType: Shape\.CurveRenderer/)
  assert.match(mark, /fillRule: ShapePath\.OddEvenFill/)
  assert.match(mark, /fillColor: root\.tint/)
  assert.match(mark, /M5\.1 12\.2h13\.8l-2 3\.1H7\.1z/)
  assert.doesNotMatch(mark, /MultiEffect|Image\s*\{/)
  assert.match(rabbit, /<title>Hazel Visor<\/title>/)
  assert.match(rabbit, /M5\.1 12\.2h13\.8l-2 3\.1H7\.1z/)
  assert.match(panel, /HazelWordmark\s*\{/)
  assert.doesNotMatch(panel, /FontLoader|Outrun-future-Bold\.otf/)
  assert.equal(fs.existsSync(path.join(root, "assets", "fonts", "Outrun-future-Bold.otf")), false)
  assert.match(wordmark, /import QtQuick\.Shapes/)
  assert.match(wordmark, /preferredRendererType: Shape\.CurveRenderer/)
  assert.match(wordmark, /fillColor: root\.tint/)
  assert.match(wordmark, /readonly property var glyphs:/)
  assert.equal((wordmark.match(/"offset":/g) || []).length, 5)
  assert.match(wordmarkSvg, /<title id="title">Hazel wordmark<\/title>/)
  assert.equal((wordmarkSvg.match(/<path /g) || []).length, 5)
  assert.match(panel, /HazelMark\s*\{[\s\S]*?Layout\.preferredWidth: headerTitles\.implicitHeight[\s\S]*?Layout\.maximumHeight: headerTitles\.implicitHeight[\s\S]*?tint: root\.statusColor\(\)/)
  assert.match(panel, /ColumnLayout\s*\{\s*id: headerTitles/)
})

test("the header reserves attention for notable events and exposes no future query actions", () => {
  const root = path.join(__dirname, "..")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const block = fs.readFileSync(path.join(root, "InstanceBlock.qml"), "utf8")

  assert.match(panel, /function notableEvent\(\)/)
  assert.match(panel, /blocked \+ " BLOCKED" \+ age/)
  assert.match(panel, /" PROFILE DOWN"/)
  assert.match(panel, /" LOCK WAIT"/)
  assert.match(panel, /visible: root\.notable\.label !== ""/)
  assert.doesNotMatch(panel, /READ ONLY/)
  assert.doesNotMatch(block, /Inspect query|Cancel query|Reserved for a later|read-only first release/)
  assert.match(block, /text: "MEMORY ONLY · "/)
})

test("shipped SQL is SELECT-only and masks active query literals", () => {
  const root = path.join(__dirname, "..")
  for (const file of ["summary.sql", "details.sql"]) {
    const sql = fs.readFileSync(path.join(root, "postgres", file), "utf8")
    assert.doesNotMatch(sql, /\b(insert|update|delete|alter|drop|truncate|vacuum|analyze|reindex|create)\s+/i)
    assert.doesNotMatch(sql, /['\"]query['\"]\s*,\s*query\b/i)
  }
  const details = fs.readFileSync(path.join(root, "postgres", "details.sql"), "utf8")
  const summarySql = fs.readFileSync(path.join(root, "postgres", "summary.sql"), "utf8")
  const controller = fs.readFileSync(path.join(root, "HazelController.qml"), "utf8")
  assert.match(details, /'queryText'/)
  assert.match(details, /AND state = 'active'/)
  assert.match(details, /regexp_replace\(query/)
  assert.match(details, /to_jsonb\(pg_stat_activity\).*query_id/)
  assert.ok(details.includes("E'\\\\$\\\\$.*\\\\$\\\\$'"))
  assert.doesNotMatch(details, /indexes_processed|indexes_total|num_dead_item_ids/)
  assert.match(controller, /environment\.PGAPPNAME = "hazel-monitor"/)
  assert.match(summarySql, /application_name IS DISTINCT FROM 'hazel-monitor'/)
  assert.match(summarySql, /server_version_num.*120000/)
  assert.match(summarySql, /server_version_num.*140000/)
  assert.match(summarySql, /hazel_legacy_wal/)
  assert.match(summarySql, /^BEGIN READ ONLY;/)
  assert.match(summarySql, /COMMIT;\s*$/)
  assert.match(details, /application_name IS DISTINCT FROM 'hazel-monitor'/)

  for (const file of ["summary.sql", "details.sql"]) {
    const mysqlSql = fs.readFileSync(path.join(root, "mysql", file), "utf8")
    assert.doesNotMatch(mysqlSql, /^\s*(insert|update|delete|replace|create|alter|drop|truncate|grant|revoke|call|do|set)\b/im)
    const mariaSql = fs.readFileSync(path.join(root, "mariadb", file), "utf8")
    assert.doesNotMatch(mariaSql, /^\s*(insert|update|delete|replace|create|alter|drop|truncate|grant|revoke|call|do|set)\b/im)
  }
  const mysqlDetails = fs.readFileSync(path.join(root, "mysql", "details.sql"), "utf8")
  assert.match(mysqlDetails, /performance_schema\.processlist/)
  assert.match(mysqlDetails, /performance_schema\.data_lock_waits/)
  assert.match(mysqlDetails, /performance_schema\.metadata_locks/)
  assert.match(mysqlDetails, /REGEXP_REPLACE/)
  const mysqlSummarySql = fs.readFileSync(path.join(root, "mysql", "summary.sql"), "utf8")
  assert.match(mysqlSummarySql, /version_comment[\s\S]*?LIKE '%percona%'[\s\S]*?'percona'/)
  const mariaDetails = fs.readFileSync(path.join(root, "mariadb", "details.sql"), "utf8")
  assert.match(mariaDetails, /information_schema\.PROCESSLIST/)
  assert.match(mariaDetails, /information_schema\.INNODB_LOCK_WAITS/)
  assert.match(mariaDetails, /information_schema\.INNODB_LOCKS/)
  assert.match(mariaDetails, /REGEXP_REPLACE/)

  for (const file of ["summary.sql", "details.sql"]) {
    const clickhouseSql = fs.readFileSync(path.join(root, "clickhouse", file), "utf8")
    assert.doesNotMatch(clickhouseSql, /^\s*(insert|update|delete|create|alter|drop|truncate|grant|revoke|kill|optimize|system|set)\b/im)
  }
  const clickhouseSummarySql = fs.readFileSync(path.join(root, "clickhouse", "summary.sql"), "utf8")
  const clickhouseDetails = fs.readFileSync(path.join(root, "clickhouse", "details.sql"), "utf8")
  assert.match(clickhouseSummarySql, /system\.events/)
  assert.match(clickhouseSummarySql, /system\.merges/)
  assert.match(clickhouseSummarySql, /system\.mutations/)
  assert.match(clickhouseDetails, /system\.processes/)
  assert.match(clickhouseDetails, /system\.parts/)
  assert.match(clickhouseDetails, /system\.mutations/)
  assert.match(clickhouseDetails, /replaceRegexpAll/)

  for (const file of ["summary.sql", "details.sql"]) {
    const sqlserverSql = fs.readFileSync(path.join(root, "sqlserver", file), "utf8")
    assert.doesNotMatch(sqlserverSql, /^\s*(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|kill|execute|exec)\b/im)
  }
  const sqlserverSummarySql = fs.readFileSync(path.join(root, "sqlserver", "summary.sql"), "utf8")
  const sqlserverDetails = fs.readFileSync(path.join(root, "sqlserver", "details.sql"), "utf8")
  assert.match(sqlserverSummarySql, /sys\.dm_os_performance_counters/)
  assert.match(sqlserverSummarySql, /sys\.dm_os_waiting_tasks/)
  assert.match(sqlserverSummarySql, /sys\.dm_db_log_space_usage/)
  assert.match(sqlserverDetails, /sys\.dm_exec_requests/)
  assert.match(sqlserverDetails, /sys\.dm_db_index_operational_stats/)
  assert.match(sqlserverDetails, /query_hash/)
  assert.doesNotMatch(sqlserverDetails, /SUBSTRING\([^)]*\.text/i)
})
