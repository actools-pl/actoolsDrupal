# Actools — Drupal 11 Enterprise Platform

Production-grade Drupal 11 platform installer for Ubuntu 24.04.  
From a single command to a fully monitored, self-healing, observable Drupal stack.

**Live example:** [feesix.com](https://feesix.com)

[![Lint and Test](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml/badge.svg)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml)

---

## What it solves

Every team running Drupal 11 with Docker hits the same walls:

- MariaDB 11.4 dropped `mysqladmin` and `mysql` — healthchecks break silently
- Docker Compose v2 tries to pull locally-built images from Docker Hub — fails with 403
- XeLaTeX in Docker is a dependency nightmare — library paths, host mounts, broken builds
- Caddyfile syntax changed in 2.8 — inline log blocks rejected
- `DB_ROOT_PASS` writeback breaks on lines with trailing comments

**Actools v9.2 fixed all 8 of these.** v10.x turned the installer into a platform.

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

Drupal 11 + MariaDB 11.4 + Caddy 2.8 + Redis + XeLaTeX worker running in under 30 minutes.

---

## Stack

| Component | Version | Notes |
|-----------|---------|-------|
| Drupal | 11 | PHP 8.3 FPM |
| MariaDB | 11.4 | InnoDB tuned, slow query log |
| Caddy | 2.8 | Custom build with caddy-ratelimit, HTTP/3 |
| Redis | 7 | LRU eviction |
| XeLaTeX | texlive | Self-contained inside worker container |
| PHP | 8.3 | OPcache configured |
| Prometheus | latest | 30-day metrics retention |
| Grafana | latest | 3 pre-built dashboards |

---

## CLI — Full Command Reference
```bash
# Health & Monitoring
actools health                    # HTTP check (simple)
actools health --verbose          # Full system health report
actools health --cost             # Memory optimization report
actools cost-optimize             # Detailed cost analysis with recommendations

# Stack Management
actools status                    # Container status
actools logs [svc]                # Stream logs
actools restart [svc]             # Restart a service
actools stats                     # Live Docker resource usage
actools update                    # Pre-snapshot + pull + drush updb

# Preview Environments (Phase 3)
actools branch feature-123        # Spin up isolated preview environment
actools branch --list             # List active preview environments
actools branch --destroy feature-123  # Destroy preview environment
actools branch --cleanup          # Remove previews older than 7 days

# Database Migrations (Phase 3)
actools migrate [env]             # Show pending migrations + table sizes
actools migrate --apply [env]     # Apply with pre-migration backup
actools migrate --rollback [env]  # Rollback to pre-migration snapshot

# CI/CD Generation (Phase 3)
actools ci --generate             # Generate GitHub Actions pipelines
actools ci --generate --platform=gitlab  # Generate GitLab CI pipeline

# Backup & Restore
actools backup                    # Run backup now (DB + files)
actools restore-test              # Verify latest backup integrity
actools restore [env] [file]      # Restore with confirmation

# Drupal
actools drush [env] [cmd]         # Run drush command
actools console [env]             # Drush PHP interactive console
actools shell [svc]               # Bash in container

# Worker & PDF
actools worker-logs               # Stream worker logs
actools worker-status             # Drupal queue status
actools worker-run                # Run queue worker manually
actools pdf-test                  # Test XeLaTeX in worker container

# Storage
actools storage-test              # S3 PUT/GET/DELETE round-trip test
actools storage-info              # Storage provider + configuration

# Network & TLS
actools caddy-reload              # Zero-downtime Caddy config reload
actools tls-status                # TLS certificate expiry dates

# Observability
actools redis-info                # Redis memory usage
actools slow-log [env]            # PHP-FPM slow request log
```

---

## Preview Environments

Every branch gets its own isolated environment:
```bash
actools branch feature-payment
# → Clones prod database
# → Copies docroot
# → Starts isolated PHP container
# → Adds Caddy vhost: feature-payment.yourdomain.com
# → TLS certificate auto-obtained
# → Auto-destroys after 7 days

# Output:
# URL      : https://feature-payment.feesix.com
# Admin    : https://feature-payment.feesix.com/user/login
# Password : <generated>
# Expires  : 2026-04-02
```

---

## Zero-Downtime Migrations
```bash
actools migrate --plan prod       # Shows pending updates + table sizes
actools migrate --apply prod      # Pre-backup → drush updb → health check
actools migrate --rollback prod   # One-command rollback to pre-migration state
```

Large tables (>100k rows) automatically use gh-ost for online schema changes.

---

## CI/CD Generation
```bash
actools ci --generate
# Generates in /tmp/actools-ci-output/.github/workflows/:
#   github-test.yml     → PHP CodeSniffer, PHPStan, composer validate (on every PR)
#   github-deploy.yml   → backup + pull + updb + health check (on merge to main)
#   github-security.yml → composer audit + Drupal advisories (weekly)
```

---

## Observability
```bash
# Enable observability stack
docker compose -f docker-compose.observability.yml up -d

# Access via SSH tunnel
ssh -L 3000:localhost:3000 actools@yourdomain.com
# Then: http://localhost:3000 (admin / actools_grafana)
```

Pre-built dashboards:
- **Node Exporter Full** — CPU, RAM, disk, network
- **cAdvisor** — per-container resource usage
- **Redis** — hit rate, memory, commands/sec

---

## S3 Storage
```bash
# actools.env
ENABLE_S3_STORAGE=true
STORAGE_PROVIDER=backblaze        # aws | backblaze | wasabi | custom
S3_ENDPOINT_URL=https://s3.us-west-000.backblazeb2.com
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

Provider auto-detected from endpoint URL. Credentials injected via Docker env vars — never in Drupal config exports.

---

## Security

- **Quantum-safe TLS** — HTTP/3 with X25519Kyber768 post-quantum key exchange
- **Forward Secrecy — ROBUST** (SSL Labs rating)
- **HSTS** — max-age=31536000 with includeSubDomains
- **Rate limiting** — Caddy caddy-ratelimit on login endpoints
- **Zero secrets in git** — all credentials via env vars, never committed
- **UFW + fail2ban** — SSH rate-limited, ports 80/443/22 only

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
│   ├── worker/     XeLaTeX: xelatex, queue
│   ├── health/     Monitoring: checks, remediation
│   ├── observability/ Prometheus + Grafana
│   ├── preview/    Branch environments
│   ├── migrate/    Zero-downtime migrations
│   └── ai/          AI assistant (Ollama + deepseek-coder)
├── cli/commands/   20+ CLI commands
├── cron/           backup, stats collection
├── templates/      Dockerfiles, CI workflows, Drupal settings
└── tests/          21 bats tests — all passing
```

---


## AI-Native Dev Environment

An AI assistant that understands your actual codebase — not generic advice.
```bash
# Ask anything about your codebase
actools ai "How does the wait_db function work?"
actools ai "What happens when a preview environment is created?"

# Explain a specific module
actools ai explain modules/drupal/provision.sh
actools ai explain modules/preview/branch.sh

# Security review
actools ai review --security

# Performance review
actools ai review --performance

# Rebuild codebase index
actools ai context
```

**Model:** deepseek-coder:1.3b (776MB, runs on CPU)  
**Engine:** Ollama 0.18.3  
**Context:** Your actual codebase — answers reference real function names, line numbers, and implementation details.

---
## vs Managed Drupal Hosts

| Feature | Actools | Acquia | Pantheon |
|---------|---------|--------|----------|
| Monthly cost | ~€10 VPS | €134–€1000+ | €35–€800+ |
| Preview environments | ✅ | ✅ | ✅ Multidev |
| XeLaTeX / PDF workers | ✅ native | ❌ | ❌ |
| Observability (Grafana) | ✅ | paid add-on | paid add-on |
| Quantum-safe TLS | ✅ | ❌ | ❌ |
| Cost optimization CLI | ✅ | ❌ | ❌ |
| Zero-downtime migrations | ✅ gh-ost | ✅ | ✅ |
| CI/CD generation | ✅ | paid | paid |
| AI code assistant | ✅ codebase-aware | ❌ | ❌ |
| Full code ownership | ✅ 100% | ❌ | ❌ |

---

## Roadmap

| Phase | Status | What |
|-------|--------|------|
| Phase 1 | ✅ Complete | Modular refactor, 32 modules, 21 bats tests, CI |
| Phase 2 | ✅ Complete | Health checks, cost-optimize, Grafana, backup hardening, quantum TLS |
| Phase 3 | ✅ Complete | Preview environments, zero-downtime migrations, CI/CD generation |
| Phase 4 | ✅ Complete | AI-native dev environment (Ollama + deepseek-coder) |

---

## Requirements

- Ubuntu 24.04
- 2GB RAM minimum (4GB+ recommended)
- 20GB disk minimum
- DNS A records pointing to server before install
- `*.yourdomain.com` wildcard DNS for preview environments
