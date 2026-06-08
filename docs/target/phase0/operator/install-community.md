# Installing Actools Drupal Community

> **Status:** Phase 0 target contract — not yet released. This document describes intended
> behavior after Phase 0 seam hardening. It must not be treated as current released behavior
> until Phase 0 closure.

This document describes the default `community` profile install journey for the Phase 0
target end-state. The five-stage journey — `init → preflight → install → handoff → doctor`
— is identical in user experience before and after Phase 0. What changes structurally is
that the install spine iterates profile stages through a dispatcher; for `community`,
this produces the same result as today.

---

## Prerequisites

- Ubuntu 24.04 (tested target; Ubuntu 22.04 is accepted with a warning)
- Root or sudo access
- The repository cloned to your home directory, e.g. `~/actoolsDrupal`
- At minimum: 2 GB RAM (4 GB recommended), 20 GB free disk (40 GB recommended)
- Ports 80 and 443 free (Caddy will claim them)
- A DNS A record pointing your domain to this server before TLS can issue

---

## Stage 1 — Init

`init` creates `actools.env` from the template. It does not install anything.

```bash
sudo ./actools.sh init \
  --domain example.com \
  --email admin@example.com \
  --site-name "Example Site"
```

**What `init` does (Phase 0 target behaviour):**

1. Sources `installer/dispatch.sh` for profile validation.
2. Validates the `--profile` flag against the allowed-profile list. Omitting `--profile`
   defaults to `community`.
3. Validates required fields: `--domain` (required), `--email` (required, email format
   checked), `--site-name` (optional; defaults to the domain value).
4. Refuses to overwrite an existing `actools.env` without `--force`.
5. Copies `actools.env.example`, patches the three operator-facing fields, and appends
   `ACTOOLS_PROFILE=community` (always explicit after `init`).
6. Sets `actools.env` to mode `600`, owned by the invoking user.
7. Prints `sudo ./actools.sh preflight` as the next command.

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | `actools.env` created successfully |
| `1` | Required field missing or file already exists without `--force` |
| `3` | Unknown `--profile` value |

**Flags:**

| Flag | Required | Description |
|---|---|---|
| `--domain` | Yes | Base domain, e.g. `example.com` |
| `--email` | Yes | Drupal admin email |
| `--site-name` | No | Drupal site name; defaults to `--domain` value |
| `--profile` | No | Deployment profile; defaults to `community` |
| `--force` | No | Overwrite an existing `actools.env` |

**Gap vs current behaviour (P0-E target):** After Phase 0 seam hardening, `init` will
also source `installer/profile.sh`, consume `PROFILE_INIT_FIELDS`, and enforce
`PROFILE_REQUIRES_ACTOR` / `PROFILE_REQUIRES_CHANGE_TICKET`. The `community` profile
sets both to `false` and `PROFILE_INIT_FIELDS=(domain email site-name)`, so community
installs behave identically. This wiring is P0-E / P0-H scope.

---

## Stage 2 — Preflight

`preflight` checks server readiness. Run it after `init`.

```bash
sudo ./actools.sh preflight
```

**What `preflight` checks:**

1. OS is Ubuntu 24.04 (OK) or Ubuntu 22.04 (WARN) or other (FAIL)
2. `actools.env` exists (early-exit on FAIL — remaining checks require it)
3. Required env vars: `BASE_DOMAIN` set and not the placeholder; `DRUPAL_ADMIN_EMAIL` valid
4. RAM: ≥ 2 GB (FAIL below 1.5 GB effective; WARN below 2.5 GB)
5. Disk: ≥ 20 GB free (FAIL); ≥ 40 GB recommended (WARN below)
6. Ports 80 and 443 free (WARN if in use — Caddy will conflict)
7. DNS A record for `BASE_DOMAIN` resolves to this server (WARN if absent or mismatched)
8. Install state: fresh server vs. already-installed (WARN if Drupal already present)

After the base checks, `preflight` loads `installer/profile.sh` to read
`PROFILE_PREFLIGHT_EXTRA`. The `community` profile defines an empty array, so no
profile-extra checks run. The dispatcher (`installer/dispatch.sh`) is sourced but
resolvers are not called in D.0 (this is the Phase 0 target state for `community`).

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | All checks pass — ready to install |
| `1` | One or more FAILs — fix and re-run preflight |
| `2` | Warnings only — install can proceed; review warnings first |

**Next step on success:**

```bash
sudo ./actools.sh install
```

---

## Stage 3 — Install

`install` runs the full provisioning sequence. This is the long-running stage.

```bash
sudo ./actools.sh install
```

`install` is an alias for `fresh`; `fresh` continues to work with a soft deprecation hint
to stderr.

**What `install` does (Phase 0 target behaviour):**

The installer iterates `PROFILE_INSTALL_STAGES` from the active profile through a stage
dispatcher. For `community`, the stages are `host stack db drupal worker` in that order:

| Stage | What runs |
|---|---|
| `host` | System packages, kernel tuning, swap, UFW firewall, Docker install, log rotation |
| `stack` | Generate `my.cnf`, `Dockerfile.caddy`, `Dockerfile.php`, `Dockerfile.worker`, `Caddyfile`, `docker-compose.yml`; build images; start services |
| `db` | Wait for MariaDB readiness; create database, user, and grants |
| `drupal` | Three-stage Drupal provisioning via `modules/drupal/provision.sh`: prepare → provision → secure |
| `worker` | Verify worker container health; register Drupal queue |

After all profile stages complete, the installer runs:
- `setup_backup_cron` — installs the daily backup cron
- `setup_cli` — deploys `/usr/local/bin/actools` from `cli/actools` (Phase 0 target; currently generated by heredoc)
- `tls_check` — waits for Caddy to obtain the TLS certificate

**Secret generation:** All secrets (`DB_ROOT_PASS`, `DB_PASS`, `DRUPAL_ADMIN_PASS`, etc.)
are auto-generated during install if the corresponding env var is blank in `actools.env`.
Secrets are written back into `actools.env` and into `.actools-state.json`. They are never
placed in process arguments.

**Gap vs current behaviour:** In the current codebase, `main()` calls `setup_stack()` and
`install_env()` directly (hardcoded sequence). The Phase 0 target has `main()` iterating
`PROFILE_INSTALL_STAGES` via `run_install_stage`/`resolve_install_stage`. For `community`,
this is behaviour-identical; the change is structural only (P0-D scope).

**State file:** On success, `actools.sh install` writes `.actools-install-complete` as a
marker. The state file `.actools-state.json` tracks per-environment install state and
credential storage.

---

## Stage 4 — Handoff

`handoff` prints the post-install summary. It runs automatically at the end of `install`
and can be re-printed at any time.

```bash
sudo ./actools.sh handoff
```

**What `handoff` prints (community profile):**

The `community` profile defines `PROFILE_HANDOFF_SECTIONS=(site admin commands log)`.
After Phase 0 seam hardening, `handoff` reads these sections from the profile and renders
each one:

- **site** — Site URL: `https://example.com`
- **admin** — Drupal admin login URL and credential file path
- **commands** — Useful daily commands
- **log** — Path to the install log and a note about the encrypted-backup key

Unknown section names are silently skipped (current behaviour). The Phase 0 target for
non-`community` profiles replaces the silent skip with `resolve_handoff_section` (P0-H
scope); for `community` this is invisible.

---

## Stage 5 — Doctor

`doctor` is the daily health check. Run it after install to verify the deployment, and
daily in operations.

```bash
actools doctor
```

**What `doctor` checks:**

1. Site HTTP response at `https://BASE_DOMAIN`
2. TLS certificate validity
3. All expected Docker containers running
4. MariaDB reachable and responding
5. Redis reachable and responding
6. Disk space
7. Backup recency (last backup age)
8. Restore-test recency
9. Drupal bootstrap (`/health` endpoint)

**Exit codes:**

| Code | Meaning |
|---|---|
| `0` | All checks pass — no failures, no warnings |
| `1` | One or more checks failed |
| `2` | Warnings only (no failures) — common on a healthy system with minor advisories; also returned by the `--deep` gate stub |

**Active profile display:** `doctor` prints the active profile (e.g. `Active profile: community`).

**Deep mode:** `actools doctor --deep` is a gate stub. The full deep-mode implementation
(trend regression, config drift, capacity forecasting, slow-log anomaly detection) is
a community-plus feature implemented in Phase 1.

---

## Idempotency

The installer is idempotent. Re-running `actools.sh fresh` on an already-installed server
skips completed phases. Use `actools update` for routine operational updates rather than
re-running install.

---

## Cross-references

- Profile contract and resolver behaviour:
  [`docs/architecture/phase0-seam-contract.md`](../../architecture/phase0-seam-contract.md)
- Generated-file safety:
  [`docs/architecture/generated-file-contract.md`](../../architecture/generated-file-contract.md)
- CLI authority:
  [`docs/architecture/cli-authority-contract.md`](../../architecture/cli-authority-contract.md)
- Commands reference: [`commands.md`](commands.md)
- Troubleshooting: [`troubleshooting.md`](troubleshooting.md)
