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
