# Command reference

Every command in `actools.sh` and the `actools` CLI, grouped by stage and frequency of use. For the curated short list, see [`operator-handbook.md`](operator-handbook.md).

Run `actools help` for a quick on-server reference. Run `actools help advanced` for the full list.

---

## Installer modes (`actools.sh`)

These run before or during install. Most operators use them once, in order.

| Command | What it does |
|---|---|
| `sudo ./actools.sh init --domain <d> --email <e> [--site-name "<n>"] [--force]` | Creates `actools.env` from the template. Refuses to overwrite without `--force`. |
| `sudo ./actools.sh preflight` | Readiness checks (OS, env, RAM, disk, ports, DNS, install state). |
| `sudo ./actools.sh install` | Build the full stack. Calls `fresh` internally; both work. |
| `sudo ./actools.sh fresh` | Legacy alias of `install`. Prints a soft deprecation hint. |
| `sudo ./actools.sh update` | Pre-snapshot → pull → `drush updb` → caddy reload. |
| `sudo ./actools.sh env <dev\|stg\|prod>` | Install one environment (multi-env mode only). |
| `sudo ./actools.sh handoff` | Re-print the post-install summary. |
| `sudo ./actools.sh dry-run` | Show what `install` would do without doing it. |
| `./actools.sh help` | Quick usage. No sudo needed. |
| `./actools.sh --version` | Print the version. |

Exit codes for `preflight`: `0` ready, `1` failures, `2` warnings only.

---

## Doctor — daily health check

| Command | What it does | Exit |
|---|---|---|
| `actools doctor` | Nine surface-level checks: site, TLS, containers, DB, Redis, disk, backups, restore-test recency, Drupal bootstrap. | 0 OK / 1 fail / 2 warn |
| `actools doctor --deep` | In development — will add trend regression, drift detection, forecasting, anomaly detection. | 2 (gate notice) |

---

## Common operations

| Command | What it does |
|---|---|
| `actools status` | Container status (`docker compose ps`). |
| `actools logs [svc]` | Stream logs; omit service for all. |
| `actools restart [svc]` | Restart one or all containers. |
| `actools backup` | Run a backup now. |
| `actools update` | Same as `sudo ./actools.sh update`. |
| `actools drush <env> <cmd...>` | Run any drush command in a container. |
| `actools shell [svc]` | Open a bash shell in a container. |
| `actools console <env>` | Drush PHP console (REPL). |

---

## Backups, restore, and recovery

| Command | What it does |
|---|---|
| `actools backup` | Run the daily backup job now (gzip dump; encryption planned — see [`../ROADMAP.md#encrypted-backups`](../ROADMAP.md#encrypted-backups)). |
| `actools restore-test` | Verify the latest backup actually restores. |
| `actools restore <env> [file]` | Restore with overwrite confirmation. |

Encrypted backups, point-in-time recovery (PITR), and DNA resurrection are **planned/experimental and not available in the standard install** — see [`../ROADMAP.md`](../ROADMAP.md) and the design notes under [Experimental](#experimental--not-yet-shipped).

---

## TLS and network

| Command | What it does |
|---|---|
| `actools tls-status` | Certificate expiry dates per domain. |
| `actools caddy-reload` | Zero-downtime Caddy config reload. |
| `actools tunnel [status\|restart\|logs]` | Cloudflare tunnel subcommands. |

---

## Worker and PDF

| Command | What it does |
|---|---|
| `actools worker-status` | Drupal queue depth and status. |
| `actools worker-logs` | Stream worker container logs. |
| `actools worker-run` | Trigger the queue worker manually. |
| `actools pdf-test` | Verify XeLaTeX compilation in the worker. |

---

## Storage

| Command | What it does |
|---|---|
| `actools storage-test` | S3 PUT/GET/DELETE round-trip. |
| `actools storage-info` | Provider, bucket, endpoint, CDN host. |
| `actools migrate` | XeLaTeX-remote migration guide (read-only). |

---

## Diagnostics

| Command | What it does |
|---|---|
| `actools stats` | Live `docker stats`. |
| `actools slow-log [env]` | PHP-FPM slow request log. |
| `actools redis-info` | Redis memory and hit rate. |
| `actools oom` | Recent OOM events from dmesg. |
| `actools log-dir` | Install log directory and latest log. |
| `actools health` | Legacy HTTP/health check (prefer `doctor`). |

---

## Advanced (shipped)

| Surface | Doc |
|---|---|
| `actools audit` | [`advanced.md`](advanced.md#audit) |

---

## Experimental — not yet shipped

The modules below exist in the source tree as future/experimental work. They are **not** registered as `actools` commands: running them returns *unknown command*. They are listed here for design reference only; see [`../ROADMAP.md`](../ROADMAP.md) for status.

| Planned surface | Design notes |
|---|---|
| Encrypted backups / point-in-time recovery | [`advanced.md`](advanced.md#point-in-time-recovery) |
| DNA snapshot / resurrection (`immortalize` / `resurrect`) | [`advanced.md`](advanced.md#dna-resurrection) |
| GDPR tooling (`gdpr export/delete/audit/report`) | [`advanced.md`](advanced.md#gdpr-compliance) |
| Preview environments (`branch`) | [`advanced.md`](advanced.md#preview-environments) |
| CI/CD generation (`ci --generate`) | [`advanced.md`](advanced.md#cicd-generation) |
| AI assistant (`ai`) | [`advanced.md`](advanced.md#ai-assistant) |

---

*For a moved-or-renamed command, see the [legacy CLI reference](cli-reference.md) — preserved for inbound links.*
