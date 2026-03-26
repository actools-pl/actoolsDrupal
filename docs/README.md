# Actools — Drupal 11 Enterprise Installer

Production-grade Drupal 11 stack installer for Ubuntu 24.04.  
Solves the compatibility problems that plague manual Docker setups.

**Live example:** [feesix.com](https://feesix.com)

---

## What it solves

Every team running Drupal 11 with Docker hits the same walls:

- MariaDB 11.4 dropped `mysqladmin` and `mysql` — healthchecks break silently
- Docker Compose v2 tries to pull locally-built images from Docker Hub — fails with 403
- XeLaTeX in Docker is a dependency nightmare — library paths, host mounts, broken builds
- Caddyfile syntax changed in 2.8 — inline log blocks rejected
- `DB_ROOT_PASS` writeback breaks on lines with trailing comments

**Actools v9.2 fixes all 8 of these.** Documented, tested, production-proven.

---

## Quick Start
```bash
# 1. Clone the repo
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal

# 2. Configure
cp actools.env.example actools.env
# Edit actools.env — set BASE_DOMAIN, DRUPAL_ADMIN_EMAIL, DB_ROOT_PASS

# 3. Install
sudo ./actools.sh fresh
```

That's it. Drupal 11 + MariaDB 11.4 + Caddy 2.8 + Redis + XeLaTeX worker
fully configured and running in under 30 minutes.

---

## Stack

| Component | Version | Notes |
|-----------|---------|-------|
| Drupal | 11 | PHP 8.3 FPM |
| MariaDB | 11.4 | InnoDB tuned, slow query log |
| Caddy | 2.8 | Custom build with caddy-ratelimit |
| Redis | 7 | LRU eviction |
| XeLaTeX | texlive | Self-contained inside worker container |
| PHP | 8.3 | OPcache configured |

---

## CLI
```bash
actools status          # Container health
actools health          # HTTP + /health endpoint check
actools pdf-test        # XeLaTeX test inside worker container
actools storage-test    # S3 PUT/GET/DELETE round-trip
actools storage-info    # Provider, bucket, endpoint summary
actools cost-optimize   # Memory usage vs limits (Phase 2)
actools backup          # Run backup now
actools restore-test    # Verify latest backup integrity
actools drush prod cr   # Run drush in prod environment
actools slow-log prod   # PHP-FPM slow request log
actools redis-info      # Redis memory usage
actools worker-status   # Drupal queue status
actools logs            # Stream all container logs
```

---

## S3 Storage

Supports AWS, Backblaze B2, Wasabi, and any S3-compatible endpoint.
Provider is auto-detected from the endpoint URL.
```bash
# actools.env
ENABLE_S3_STORAGE=true
STORAGE_PROVIDER=backblaze
S3_ENDPOINT_URL=https://s3.us-west-000.backblazeb2.com
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

Credentials are injected via Docker environment variables.
They are never written to Drupal's config system or config exports.

---

## XeLaTeX / PDF Generation

XeLaTeX runs self-contained inside the worker container.
No host packages needed. No library path fragility.
```bash
# Test it
actools pdf-test

# Future: move to remote service
XELATEX_MODE=remote
XELATEX_ENDPOINT=http://your-xelatex-service:8081
```

---

## Architecture
```
actools/
├── core/           Engine: bootstrap, state, secrets, validate
├── modules/
│   ├── host/       System: packages, kernel, swap, firewall, docker
│   ├── stack/      Docker: compose, caddyfile, images, mycnf
│   ├── db/         MariaDB: wait, credentials, backup_user
│   ├── drupal/     Install: prepare → provision → secure
│   ├── storage/    S3: s3fs, settings_inject
│   └── worker/     XeLaTeX: xelatex, queue
├── cli/commands/   CLI: health, backup, storage, worker, restore
├── cron/           Scheduled: backup, stats collection
└── tests/          bats test suite — 21 tests, 0 failures
```

The `install_env()` monolith from v9.2 is now three independent stages:
- **prepare** — database + filesystem
- **provision** — Composer + Drupal site:install
- **secure** — trusted_host_patterns + S3 injection + FPM config

Each stage is idempotent. A failed Composer install can be resumed
with `sudo ./actools.sh resume prod --stage=provision` without
recreating the database.

---

## CI

Every push runs:
- ShellCheck on all `.sh` files
- 21 bats unit tests (core/validate, core/secrets)

[![Lint and Test](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml/badge.svg)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml)

---

## Roadmap

| Phase | Status | What |
|-------|--------|------|
| Phase 1 | ✅ Complete | Modular refactor, bats tests, CI |
| Phase 2 | 🔜 Next | Self-healing healthd, observability, cost-optimize |
| Phase 3 | Planned | Preview environments, zero-downtime migrations, CI/CD generation |
| Phase 4 | Future | AI-native dev environment, edge workers |

---

## Requirements

- Ubuntu 24.04
- 2GB RAM minimum (4GB+ recommended for XeLaTeX)
- 20GB disk minimum
- DNS A records pointing to server before install
