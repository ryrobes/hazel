# Hazel

Hazel is a read-only database instrument for the Omarchy 4 bar. It monitors
PostgreSQL and MySQL 8+ through one persistent, noninteractive client
connection per enabled profile. Every collector keeps its own time-bucketed
session history in memory and never writes to the database it observes.

Hazel is deliberately not a tiny Grafana dashboard. Its first job is to show
what changed: work rate, session pressure, waits and blocking, log generation,
and engine-native maintenance signals.

The bar uses Hazel's original angular Visor rabbit mark rather than a text
abbreviation. The open-panel HAZEL wordmark uses the embedded Outrun future
Bold display face. A larger Visor spans the panel header's two text rows,
replaces the generic status dot, and inherits its live fleet-status color
without increasing the header height. No font or artwork is fetched while
Hazel is running. Both Visors use the SVG's original path geometry through Qt
Quick Shape, keeping the enlarged header mark vector-sharp instead of scaling
a rasterized texture.

Collapsed profile cards carry a faint, theme-tinted engine mark in a fixed
watermark bay. PostgreSQL uses the embedded CC0 SVG Repo elephant; databases
with the `pg_rvbbit` extension installed use Hazel's embedded rvbbit mark
instead. MySQL uses an embedded, theme-tinted CC0 dolphin mark in the same
fixed bay, which remains the contract for future adapter marks.

Profile cards are separated by space and their persistent accent rail rather
than a perimeter stroke. A small embedded database glyph carries that same
profile accent beside the database and route in compact and expanded views.

When the panel is open, Hazel also samples active client queries and current
blocking edges. Query whitespace is normalized and string/number literals are
masked by each adapter before the text reaches the UI; idle sessions are not
shown. Lock flow is rendered holder-to-waiter with the waiting mode and target
when the engine exposes them. MySQL combines InnoDB data-lock waits and pending
metadata locks, and labels each edge by lock family.

Summary collection for every enabled profile continues while the panel is
closed (every five seconds by default), so reopening Hazel preserves the
context gathered while it was out of sight. The Pressure Memory view uses
those per-profile five-second buckets to show the
current value, p50, p90, and session high-water mark for engine-native work
flow, lock-wait counts, used connections, and maintenance backlog. Connections are
shown as an actual used/max count while their rail zooms to the observed range.
PostgreSQL pairs dead-tuple history with a five-minute accumulation or drain
rate and active/recent autovacuum state. MySQL instead shows purge debt from
the InnoDB undo history list, its accumulation/drain trend, and available purge
threads. The lock row pairs its baseline with the current blocked count and
oldest wait age. The window is configurable from
1–24 hours and defaults to six hours. History remains memory-only in v0.2 and
resets when the Omarchy shell restarts. Flow subtracts Hazel's own known
snapshot work so an otherwise quiet database still reads as quiet.

## Status

This is an early working shell. PostgreSQL and MySQL 8 summary/detail snapshots
are implemented. Future releases will deepen capability-aware views and may
add optional SQLite or DuckDB history outside the monitored database.

The PostgreSQL watermark is adapted from the CC0 mark at
https://www.svgrepo.com/svg/306591/postgresql.

The MySQL watermark is adapted from the CC0 mark at
https://www.svgrepo.com/svg/303251/mysql-logo.

The Visor rabbit is original artwork developed for Hazel. The embedded Outrun
future Bold font was supplied from the local RVBBIT font collection.

## Requirements

- Omarchy 4.0 or newer
- PostgreSQL `psql` client for PostgreSQL profiles
- `mariadb-clients` for MySQL profiles (the MariaDB CLI speaks the MySQL protocol)
- A database account with read access to the engine's monitoring views

For full visibility into other sessions, grant the monitoring account the
built-in `pg_monitor` role. Hazel degrades when fields are restricted and does
not require a superuser.

For MySQL, grant `PROCESS` and `REPLICATION CLIENT`, plus `SELECT` on the
monitored schema, `performance_schema.*`, and `sys.*`. Hazel's included Docker
fixture applies exactly this read-only monitoring grant set; fixture mutation
is performed separately as root by the tests.

## Connect

Open Hazel's **Config** view to add, edit, pause, or enable named profiles.
There is no selected database: Hazel samples every enabled profile concurrently
and renders a live instrument block for each one. Profile tone is derived from
the current Omarchy theme and follows that database through pressure memory,
activity, lock flow, and status. Histories remain isolated per profile and are
never combined into a synthetic database timeline.

Each profile chooses PostgreSQL or MySQL, then defines that engine's target and
can optionally use a separate SSH
gateway. Hazel manages forwarding internally, so the editor only asks for the
database and SSH ports people actually configure. SSH is noninteractive: use
the system agent/default key or specify an identity file in the profile. Hazel
accepts a new OpenSSH host key once; changed keys still fail rather than
silently replacing the trusted key.

The **Remember database password** preference belongs to the profile. Its
password is stored through the desktop keyring when enabled, or kept only in
the running shell session when disabled. Editing an existing profile leaves
the password field blank and preserves the credential already in use unless a
replacement is entered. All non-secret profile data is saved through Omarchy's
supported per-widget settings API.

No `.pg_service.conf`, `.pgpass`, MySQL option file, or Hazel-specific
connection file is required. A local peer-authenticated PostgreSQL server can
leave the password empty; a Unix socket path can be entered in the host field.

## Local PostgreSQL and MySQL test targets

The included Compose project exposes PostgreSQL 18 on `127.0.0.1:55432` and
MySQL 8.4 LTS on `127.0.0.1:55433`:

```sh
docker compose up -d --wait
```

Both use database/user `hazel` and password `hazel-dev-only`. These credentials
are for the local development containers only. The MySQL monitor account is
read-only; tests use the separate root fixture credential only to manufacture
active queries, lock waits, and purge debt.

## Development install

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/ryan.hazel
omarchy-shell shell rescanPlugins
omarchy plugin enable ryan.hazel
```

Saved QML changes hot-reload. Validate before testing:

```sh
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell \
  BarWidget.qml Panel.qml HazelController.qml Sparkline.qml PressureAperture.qml
node --test tests/model.test.js
tests/postgres-sql.test.sh
tests/mysql-sql.test.sh
```

## Controls

- Left click: open or close Hazel
- Click a profile block: focus or close that profile's investigation details
- Click a minimized profile row: switch focus without reopening the full grid
- In a focused profile, choose **1H**, **3H**, **6H**, or **24H** to change the behavior-memory lens
- Middle click: refresh immediately
- `C` or **Config**: choose which profiles Hazel monitors and edit connections
- `R`: refresh immediately
- `Esc`: close
- `Tab` / `Shift+Tab`: switch between adjacent Omarchy panels

Hazel v0.2 is strictly read-only. Query inspection and cancellation affordances
remain intentionally deferred until the interaction and privilege model is
ready for them.

## Privacy and safety

- No telemetry or external service
- No passwords in Omarchy settings or Hazel-owned files
- No writes to the monitored database
- Active query text is session-only, whitespace-normalized, and literal-masked
- Fixed SQL shipped with the plugin; connection fields are passed through
  environment variables, not interpolated into SQL

## License

MIT
