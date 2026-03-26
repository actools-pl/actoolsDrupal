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
| MariaDB | 11.4 | InnoDB tuned, slow query log, TLS 1.3 |
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

# Preview Environments
actools branch feature-123        # Spin up isolated preview environment
actools branch --list             # List active preview environments
actools branch --destroy feature-123  # Destroy preview environment
actools branch --cleanup          # Remove previews older than 7 days

# Database & Recovery
actools migrate [env]             # Show pending migrations + table sizes
actools migrate --apply [env]     # Apply with pre-migration backup
actools migrate --rollback [env]  # Rollback to pre-migration snapshot
actools migrate --point-in-time "YYYY-MM-DD HH:MM:SS"  # Point-in-time recovery

# Backup
actools backup db                 # Run full database backup now
actools backup binlogs            # Rotate and archive binary logs
actools backup status             # Backup status + binlog position

# Disaster Recovery
actools immortalize               # Snapshot complete server state to DNA
actools resurrect --dna <file> --key <key>  # Restore on fresh server

# GDPR Compliance
actools gdpr export <email>       # Export all user data (Art. 15)
actools gdpr delete <email>       # Delete user + content (Art. 17)
actools gdpr audit  <email>       # Audit trail for a user
actools gdpr report               # Full compliance status report

# CI/CD Generation
actools ci --generate             # Generate GitHub Actions pipelines
actools ci --generate --platform=gitlab  # Generate GitLab CI pipeline

# Backup & Restore
actools backup                    # Run backup now (DB + files)
actools restore-test              # Verify latest backup integrity
actools restore [env] [file]      # Restore with confirmation

# Drupal
actools drush [env] [cmd]         # Run drush command
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

# AI Assistant
actools ai "question"             # Ask about your codebase
actools ai explain <file>         # Explain a specific module
actools ai review --security      # Security review
actools ai review --performance   # Performance review
actools ai context                # Rebuild codebase index
```

---

## Phase 4.5 — Enterprise Hardening

v11.2.0 adds six enterprise-grade capabilities. See [full documentation →](docs/04-enterprise-hardening.md)

| Capability | What it gives you |
|---|---|
| **Encrypted backups** | Daily DB dumps + hourly binlog rotation, age-encrypted at rest |
| **Point-in-Time Recovery** | `actools migrate --point-in-time "..."` — restore to any second |
| **RBAC + audit trail** | `actools-dev`, `actools-ops`, `actools-viewer` roles, every command logged |
| **MariaDB TLS 1.3** | `require_secure_transport=ON`, TLS_AES_256_GCM_SHA384 |
| **DNA resurrection** | Full server blueprint snapshot — rebuild from bare metal in <15 min |
| **GDPR tools** | Art.15 export, Art.17 erasure, compliance report |

**Recovery targets:**
- RPO: ~1 hour (binlog rotation interval)
- RTO: <15 minutes (DNA + dump restore + binlog replay)

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

## Observability
```bash
docker compose -f docker-compose.observability.yml up -d
ssh -L 3000:localhost:3000 actools@yourdomain.com
# http://localhost:3000 (admin / actools_grafana)
```

Pre-built dashboards: Node Exporter Full, cAdvisor, Redis.

---

## S3 Storage
```bash
ENABLE_S3_STORAGE=true
STORAGE_PROVIDER=backblaze        # aws | backblaze | wasabi | custom
S3_ENDPOINT_URL=https://s3.us-west-000.backblazeb2.com
S3_BUCKET=your-bucket-name
```

---

## Security

- **Quantum-safe TLS** — HTTP/3 with X25519Kyber768 post-quantum key exchange
- **MariaDB TLS 1.3** — `require_secure_transport=ON`, TLS_AES_256_GCM_SHA384
- **Encryption at rest** — age-encrypted backups, DNA snapshots
- **RBAC** — role-scoped access (dev/ops/viewer) with full audit trail
- **HSTS** — max-age=31536000 with includeSubDomains
- **Rate limiting** — Caddy caddy-ratelimit on login endpoints
- **Zero secrets in git** — all credentials via env vars, private keys gitignored

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
│   ├── backup/     PITR: binlog rotation, full dumps, restore
│   ├── security/   RBAC: sudoers, audit wrapper
│   ├── compliance/ GDPR: export, delete, audit, report
│   ├── dr/         Disaster recovery: immortalize, resurrect
│   └── ai/         AI assistant (Ollama + deepseek-coder)
├── cli/            Main dispatcher + 25+ commands
├── cron/           Backup, binlog rotation, DNA snapshots
├── certs/          MariaDB SSL certificates (keys gitignored)
└── tests/          21 bats tests — all passing
```

---

## vs Managed Drupal Hosts

| Feature | Actools | Acquia | Pantheon |
|---------|---------|--------|----------|
| Monthly cost | ~€10 VPS | €134–€1000+ | €35–€800+ |
| Preview environments | ✅ | ✅ | ✅ Multidev |
| Point-in-time recovery | ✅ | ✅ paid | ✅ paid |
| GDPR tools | ✅ built-in | ❌ | ❌ |
| Encryption at rest | ✅ age | varies | varies |
| XeLaTeX / PDF workers | ✅ native | ❌ | ❌ |
| Observability (Grafana) | ✅ | paid add-on | paid add-on |
| Quantum-safe TLS | ✅ | ❌ | ❌ |
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
| Phase 4.5 | ✅ Complete | Enterprise hardening — PITR, RBAC, TLS, DNA, GDPR |
| Phase 5 | 🔜 Planned | Multi-tenancy — multiple Drupal sites per server |
| Phase 6 | 🔮 Future | GitHub webhook automation — PR → preview, merge → deploy |

---

## Requirements

- Ubuntu 24.04
- 2GB RAM minimum (4GB+ recommended)
- 20GB disk minimum
- DNS A records pointing to server before install
- `*.yourdomain.com` wildcard DNS for preview environments

---

## Documentation

| # | Guide | Description |
|---|-------|-------------|
| 01 | [Drupal settings.php Hardening](docs/01-drupal-settings-hardening.md) | Public vs private files, hardened settings.php, session security, Redis config |
| 02 | [Troubleshooting & Security](docs/02-troubleshooting-performance-security.md) | MariaDB, Caddy, XeLaTeX — debugging, performance tuning, hardening |
| 03 | [Prometheus & Grafana Guide](docs/03-prometheus-grafana-guide.md) | Dashboard usage, PromQL queries, alerts, retention |
| 04 | [Enterprise Hardening (Phase 4.5)](docs/04-enterprise-hardening.md) | PITR, RBAC, MariaDB TLS, DNA resurrection, GDPR tools |
