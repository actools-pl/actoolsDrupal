# Architecture

> Applies to: Actools v14.0+

---

## How it's built

Actools is a bash platform with a staged install spine (`actools.sh`) and a separate operator CLI (`/usr/local/bin/actools`). The install spine (`actools.sh`) is the live authority for provisioning; it is monolithic today and is being extracted into per-stage modules (Phase 0 seam hardening). The CLI dispatcher routes operator commands to command handlers in `cli/commands/`.

```
/home/actools/
│
├── actools.sh              installer — runs once on fresh server
├── actools.env             all configuration (gitignored)
├── docker-compose.yml      stack definition (gitignored — contains secrets)
├── Caddyfile               web server config
│
├── core/                   engine
│   ├── bootstrap.sh        environment load, validation, secret injection
│   ├── state.sh            .actools-state.json read/write
│   ├── secrets.sh          credential generation and storage
│   └── validate.sh         pre-flight checks before any operation
│
├── modules/                live install modules (6 — sourced/executed on the install path)
│   ├── audit/              actools audit — security/config audit (CLI command; lib/*.sh)
│   ├── backup/             scheduled DB-backup cron (cron.sh); the PITR/binlog/encrypted-backup files here are unwired drafts — see the file-level inventory in runtime-authority-map.md
│   ├── db/                 MariaDB: wait-for-ready, credentials, backup user
│   ├── drupal/             Drupal install: provision (prepare.sh/secure.sh are unwired extractions)
│   ├── host/               system setup (packages, kernel, swap, UFW, Docker)
│   └── stack/              Docker Compose, Caddyfile, images, my.cnf
│
├── experimental/           quarantined 4.5-design seeds (7) — committed but UNWIRED; NOT in the standard install
│   ├── ai/                 AI assistant (Ollama, codebase indexing)
│   ├── compliance/         GDPR: export, delete, audit, report
│   ├── dr/                 disaster recovery: immortalize, resurrect
│   ├── network/            Cloudflare tunnel setup
│   ├── observability/      Prometheus, Grafana, exporters
│   ├── preview/            branch environments: create, list, destroy
│   └── security/           RBAC: sudoers rules, audit wrapper
│
├── cli/
│   ├── actools             main dispatcher (case statement)
│   └── commands/           individual command handlers
│
├── cron/                   scheduled jobs (backup)
├── certs/                  TLS certificates (private keys gitignored)
├── templates/              Dockerfiles, CI workflows, settings.php template
├── tests/                  236 bats tests (24 files)
└── docs/                   this documentation
```

> Note: `modules/` holds the 6 live modules the installer wires; `experimental/` holds the 7 quarantined 4.5-design seeds (committed but unwired — not in the standard install). Some files **inside** live modules are themselves unwired drafts (e.g. the `backup/` PITR cluster). The authoritative live-vs-experimental map — including file-level wiring inside the live modules — is [`architecture/runtime-authority-map.md`](architecture/runtime-authority-map.md).

---

## The Docker stack

Six containers on a shared `actools_net` bridge network:

```
Internet → Caddy (80/443) → php_prod (9000) → db (3306)
                                            → redis (6379)
                          → worker_prod     → db
                                            → redis
```

| Container | Image | Role |
|---|---|---|
| `actools_caddy` | custom build | reverse proxy, TLS, HTTP/3, rate limiting |
| `actools_php_prod` | drupal:11-php8.3-fpm | PHP-FPM, Drupal application |
| `actools_worker_prod` | actools_worker:latest | XeLaTeX PDF generation, Drupal queue |
| `actools_db` | mariadb:11.4 | database, binary logging, TLS |
| `actools_redis` | redis:7-alpine | cache, session storage |
| `actools_prometheus` + exporters *(optional observability stack — not in the default install)* | prom/* | metrics collection |
| `actools_grafana` *(optional — not in the default install)* | grafana/grafana | dashboards |

---

## State machine

Actools tracks installation state in `.actools-state.json`:

```json
{
  "envs": { "prod": true },
  "db_passes": { "prod": "<generated at install>" },
  "backup_user_pass": "<generated at install>"
}
```

The installer is idempotent — re-running `actools.sh fresh` on an already-installed server skips completed phases.

---

## Security model

- **No secrets in git** — `actools.env` and `docker-compose.yml` are gitignored
- **No secrets in images** — credentials injected at runtime via Docker environment
- **No secrets in Drupal config** — S3, Redis credentials use `getenv()` in `settings.php`
- **Daily backups** — daily database dumps with checksum verification (encrypted backup deployment planned — see [`../ROADMAP.md#encrypted-backups`](../ROADMAP.md#encrypted-backups))
- **RBAC** *(planned hardening tier — not the standard install)* — three role users (`actools-dev`, `actools-ops`, `actools-viewer`) with scoped sudo rules
- **Audit trail** — the `actools audit` command is shipped; per-invocation logging to `logs/audit.log` is part of the planned hardening tier, not the standard install

---

## Adding a module

```bash
mkdir /home/actools/modules/mymodule
cat > /home/actools/modules/mymodule/mymodule.sh << 'EOF'
#!/usr/bin/env bash
my_command() {
  echo "doing something"
}
EOF

# Source it in the CLI dispatcher
# Add to cli/actools (the canonical CLI source):
#   source "${INSTALL_DIR}/modules/mymodule/mymodule.sh"
#   my_command) my_command ;;
```

---

*Back to [docs index](README.md)*
