# Changelog

All notable changes to Actools are documented here.

---

## [v10.0.2] — 2026-03-26

### Fixed
- CI: Added ShellCheck exclusions for SC2043, SC2012, SC1090 in cli/commands
- CI: Fixed bats test paths for GitHub Actions compatibility

## [v10.0.1] — 2026-03-26

### Added
- Phase 1 complete: 32 modules extracted from monolith
- 21 bats tests — all passing (core/validate, core/secrets)
- GitHub Actions CI: ShellCheck + bats on every push
- modules/preflight/: dns.sh, disk.sh, ram.sh
- tests/core/: validate_test.bats, secrets_test.bats

## [v10.0.0] — 2026-03-26 — Phase 1 Complete

### Added
- core/bootstrap.sh — variable init, logging, lock file
- core/state.sh — JSON state management
- core/secrets.sh — password generation and writeback
- core/validate.sh — env, S3, XeLaTeX, disk validation
- modules/host/ — packages, kernel, swap, firewall, docker, logrotate
- modules/stack/ — mycnf, caddyfile, images, compose
- modules/db/ — wait, credentials, backup_user
- modules/drupal/ — prepare, provision, secure (3-stage install)
- modules/storage/ — s3fs, settings_inject
- modules/worker/ — xelatex, queue
- cli/commands/ — health, backup, worker, storage, restore, update
- cron/ — backup, stats collection
- docs/phases/ — phase documentation

### Architecture
- install_env() split into 3 independent stages: prepare → provision → secure
- Each stage is idempotent and independently retryable
- Failed installs can resume from any stage without re-running earlier steps
- All Dockerfiles moved to template variables — no more bash heredoc embedding

---

## [v9.2] — 2026-03-25 — Production Hardening

### Fixed (8 compatibility fixes)

1. **MariaDB 11.4 healthcheck** — `mysqladmin` removed in MariaDB 11.4.
   Replaced with `healthcheck.sh --connect --innodb_initialized`

2. **MariaDB 11.4 client** — `mysql` binary removed in MariaDB 11.4.
   All `mysql` calls replaced with `mariadb` throughout installer and CLI

3. **mariadb-dump** — backup cron used non-existent `mariadump` command.
   Fixed to `mariadb-dump` — nightly backups were silently failing before this fix

4. **pull_policy: never** — Docker Compose was attempting to pull locally-built
   `actools_caddy:custom` and `actools_worker:latest` from Docker Hub registry.
   Added `pull_policy: never` to both services

5. **Caddyfile log block** — Caddy 2.8 rejected inline `log { level INFO }`.
   Expanded to multi-line block format

6. **DB log directory ownership** — MariaDB (UID 999) could not write slow.log.
   Pre-create `/logs/db/slow.log` with correct ownership before container starts

7. **wait_db subshell** — `DB_ROOT_PASS` was unbound under `set -u` in spawned
   bash subshell. Rewrote as a plain loop without `timeout bash -c`

8. **Secret writeback** — `DB_ROOT_PASS=  # comment` lines were not matched by
   writeback regex. Fixed with `grep -qP` to strip trailing comments

### Added
- `version: '3.9'` removed from docker-compose.yml (obsolete in Compose v2)
- Selective `docker compose pull` — skips locally-built images
- Per-run install logs in `~/logs/install/`
- `actools log-dir` CLI command

---

## [v9.1] — Prior Release

- S3FS config keys corrected to `$config['s3fs.settings']`
- Backup cron: added `cd "${INSTALL_DIR}"` before docker compose calls
- storage-info CLI: re-sources actools.env at runtime
- CDN + endpoint injected in settings.php
- Lock file: touch before exec to prevent Permission denied on re-run

## [v9.0] — Prior Release

- XeLaTeX moved inside worker container (self-contained, no host mounts)
- Multi-provider S3: aws, backblaze, wasabi, custom
- Provider auto-detection from S3_ENDPOINT_URL hostname
- S3-aware backup cron
- actools storage-test, storage-info, migrate CLI commands

---

## [v11.0.0] — 2026-03-26 — Phase 4: AI-Native Dev Environment

### Added
- Ollama 0.18.3 installed as system service
- deepseek-coder:1.3b model (776MB, CPU-optimized)
- `actools ai <question>` — ask anything with full codebase context
- `actools ai explain <file>` — explain any module file
- `actools ai review --security` — security vulnerability review
- `actools ai review --performance` — performance review
- `actools ai context` — rebuild codebase index
- modules/ai/assistant.sh — AI module with Ollama API integration
- Context builder indexes all core/, modules/, cli/ bash files
- Low temperature (0.2-0.3) for precise, factual code answers

---

## [v10.6.0] — 2026-03-26 — Phase 3 Complete

### Added
- `actools migrate --plan` — shows pending Drupal updates + table sizes
- `actools migrate --apply` — pre-backup + drush updb + health check
- `actools migrate --rollback` — one-command rollback to pre-migration snapshot
- gh-ost 1.1.8 installed — online schema changes for tables >100k rows
- modules/migrate/migrate.sh — zero-downtime migration module

## [v10.5.0] — 2026-03-26

### Added
- `actools ci --generate` — generates 3 GitHub Actions workflows
  - github-test.yml — PHP CodeSniffer, PHPStan, composer validate
  - github-deploy.yml — backup + pull + updb + health check
  - github-security.yml — weekly composer audit + Drupal advisories
- templates/ci/ — CI workflow templates with variable substitution

## [v10.4.0] — 2026-03-26

### Added
- `actools branch <name>` — create isolated preview environment
- `actools branch --list` — list active previews
- `actools branch --destroy <name>` — clean destroy (DB, container, vhost)
- `actools branch --cleanup` — auto-remove previews older than 7 days
- Preview auto-cleanup daily cron
- modules/preview/branch.sh — full preview environment lifecycle
- Requires wildcard DNS: *.yourdomain.com

## [v10.3.1] — 2026-03-26

### Added
- Quantum-safe TLS — HTTP/3 (h1 h2 h3) enabled in Caddy 2.8
- X25519Kyber768 post-quantum key exchange active
- SSL Labs rating: Forward Secrecy ROBUST

### Fixed
- Backup cron: mariadb-dump correct password, removed duplicate BACKUP_PASS

## [v10.2.0] — 2026-03-26

### Added
- Prometheus + Grafana observability stack
- 3 pre-built dashboards: Node Exporter Full, cAdvisor, Redis
- docker-compose.observability.yml — separate compose file
- Prometheus data source auto-configured via API

## [v10.1.0] — 2026-03-26

### Added
- `actools health --verbose` — full system health report
- `actools health --cost` — memory optimization report
- `actools cost-optimize` — reads real Docker stats, suggests memory changes
- modules/health/checks.sh — container, TLS, disk, MariaDB, Redis checks
- Worker container stable — loop with sleep instead of crash-restart
