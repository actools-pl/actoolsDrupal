# Actools Drupal Community

A guided single-server Drupal installer and operator CLI for Ubuntu 24.04.

Install Drupal 11, Caddy, MariaDB, Redis, PHP-FPM, and a worker container on one VPS in five staged commands. Get a small operator CLI for the daily tasks. Run as much or as little of the advanced surface as you want — none of it is required.

[![CI](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml/badge.svg)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml) [![Security Scan](https://img.shields.io/badge/security-trivy-green)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/lint.yml) [![CodeQL](https://github.com/actools-pl/actoolsDrupal/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/actools-pl/actoolsDrupal/actions/workflows/github-code-scanning/codeql)

---

## What it installs

Drupal 11 · MariaDB 11.4 · Caddy 2.8 (auto-TLS, HTTP/3) · Redis 7 · PHP 8.3 FPM · XeLaTeX worker · daily backups · health checks.

## Requirements

Ubuntu 24.04 VPS · 2 GB RAM minimum (4 GB recommended) · 20 GB disk · sudo user · DNS A record pointing to the server.

## Install

```bash
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal

sudo ./actools.sh init --domain example.com --email admin@example.com --site-name "Example"
sudo ./actools.sh preflight
sudo ./actools.sh install
```

Three commands. The installer creates `actools.env`, checks the server is ready, then builds the stack.

## Verify

```bash
actools doctor
```

One line per check: site, TLS, containers, database, Redis, disk, backups, restore-test recency, Drupal bootstrap. Each failure tells you the next command to fix it.

## Daily commands

```bash
actools doctor       # one-page health summary
actools status       # container status
actools logs         # stream logs
actools backup       # run a backup now
actools update       # pull + drush updb + caddy reload
```

`actools help` shows the common surface. `actools help advanced` shows everything else.

## Advanced features

The installer also ships PITR backups, DNA snapshot/resurrection, GDPR tools, preview environments, an AI assistant, Cloudflare tunnel support, and `actools audit`.

See [`docs/advanced.md`](docs/advanced.md) — none of it is required for a working site.

## Documentation

| Doc | What it covers |
|---|---|
| [`docs/quick-start.md`](docs/quick-start.md) | Full install walkthrough with screenshots-in-prose |
| [`docs/operator-handbook.md`](docs/operator-handbook.md) | Daily operations: backups, updates, restores |
| [`docs/command-reference.md`](docs/command-reference.md) | Every command, every flag |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | DNS, TLS, Docker, DB, disk, restore |
| [`docs/advanced.md`](docs/advanced.md) | PITR, DNA, GDPR, AI, preview environments, tunnels |
| [`docs/architecture.md`](docs/architecture.md) | How it's built — modules, state, profiles |
| [`docs/privacy.md`](docs/privacy.md) | What stays local, what doesn't |

## What this is and isn't

This is a single-server Drupal installer and operator kit. It is not a managed hosting platform, multi-tenant SaaS, or compliance certification. The advanced features are useful, but the community claim is intentionally narrow: install and operate Drupal on one VPS, calmly.

## Deployment profiles

Actools supports deployment profiles via the `--profile` flag on `init`.

The default `community` profile is suitable for all standard installs. A `community-plus` profile — designed for schools, universities, and regulated organisations that need evidence generation and governance gates — arrives in later phases.

```bash
# Default — community profile (no flag needed)
sudo ./actools.sh init --domain example.com --email admin@example.com

# Community-plus (arriving in later phases)
sudo ./actools.sh init --domain example.com --email admin@example.com \
  --profile community-plus
```

The active profile is shown in `actools doctor`. Once set at init time the profile is pinned in `actools.env` for the lifetime of the deployment.

## Security

To report a security vulnerability, email **hello@feesix.com**. We aim to respond within 48 hours. Do not open a public GitHub issue for security issues.

## Acknowledgements

Development assisted by [Claude](https://claude.ai) (Anthropic). MIT licensed.
