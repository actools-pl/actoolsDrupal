# Quick Start

> **Time to running Drupal:** under 30 minutes  
> **Applies to:** Ubuntu 24.04 · Actools v11.0+

---

## Requirements

| | Minimum | Recommended |
|---|---|---|
| OS | Ubuntu 24.04 | Ubuntu 24.04 |
| RAM | 2GB | 4GB+ |
| Disk | 20GB | 40GB+ |
| CPU | 1 vCPU | 2 vCPU |

**Hetzner CX22** (2 vCPU, 4GB RAM, 40GB NVMe) is the reference server — €3.79/month.

DNS A records must point to the server before install. Caddy obtains TLS certificates automatically on first request.

For preview environments (`*.yourdomain.com`), add a wildcard A record pointing to the same IP.

---

## Install

```bash
# 1. Clone
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal

# 2. Configure
cp actools.env.example actools.env
nano actools.env
# Required: BASE_DOMAIN, DRUPAL_ADMIN_EMAIL, DB_ROOT_PASS

# 3. Install
sudo ./actools.sh fresh
```

The installer handles everything: Docker, Caddy, MariaDB, PHP-FPM, Redis, XeLaTeX worker, Prometheus, Grafana.

---

## Verify

```bash
# Health check
actools health --verbose

# All containers running
actools status

# Site is live
curl https://yourdomain.com/health
# → OK
```

---

## First commands

```bash
actools health --verbose          # full system report
actools logs php_prod             # stream PHP logs
actools drush prod status         # Drupal status
actools backup db                 # run a backup now
actools ai "explain the stack"    # ask the AI assistant
```

---

## What was installed

```
/home/actools/
├── actools.env          your configuration (gitignored)
├── docker-compose.yml   stack definition
├── Caddyfile            web server config
├── docroot/prod/        Drupal 11 files
├── modules/             actools feature modules
├── logs/                all container logs
└── backups/             encrypted database backups
```

Drupal admin: `https://yourdomain.com/user/login`  
Credentials: set in `actools.env` as `DRUPAL_ADMIN_EMAIL` / `DRUPAL_ADMIN_PASS`

---

*Next: [Configuration](configuration.md) — set up S3, XeLaTeX, and review all env vars.*
