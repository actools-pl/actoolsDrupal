# HANDOVER.md — actools Community Version
*Freeze document — April 21, 2026*
*This document is the contract for the community version.*
*Do not change these decisions without community discussion.*

---

## What This Is

actools is a one-command Drupal 11 installer for Hetzner CX22 (Ubuntu 24.04).
It installs a production-ready Drupal stack in 15-25 minutes with zero manual steps.

```bash
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal
cp actools.env.example actools.env   # edit domain, email, passwords
sudo ./actools.sh fresh
```

That is the entire user journey.

---

## Frozen Decisions

These are not open for change in the community version.
They may be revisited in the monetisation version (Phase 2).

### 1. Human Roles

| Role | Who | What they can do |
|---|---|---|
| Installer user | Any sudoer (e.g. `sysadmin`, `john`) | Run `sudo ./actools.sh fresh` |
| App user | `www-data` | Write to `files/` and `private/` only |
| DB user | `actools_prod` | Access only their own database |
| Root | Only during install | Packages, Docker, firewall setup |

**Rule:** The installer runs as sudo but hands ownership back to `REAL_USER` after every operation. `www-data` owns runtime directories. Root owns nothing after install completes.

---

### 2. Install-Root Philosophy

- `INSTALL_DIR` is always the directory containing `actools.sh`
- It is dynamically detected — never hardcoded
- It is exported so all subshells and modules can access it
- The installer works for any username — `sysadmin`, `john`, `actools`, or anything else

```bash
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR
```

---

### 3. Path Zones

| Zone | Path | Purpose | Owner | Writable by |
|---|---|---|---|---|
| code | `$INSTALL_DIR/docroot/prod/web` | Drupal codebase | REAL_USER | REAL_USER only |
| runtime-public | `$INSTALL_DIR/docroot/prod/web/sites/default/files` | Public uploads | www-data | www-data |
| runtime-private | `$INSTALL_DIR/docroot/prod/private` | Private files | www-data | www-data |
| config | `$INSTALL_DIR/docroot/prod/web/sites/default/settings.php` | Drupal config | REAL_USER | Nobody after install (444) |
| secrets | `$INSTALL_DIR/actools.env` | Environment vars | REAL_USER | REAL_USER only (600) |
| state | `$INSTALL_DIR/.actools-state.json` | Install state | REAL_USER | REAL_USER only |
| logs | `$INSTALL_DIR/logs/` | All logs | REAL_USER | REAL_USER + www-data |
| backups | `$INSTALL_DIR/backups/` | DB backups | REAL_USER | REAL_USER only |
| infra | `/var/run/docker.sock` | Docker socket | root | docker group only — never 666 |

**Rule:** Never `chmod 777` anything. Never `chown -R root`. Always re-apply `www-data` ownership to runtime zones after any `chown -R REAL_USER` operation.

---

### 4. Community Boundary

**What is in scope for the community version:**
- Single server, single Drupal 11 site (prod environment)
- Hetzner CX22, Ubuntu 24.04
- Docker Compose stack: Caddy, PHP-FPM, MariaDB 11.4, Redis 7, Worker
- Basic S3 storage integration
- Daily backup cron
- `actools audit` — 27-check health audit
- `actools` CLI for day-to-day operations

**What is out of scope (Phase 2 / monetisation version):**
- Multi-site per server
- Dev/staging environments (code exists, not supported)
- Grafana monitoring
- Point-in-time recovery
- AI content builder (actools_brain, actools_planner, actools_ui, actools_views)
- Modular lib/ architecture
- Full CI with hcloud E2E tests
- Permission policy/enforcement/verification separation

---

### 5. Test Contract

A fresh install is considered passing when all of these pass with zero manual steps:

```bash
sudo ./actools.sh fresh
actools audit                           # score ≥ 7/10
goss validate --format documentation   # 26/26
bats tests/install.bats                # 12/12
```

And load test passes when:
```
k6: 50 VUs, 5 minutes, p95 < 250ms, failure rate < 0.1%
```

**Idempotency contract:** Running `sudo ./actools.sh fresh` a second time must:
- Detect existing install and run updates only
- Not reinstall Drupal
- Not duplicate config injections
- Not reset `www-data` ownership on `files/` and `private/`
- Pass all four test commands above

---

## Known Technical Debt

These are honest limitations. They are tracked, not hidden.

| Item | Description | Phase |
|---|---|---|
| Permission system | Enforcement and verification are combined. Policy is implicit, not explicit. Should be three separate layers: policy spec, enforcer, verifier. | Phase 2 |
| provision.sh | Wired in but not complete. Some install logic still in actools.sh. Full extraction pending. | Phase 2 |
| Docker group session | `.bashrc` fix applied but first SSH session after install still requires `newgrp docker` on some systems. `exec sg` permanent fix pending. | Phase 2 |
| Scoring algorithm | 24 PASS, 0 CRITICAL should score 8/10 not 7/10. Weighting needs adjustment. | Before release |
| GitHub Actions E2E | No automated hcloud fresh install test on push yet. Manual testing only. | Before release |
| Worker image pinning | `actools_worker:latest` uses unpinned tag. ACT-SEC-03 warning. | Phase 2 |

---

## Architecture Sketch (Phase 2)

This is the intended modular structure. Do not implement in community version.

```
actools.sh              # dispatcher only
lib/common.sh           # log, warn, error, section, colors, lock
lib/bootstrap.sh        # REAL_USER, REAL_HOME, INSTALL_DIR, ENV_FILE
lib/preflight.sh        # sudo checks, env loading, DNS, validate_env
lib/state.sh            # init_state, get_state, set_state, get_db_pass
lib/system.sh           # packages, kernel, swap, firewall, docker
lib/stack.sh            # setup_stack, compose, Dockerfiles, Caddyfile
lib/drupal.sh           # check_db_creds, install_env
lib/ops.sh              # backup_cron, setup_cli, tls_check
lib/permissions.sh      # permissions enforcer (reads from policy spec)
modules/drupal/provision.sh      # drupal_provision() — wired in
modules/audit/audit.sh           # actools audit
modules/audit/lib/               # drupal, integration, stack, security checks
```

Permission policy table (source of truth for Phase 2):

| Path | Zone | Owner | Group | Dir Mode | File Mode | App Writable |
|---|---|---|---|---|---|---|
| `$INSTALL_DIR/docroot/prod/web` | code | REAL_USER | www-data | 0755 | 0644 | No |
| `sites/default/files` | runtime | www-data | www-data | 0755 | 0644 | Yes |
| `private/` | runtime | www-data | www-data | 0755 | 0644 | Yes |
| `settings.php` | config | REAL_USER | REAL_USER | — | 0444 | No |
| `actools.env` | secrets | REAL_USER | REAL_USER | — | 0600 | No |
| `/var/run/docker.sock` | infra | root | docker | — | 0660 | docker group only |

---

## How to Contribute

1. Fork the repo
2. Create a fresh Hetzner CX22 (Ubuntu 24.04)
3. Run `sudo ./actools.sh fresh`
4. Run the test contract above — all must pass
5. Make your change
6. Run the test contract again — all must still pass
7. Submit a PR with test output attached

**The test contract is the contribution gate. No exceptions.**

---

## Outreach Gate

Community outreach and Matt Glaman contact after:
- GitHub Actions E2E automated test passing on push
- Score stable ≥ 8/10 on clean server
- 3+ confirmed external testers
- This document committed to the repo

Not before.

---

*Built with Claude. MIT License.*
