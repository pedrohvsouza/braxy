# Backend

Built with [Saci](https://github.com/rails-crystal/saci) — a
Rails-compatible web framework for Crystal.

## Quick start

```sh
bin/setup          # shards install + db:migrate + db:seed
bin/dev            # saci serve --watch on http://127.0.0.1:3000
bin/doctor         # pre-flight deployment checks
```

The health endpoint answers `GET /up` with `200 OK`; point container
and load-balancer probes at it.

## Everyday commands

| Command | What it does |
| --- | --- |
| `bin/saci ...` | Project-local wrapper around the global `saci` binary (args pass through, including `--`). |
| `bin/setup` | Installs shards, runs migrations, then seeds. `SKIP_SEED=1 bin/setup` skips seeding. |
| `bin/dev` | `saci serve --watch`; extra args go to `saci serve` (e.g. `bin/dev --port 4000`). |
| `bin/ci` | Runs `config/ci.cr` through `saci ci` when available, else `crystal spec`. Set `SACI_EXECUTION_CONTEXT=1` (or pass `--execution-context`) to add `-Dexecution_context`. |
| `bin/doctor` | Checks `SECRET_KEY_BASE`, the database URL and writable `storage/`, `log/`, `tmp/`. |
| `bin/docker-entrypoint` | Prepares the database (`saci db:migrate` or the release `bin/saci-migrate`) and then execs its arguments. |
| `bin/kamal` | Wrapper for Kamal 2 (`bin/kamal setup`, `bin/kamal deploy`); see `config/deploy.yml`. |
| `bin/systemd` | Prints `deploy/backend.service`; `bin/systemd --install` copies it to `/etc/systemd/system`. |
| `bin/thrust` | Documentation only: Saci has no bundled proxy. Put Caddy/nginx/Kamal's proxy (or a separately installed Thruster) in front of `saci serve`. |

Direct framework commands still work:

```sh
shards install
saci generate model Post title:string
saci db:migrate
saci db:seed
saci test
saci serve
```

## Configuration files

Saci keeps working with env vars and no YAML. The generated files are
the declarative, per-`APP_ENV` surface (G147/G148):

| File | Read with | Notes |
| --- | --- | --- |
| `config/database.yml` | `Saci.config_for(:database)` / `Saci::ConfigFile.database_url` | `development`/`test`/`staging`/`production`, pool, optional replicas/cache/queue/cable examples. |
| `config/cache.yml` | `Saci.config_for(:cache)` | `memory` by default; Redis example in comments. |
| `config/queue.yml` | `Saci.config_for(:queue)` | Maps to `Saci::Job.queue_adapter` (`:async`, `:test`, `:db`, ...). |
| `config/cable.yml` | `Saci.config_for(:cable)` | In-process default; Redis example for multi-process. |
| `config/recurring.yml` | `Saci.config_for(:recurring)` | Descriptive task list; register blocks with `Saci::Recurring`. |
| `config/storage.yml` | `Saci.config_for(:storage)` | Local disk under `storage/`; S3 keys documented. |
| `config/server.yml` | `Saci::Deploy::ServerConfig` | Host/port/threads/timeouts; `config/server.cr` applies `HOST`/`PORT` and `SACI_*` overrides at boot. |

Example:

```crystal
db = Saci.config_for(:database)
db[:adapter].as_s                 # string and symbol keys both work
Saci::ConfigFile.database_url     # URL assembled from the current section
```

Files may use `<%= ENV["NAME"] %>` or
`<%= ENV.fetch("NAME", "default") %>`; only those forms are
interpolated (there is no runtime ERB). Delete any file and Saci falls
back to its env-var defaults.

## Operations and deployment

- **Graceful shutdown.** `src/backend.cr` calls
  `listen_gracefully`, which traps `SIGTERM`/`SIGINT`, stops accepting
  connections, waits for in-flight requests up to
  `SACI_SHUTDOWN_TIMEOUT` (default 10s), then runs shutdown hooks.
  Plain `Saci::Application#listen` keeps its original behaviour.
- **Server model.** Crystal's stdlib HTTP server is single-process and
  has no Puma-style cluster/workers. `SACI_THREADS` maps to Crystal
  execution contexts and only takes effect when compiled with
  `-Dexecution_context` (`saci serve --mt`, `bin/dev --mt`). For more
  capacity run multiple processes behind a proxy or scale containers.
- **Kamal 2.** `config/deploy.yml` uses the image built by the
  `Dockerfile`, exposes port 3000, and probes `/up`. `bin/kamal` is a
  thin wrapper; Kamal's proxy handles TLS/HTTP2 outside the app.
  Secrets belong in `.kamal/secrets` as env-var references (or your
  password manager's command), never literal values.
- **systemd.** `deploy/backend.service` is a ready-to-edit unit;
  `bin/systemd` prints it and `bin/systemd --install` installs it.
  Keep `TimeoutStopSec` above the app's shutdown timeout.
- **Docker restart policy.** For plain Docker, use
  `docker run --restart unless-stopped` so the process restarts after
  a crash; Kamal/systemd already restart failed units.
- **Thruster.** Saci does not bundle a proxy. See
  `docs/thruster.md` for supported topologies and why `bin/thrust` is
  documentation, not an implementation.

## Layout

- `src/<app>.cr` — boot file. There is deliberately **no `config.ru`**:
  Saci is not Rack-based. This file (and `bin/saci`) is the entrypoint.
- `config/environments/*.cr` — per-environment settings, loaded by a
  require glob.
- `config/server.cr` — server settings loaded explicitly by the boot
  file (it is not an initializer).
- `config/initializers/*.cr` — app initializers, also loaded by glob
  (`require "../config/initializers/*"`). The generated files are
  comment-only examples so a fresh app always compiles.
- `config/locales/*.yml` — I18n dictionaries.
- `config/*.yml` — declarative per-environment settings (see above).
- `config/ci.cr` — local CI steps (`Saci::CI.step` / `Saci::CI.run`).
- `public/` — static error pages and `robots.txt`. Serve this directory
  with Saci's static middleware when the framework build provides it;
  otherwise mount it behind your reverse proxy. The `/up` route is
  dynamic and lives in `src/controllers/health_controller.cr`.
- `spec/{controllers,models,mailers,integration,fixtures}/` — the
  Crystal equivalent of Rails' `test/` tree (`crystal spec` runs it).
- `db/migrate/` + `db/migrations.cr` — migrations and their manifest.
- `storage/`, `log/`, `tmp/pids/`, `vendor/`, `script/` — runtime and
  auxiliary directories. `.gitkeep` keeps empty ones in Git.
- `bin/` — project binstubs (executable).
- `deploy/`, `docs/`, `.kamal/` — systemd unit, deployment docs and
  Kamal secrets template.
- `Dockerfile`, `.dockerignore`, `.github/workflows/ci.yml` — deployment
  and CI defaults. `.tool-versions` pins the Crystal version.

## Docker

```sh
docker build -t backend .
docker run --rm -p 3000:3000 --restart unless-stopped \
  -e SECRET_KEY_BASE="$(saci secret)" \
  -e DATABASE_URL="postgres://..." \
  backend
```

The image is multi-stage (Crystal build stage + slim Debian runtime),
runs as the non-root `saci` user, prepares the database in the
entrypoint, and exposes port 3000. `STOPSIGNAL SIGTERM` lets the app
drain requests. `SKIP_DB_PREPARE=1` skips the migrate step. The
generated `shard.yml` points at your local Saci checkout; update that
path (or vendor/publish Saci) before building in CI or on another
machine.

## Notes

- There is no `Rakefile`: use the documented `saci` tasks
  (`saci db:migrate`, `saci db:seed`, `saci routes`, `saci test`, ...).
- Set `SECRET_KEY_BASE` in production. `config/credentials.yml.enc`
  plus the gitignored `config/master.key` is the local alternative.
- Run `bin/doctor` before the first deploy and after changing secrets,
  database URLs or volume mounts.
