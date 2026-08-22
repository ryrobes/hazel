# Hazel

Hazel is a read-only database instrument for the Omarchy 4 bar. The first
adapter monitors PostgreSQL through one persistent, noninteractive `psql`
connection per enabled profile. Every collector keeps its own time-bucketed
session history in memory and never writes to the database it observes.

Hazel is deliberately not a tiny Grafana dashboard. Its first job is to show
what changed: transaction activity, session pressure, waits and blocking,
WAL generation, and MVCC maintenance signals.

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
instead. The fixed bay is also the contract for future MySQL, ClickHouse, and
other adapter marks.

Profile cards are separated by space and their persistent accent rail rather
than a perimeter stroke. A small embedded database glyph carries that same
profile accent beside the database and route in compact and expanded views.

When the panel is open, Hazel also samples active client queries and current
blocking edges. Query whitespace is normalized and string/number literals are
masked inside PostgreSQL before the text reaches the UI; idle sessions are not
shown. Lock flow is rendered holder-to-waiter with the waiting mode and target
when PostgreSQL exposes them.

Summary collection for every enabled profile continues while the panel is
closed (every five seconds by default), so reopening Hazel preserves the
context gathered while it was out of sight. The Pressure Memory view uses
those per-profile five-second buckets to show the
current value, p50, p90, and session high-water mark for transaction flow,
lock-wait counts, used connections, and estimated dead tuples. Connections are
shown as an actual used/max count while their rail zooms to the observed range.
The MVCC row pairs dead-tuple history with a five-minute accumulation or drain
rate and active/recent autovacuum state; the lock row pairs its baseline with
the current blocked count and oldest wait age. The window is configurable from
1–24 hours and defaults to six hours. History remains memory-only in v0.1 and
resets when the Omarchy shell restarts. Flow subtracts Hazel's own known
snapshot transactions so an otherwise quiet database still reads as quiet.

## Status

This is an early working shell. PostgreSQL summary and detail snapshots are
implemented; future releases will deepen capability-aware views and may add
optional SQLite or DuckDB history outside the monitored database.

The PostgreSQL watermark is adapted from the CC0 mark at
https://www.svgrepo.com/svg/306591/postgresql.

The Visor rabbit is original artwork developed for Hazel. The embedded Outrun
future Bold font was supplied from the local RVBBIT font collection.

## Requirements

- Omarchy 4.0 or newer
- PostgreSQL `psql` client
- A PostgreSQL account with read access to the standard statistics views

For full visibility into other sessions, grant the monitoring account the
built-in `pg_monitor` role. Hazel degrades when fields are restricted and does
not require a superuser.

## Connect

Open Hazel's **Config** view to add, edit, pause, or enable named profiles.
There is no selected database: Hazel samples every enabled profile concurrently
and renders a live instrument block for each one. Profile tone is derived from
the current Omarchy theme and follows that database through pressure memory,
activity, lock flow, and status. Histories remain isolated per profile and are
never combined into a synthetic database timeline.

Each profile has a PostgreSQL target and can optionally use a separate SSH
gateway. Hazel manages forwarding internally, so the editor only asks for the
PostgreSQL and SSH ports people actually configure. SSH is noninteractive: use
the system agent/default key or specify an identity file in the profile. Hazel
accepts a new OpenSSH host key once; changed keys still fail rather than
silently replacing the trusted key.

The **Remember database password** preference belongs to the profile. Its
password is stored through the desktop keyring when enabled, or kept only in
the running shell session when disabled. Editing an existing profile leaves
the password field blank and preserves the credential already in use unless a
replacement is entered. All non-secret profile data is saved through Omarchy's
supported per-widget settings API.

No `.pg_service.conf`, `.pgpass`, or Hazel-specific connection file is
required. A local peer-authenticated server can leave the password empty; a
Unix socket path can be entered in the host field.

## Local PostgreSQL test target

The included Compose target exposes PostgreSQL 18 on `127.0.0.1:55432`:

```sh
docker compose up -d --wait
```

Use database/user `hazel` and password `hazel-dev-only`. This credential is
for the local development container only.

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

Hazel v0.1 is strictly read-only. The expanded panel reserves a visible action
area for future guarded inspection and cancellation workflows, but those
controls are disabled.

## Privacy and safety

- No telemetry or external service
- No passwords in Omarchy settings or Hazel-owned files
- No writes to the monitored database
- Active query text is session-only, whitespace-normalized, and literal-masked
- Fixed SQL shipped with the plugin; connection fields are passed through
  environment variables, not interpolated into SQL

## License

MIT
