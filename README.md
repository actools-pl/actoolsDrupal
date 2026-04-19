# Actools

**€10/month. Enterprise Drupal on your own server. Full code ownership.**

Production-grade Drupal 11 on a €10 Hetzner VPS — monitored, self-healing, enterprise-hardened.  
One command to install. One CLI to operate everything.

**Live:** [feesix.com](https://feesix.com) &nbsp;·&nbsp; [![CI](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml/badge.svg)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml) [![Security Scan](https://img.shields.io/badge/security-trivy-green)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml) [![CodeQL](https://github.com/actools-pl/actoolsDrupal/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/github-code-scanning/codeql)

---

## The problem it solves

Every team running Drupal 11 with Docker hits the same walls — MariaDB 11.4 dropped `mysql` and `mysqladmin` so healthchecks break silently, Docker Compose v2 tries to pull local images from Docker Hub and fails with 403, XeLaTeX is a dependency nightmare, and shared hosting gives you none of the control you need.

Actools solves all of it. One install. Full control.

---


---

## Prerequisites

Before running the installer you need a sudo user on the server. Root login is disabled after setup.

**Step 1 — Create a sudo user (run once as root)**

On a fresh Hetzner server, SSH in as root and create `setup_user.sh` and `install.env` with your username, password and SSH public key. Then run:

```bash
bash setup_user.sh install.env
```

This creates your sudo user, installs your SSH key, disables root login and password authentication. The `install.env` file is shredded after it runs.

**Step 2 — SSH in as your new user and clone the installer**

```bash
ssh sysadmin@<your-server-ip>
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal
cp actools.env.example actools.env
nano actools.env   # set BASE_DOMAIN and DRUPAL_ADMIN_EMAIL
sudo ./actools.sh fresh
```

> DNS must point to the server before running. Caddy cannot obtain TLS certificates without it.

## Quick start
Note: Actools installs on YOUR server (e.g. Hetzner CX22).
It is not a hosted service — you own and manage the server.

```bash
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal
cp actools.env.example actools.env   # set BASE_DOMAIN, DB_ROOT_PASS
sudo ./actools.sh
```

Drupal 11 · MariaDB 11.4 · Caddy 2.8 · Redis · XeLaTeX — running in under 30 minutes.

---

## What you get

| | Actools | Acquia | Pantheon |
|---|---|---|---|
| Monthly cost | ~€10 VPS | €134–€1,000+ | €35–€800+ |
| Preview environments | ✅ | ✅ | ✅ Multidev |
| Point-in-time recovery | ✅ | paid | paid |
| XeLaTeX / PDF workers | ✅ native | ❌ | ❌ |
| GDPR tools built-in | ✅ | ❌ | ❌ |
| Observability (Grafana) | ✅ | paid add-on | paid add-on |
| Quantum-safe TLS | ✅ | ❌ | ❌ |
| AI codebase assistant | ✅ | ❌ | ❌ |
| Full code ownership | ✅ 100% | ❌ | ❌ |

---

## Key capabilities

**One CLI for everything**
```bash
actools health --verbose          # full system health report
actools branch feature-payment    # spin up isolated preview environment
actools migrate --point-in-time "2026-03-26 14:30:00"  # restore to any second
actools gdpr export user@example.com   # GDPR Art.15 data export
actools immortalize               # snapshot entire server state
actools ai "how does the queue worker handle timeouts?"
```

**Enterprise hardening** (v14.0)
- RPO ~1 hour · RTO <15 minutes
- MariaDB TLS 1.3 · age-encrypted backups · RBAC + audit trail
- DNA resurrection — rebuild from bare metal in under 15 minutes
- GDPR Art.15 export · Art.17 erasure · compliance report

**Developer platform**
- Preview environments per branch — isolated DB, PHP, Caddy vhost, auto-TLS
- Zero-downtime migrations with one-command rollback
- CI/CD pipeline generation (GitHub Actions · GitLab CI)
- AI assistant aware of your actual codebase

---

## Stack

| Component | Version | Notes |
|---|---|---|
| Drupal | 11 | PHP 8.3 FPM |
| MariaDB | 11.4 | TLS 1.3, binary logging, PITR |
| Caddy | 2.8 | HTTP/3, quantum-safe TLS, rate limiting |
| Redis | 7 | LRU eviction |
| XeLaTeX | texlive | Self-contained worker container |
| Prometheus + Grafana | latest | 3 pre-built dashboards |

---

## Roadmap

| Phase | Status | What |
|---|---|---|
| 1–4 | ✅ Complete | Modular platform · observability · preview envs · AI assistant |
| 4.5 | ✅ Complete | Enterprise hardening — PITR · RBAC · TLS · DNA · GDPR |
| 5 | 🔜 Planned | Multi-tenancy — multiple Drupal sites per server |
| 6 | 🔮 Future | GitHub webhook automation — PR → preview · merge → deploy |

Current scope: Single site per server. Multi-site support is planned for Phase 5.
---

## Requirements

Ubuntu 24.04 · 2GB RAM minimum · DNS A records pointing to server

**Current scope:** Single site per server. Multi-site support is planned for Phase 5.
> **DNS must be configured before install.** Point your A record to the server IP before running.
> Add a DNS CAA record for extra security: `CAA 0 issue "letsencrypt.org"`

---


---

## Audit

`actools audit` is a deterministic, operator-readable health check. It does not just report problems — it gives you the exact command to fix each one.

```bash
actools audit                  # full audit
actools audit --security       # security layer only
actools audit --complete       # include performance checks
actools audit --ci             # machine-readable exit codes for CI pipelines
actools audit --json           # JSON output
actools audit --deep           # Pro only — active security scanning
```

**What it checks:**

| Layer | Check | Code |
|---|---|---|
| Drupal | Security advisories | ACT-SEC-05 |
| Drupal | Cron last run | ACT-CRON-01 |
| Drupal | Config drift | ACT-CFG-01 |
| Drupal | trusted_host_patterns configured | ACT-SEC-04 |
| Drupal | Error display hidden in production | ACT-CFG-02 |
| Drupal | Session cookie secure flag | ACT-CFG-02 |
| Drupal | Queue backlog | ACT-WORK-01 |
| Integration | Redis write/read/TTL cycle | ACT-REDIS-02 |
| Integration | Redis as Drupal cache backend | ACT-REDIS-01 |
| Integration | HTTP response headers | ACT-HTTP-01 |
| Integration | Trusted host spoof rejection | ACT-SEC-04 |
| Integration | Queue worker enqueue test | ACT-WORK-02 |
| Integration | Private file path configured and writable | ACT-PRIV-01 |
| Stack | All containers running | ACT-STACK-01 |
| Stack | Site returns HTTP 200 | ACT-STACK-02 |
| Stack | TLS certificate valid and days remaining | ACT-TLS-01 |
| Stack | Disk usage | ACT-DISK-01 |
| Stack | Available memory | ACT-MEM-01 |
| Stack | Backup freshness | ACT-BKUP-01 |
| Stack | MariaDB reachable | ACT-STACK-03 |
| Stack | Worker container health | ACT-WORK-01 |
| Security | HTTPS enforced | ACT-SEC-01 |
| Security | HSTS header | ACT-SEC-01 |
| Security | X-Frame-Options header | ACT-SEC-02 |
| Security | X-Content-Type-Options header | ACT-SEC-02 |
| Security | Server header hidden | ACT-SEC-03 |
| Security | Referrer-Policy header | ACT-SEC-02 |
| Security | Docker images pinned (no :latest) | ACT-SEC-03 |

**CI exit codes:**

| Code | Meaning |
|---|---|
| 0 | All clear |
| 1 | Warnings found |
| 2 | Failures found |
| 3 | Critical issues found |

**Fresh install score:** 6/10 · 0 CRITICAL · 22 PASS. The score reflects real-world hardening gaps — no backup yet, no S3, no observability stack. Not bugs. Each gap has an exact fix command.

## Documentation

| | |
|---|---|
| [Quick start](docs/quick-start.md) | Requirements, installation, first run |
| [Configuration](docs/configuration.md) | Environment variables, S3, XeLaTeX modes |
| [CLI reference](docs/cli-reference.md) | Every command, every flag |
| [Operations](docs/operations.md) | Backups, updates, health checks, troubleshooting |
| [Architecture](docs/architecture.md) | How it's built — modules, state, directory structure |
| [Hardening](docs/hardening.md) | TLS, RBAC, audit trail, settings.php |
| [Observability](docs/observability.md) | Prometheus, Grafana, dashboards, alerts |
| [Enterprise hardening](docs/enterprise.md) | PITR, DNA resurrection, GDPR tools |
| [Privacy & Data Policy](docs/privacy.md) | AI local only, zero phone-home, no telemetry |

## Security

To report a security vulnerability, email **hello@feesix.com** with a description of the issue.
Do not open a public GitHub issue for security vulnerabilities.
We aim to respond within 48 hours.

## Acknowledgements

Development assisted by [Claude](https://claude.ai) (Anthropic).
