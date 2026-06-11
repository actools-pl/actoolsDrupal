# Roadmap

This document tracks committed architectural work that is **planned and partially built** but not yet enabled in the default install. It is the canonical reference for any documentation note saying *"this feature is deferred"* or *"planned hardening."*

If a doctrine note in the docs says *"not enabled by default — see ROADMAP.md"*, the relevant section here explains what's planned, what's already coded, and what's needed to complete it. For the full architectural context, see [`docs/technical-roadmap.md`](docs/technical-roadmap.md).

This file does NOT track every known issue or every future idea. It tracks operator-relevant deferred items and committed architectural deliverables.

---

## Committed architectural work — planned but not enabled

The code for these features exists in the repository; install-time deployment wiring is the remaining work. See [`docs/technical-roadmap.md`](docs/technical-roadmap.md) for the full architectural context.

### Encrypted backup deployment <a id="encrypted-backups"></a>

**Status:** Code complete, deployment wiring incomplete

**What exists:**
- `modules/backup/db-full-backup.sh` — daily encrypted dump script
- `modules/backup/binlog-rotate.sh` — hourly binlog rotation + age encryption
- `modules/backup/pitr-restore.sh` — point-in-time restore from encrypted dumps + binlogs
- `modules/backup/encrypted_backup.sh` — age encryption helper
- `modules/backup/deploy-pitr.sh` — deployment script (manual invocation)

**What's missing:**
- ✅ The standard installer now generates a per-deployment age keypair (`.age-key.txt` mode 600 + `.age-public-key`, owned by the install operator) at install time — done. (No backup consumer is wired yet; the key is generated and stored, not yet read by any running job.)
- The standard installer does not invoke `deploy-pitr.sh` to install the encrypted backup cron entries
- The standard install generates a basic gzip backup cron **inline** (in `actools.sh`), installed at `/etc/cron.daily/actools-backup`. (The `cron/backup.sh` file in the repo is an unwired duplicate and is not deployed.)

**What's needed to complete:**
1. ✅ Add age keypair generation step to the installer (per-deployment keypair) — **done**
2. Invoke `deploy-pitr.sh` during install to set up the encrypted backup cron jobs
3. Update CLI `restore` and `restore-test` paths to handle `.age` files (detect extension, decrypt before restore)
4. Update operational docs to describe the now-deployed encrypted system
5. Introduce a configurable service user (and make the backup consumer run as it, owning the age key) — deferred to this feature-completion work, since only then does something actually run as that user. The current installer deliberately owns key material as the install operator (`REAL_USER`) and does not advertise a service-user knob.

**Architectural reference:** [`docs/technical-roadmap.md`](docs/technical-roadmap.md) — Section 5A "High Availability & Disaster Recovery"

### MariaDB TLS in transit <a id="mariadb-tls"></a>

**Status:** Templates exist, deployment wiring incomplete

**What exists:**
- `certs/mariadb/99-ssl.cnf` — MariaDB SSL configuration template
- `certs/mariadb/ca-cert.pem`, `client-cert.pem`, `server-cert.pem` — shared CA + cert templates

**What's missing:**
- `server-key.pem` is not in the repository (would need to be generated per-deployment)
- The standard installer does not mount `certs/mariadb/` into the db container
- The standard installer does not mount `99-ssl.cnf` into `/etc/mysql/mariadb.conf.d/`
- The shipped cert templates are shared across deployments; per-deployment cert generation is needed for production use

**What's needed to complete:**
1. Generate per-deployment CA + server cert + key during install
2. Move from shipped cert templates to install-time generation
3. Add volume mounts to the compose configuration for the certs and 99-ssl.cnf
4. Update the Drupal PDO connection settings to use SSL

**Architectural reference:** [`docs/technical-roadmap.md`](docs/technical-roadmap.md) — Section 5E "Security Hardening"

Current state: `docs/hardening.md` describes MariaDB TLS as not enabled by default and documents the manual enabling steps.

### Cloudflare Tunnel — Caddy ACME wiring <a id="caddy-cloudflare-acme"></a>

**Status:** Environment variable placeholder added, Caddyfile wiring incomplete

**What exists:**
- `CADDY_CLOUDFLARE_TOKEN` placeholder in `actools.env.example`
- Documentation in `modules/network/cloudflare-setup.md` describing DNS-01 and Origin-Cert options

**What's missing:**
- The Caddy image does not include the `caddy-dns/cloudflare` provider plugin
- The Caddyfile does not consume `CADDY_CLOUDFLARE_TOKEN` for DNS-01 challenge

**What's needed to complete:**
1. Build a custom Caddy image with the cloudflare DNS provider plugin
2. Wire `CADDY_CLOUDFLARE_TOKEN` into the Caddyfile's `tls` block when the variable is set
3. Document the Origin-Certificate workflow with full step-by-step instructions

**Architectural reference:** [`docs/technical-roadmap.md`](docs/technical-roadmap.md) — Section 5C "Zero-Trust Networking"

### Automated rollback in `actools update` <a id="automated-rollback"></a>

**Status:** Manual rollback supported, automated rollback not implemented

**What exists:**
- `actools update` creates a pre-update snapshot before pulling new images
- `actools update` exits non-zero on `drush updb` failure with snapshot path and manual restore command printed
- `actools restore prod <snapshot>` performs manual rollback

**What's missing:**
- No automated health check after database updates and Caddy reload
- No automated invocation of `actools restore` on health-check failure

**What's needed to complete:**
1. Define what "post-update health check" means (HTTP probe? drush status? bootstrap test?)
2. Implement the health check in `actools update` after the update applies
3. Wire automated rollback to `actools restore prod <snapshot>` on health-check failure

**Architectural reference:** [`docs/technical-roadmap.md`](docs/technical-roadmap.md) — Section 5A "High Availability & Disaster Recovery"

Current state: `docs/operations.md` describes the update flow and names manual rollback as the supported path.

### Two-CLI architecture collapse <a id="two-cli-collapse"></a>

**Resolved (P0-F).** `cli/actools` is the single canonical CLI, installed verbatim by `setup_cli()` (`actools.sh:702-717`). The heredoc CLI generator was removed; `tests/installer/cli_authority_test.bats` enforces that no generation path remains. (Kept here as a historical note.)

### Audit-wrapper topology in standard install <a id="audit-wrapper"></a>

**Status:** Deployed in disaster-recovery installations only, not in standard install

**What exists:**
- Audit wrapper at `modules/security/actools-audit`
- The disaster-recovery resurrection path installs the wrapper chain (`actools` symlink → `actools-audit` → `actools-real`)

**What's missing:**
- The standard installer creates a single regular file at `/usr/local/bin/actools` instead of the wrapper chain
- Documentation in `docs/hardening.md` and `docs/architecture.md` describes the wrapper topology as if always deployed

**What's needed to complete:**
1. Decide whether the wrapper topology should be standard or remain DR-only
2. If standard: update the installer to deploy the same chain
3. If DR-only: update docs to clearly distinguish deployment modes

**Architectural reference:** [`docs/technical-roadmap.md`](docs/technical-roadmap.md) — Section 5D's "Audit Logging" subsection

---

## Known gaps deferred for future work

Items identified during recent review cycles, held for future treatment.

### Operator-relevant items

- **Audit module behavior at non-default install paths** — The audit module may return success when run against installs deployed at non-default paths (paths other than the configured `INSTALL_DIR`). Fix planned. Workaround: verify audit findings against your actual install paths if you customized the install location.

- **`INSTALL_DIR` sibling references** — Some operational paths still reference the historical default `/home/actools`. Operators with custom install paths may encounter a few code sites that haven't been updated to use the configured install location yet. A cleanup pass is planned.

- **Session cookie hardening — further tightening** — The installer auto-applies five session security flags (`cookie_secure`, `cookie_httponly`, `cookie_samesite=Strict`, `use_strict_mode`, `use_only_cookies`). Operators with cross-origin OAuth flows or other deployment-specific needs may want to relax `samesite` to `Lax`; further hardening tuning is deployment-dependent and not auto-applied beyond the secure defaults.

### Development / release process items

- **CI workflow improvements** — Several CI-process refinements are planned: action version pinning (currently uses some unpinned action references), enforcement of vulnerability-scanner findings (currently report-only), and a fast/slow CI split to reduce signal latency on routine changes.

- **Release process documentation** — Self-update workflow guidance is currently incomplete; the operations doc describes re-running the installer rather than an in-place upgrade path. A canonical self-update flow is planned work.

---

## Future direction

The architectural commitment for future phases is documented in [`docs/technical-roadmap.md`](docs/technical-roadmap.md). Topics covered there include multi-tenancy support, GitHub webhook integration for CI/CD, content intelligence integration, and edge distribution.

These are under architectural consideration; current commitment is to complete the enterprise hardening work first.

---

## How to use this file

**If you're an operator reading doctrine prose** that references this file (e.g., *"encrypted backups are not enabled by default — see ROADMAP.md"*), the relevant section here explains:
- What exists in code today
- What's missing for the feature to be enabled
- Where the architectural commitment is documented

**If you're contributing and want to pick up planned work**, the "What's needed to complete" lists are intended as task starters. Open an issue first to coordinate.

**If you're auditing the platform**, the "Known gaps deferred for future work" section is the most useful operator-facing inventory.

---

*Last updated: see git log.*
