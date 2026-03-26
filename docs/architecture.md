# Architecture

> Applies to: Actools v11.2.0+

---

## How it's built

Actools is a modular bash platform. Each capability lives in its own module directory with a clear boundary. The CLI dispatcher (`/usr/local/bin/actools`) sources modules and routes commands — it never contains business logic itself.

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
├── modules/
│   ├── host/               system setup (packages, kernel, swap, UFW, Docker)
│   ├── stack/              Docker Compose, Caddyfile, images, my.cnf
│   ├── db/                 MariaDB: wait-for-ready, credentials, backup user
│   ├── drupal/             Drupal install: prepare → provision → secure
│   ├── storage/            S3: s3fs mount, settings injection
│   ├── worker/             XeLaTeX worker: build, queue integration
│   ├── health/             health checks, self-healing remediation
│   ├── observability/      Prometheus, Grafana, exporters
│   ├── preview/            branch environments: create, list, destroy
│   ├── migrate/            zero-downtime migrations, rollback
│   ├── backup/             PITR: full dumps, binlog rotation, restore
│   ├── security/           RBAC: sudoers rules, audit wrapper
│   ├── compliance/         GDPR: export, delete, audit, report
│   ├── dr/                 disaster recovery: immortalize, resurrect
│   └── ai/                 AI assistant: Ollama, codebase indexing
│
├── cli/
│   ├── actools             main dispatcher (case statement)
│   └── commands/           individual command handlers
│
├── cron/                   scheduled jobs (backup, binlog, DNA snapshots)
├── certs/                  TLS certificates (private keys gitignored)
├── templates/              Dockerfiles, CI workflows, settings.php template
├── tests/                  21 bats tests
└── docs/                   this documentation
```

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
| `actools_prometheus` + exporters | prom/* | metrics collection |
| `actools_grafana` | grafana/grafana | dashboards |

---

## State machine

Actools tracks installation state in `.actools-state.json`:

```json
{
  "version": "11.2.0",
  "installed_at": "2026-03-25T18:00:00Z",
  "domain": "feesix.com",
  "phases_complete": ["host", "stack", "db", "drupal", "storage", "worker"],
  "preview_environments": {}
}
```

The installer is idempotent — re-running `actools.sh fresh` on an already-installed server skips completed phases.

---

## Security model

- **No secrets in git** — `actools.env` and `docker-compose.yml` are gitignored
- **No secrets in images** — credentials injected at runtime via Docker environment
- **No secrets in Drupal config** — S3, Redis credentials use `getenv()` in `settings.php`
- **Encrypted backups** — all dumps and binlogs age-encrypted before storage
- **RBAC** — three role users (`actools-dev`, `actools-ops`, `actools-viewer`) with scoped sudo rules
- **Audit trail** — every CLI invocation logged to `logs/audit.log`

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
# Add to /usr/local/bin/actools-real:
#   source "${INSTALL_DIR}/modules/mymodule/mymodule.sh"
#   my_command) my_command ;;
```

---

*Back to [docs index](README.md)*
