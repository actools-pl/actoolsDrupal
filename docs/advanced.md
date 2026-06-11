# Advanced features

Everything beyond the daily five commands. None of this is required to run a working Drupal site.

This page mixes **shipped** capabilities with **experimental/planned** ones. Shipped commands are registered in the `actools` CLI today. Sections marked **Experimental — not wired** describe code that exists in the source tree but is **not** registered as an `actools` command: running those commands returns *unknown command*. They are documented here as design reference; see [`../ROADMAP.md`](../ROADMAP.md) for status.

---

## Audit

`actools audit` is a deterministic operator-readable health check that doesn't just report problems — it gives you the exact command to fix each one.

```bash
actools audit                  # full audit
actools audit --security       # security layer only
actools audit --complete       # include performance checks
actools audit --ci             # machine-readable exit codes for CI
actools audit --json           # JSON output
actools audit --deep           # in development — active security scanning
```

CI exit codes: `0` clear, `1` warnings, `2` failures, `3` critical.

Fresh-install score is typically 6/10 — the score reflects real hardening gaps (no backup yet, no S3, no observability stack), not bugs. Each gap comes with a fix command.

See `modules/audit/docs/fix_catalog.md` for the full check catalogue.

`actools audit --deep` is in development — it is not available in this edition. When it ships, it will run OWASP ZAP, SSLyze, Nmap, and the Drupal Security Review module against your live site. The community audit is comprehensive on its own — `--deep` is for compliance reviews and pentest-style checks.

---

## Point-in-time recovery

> **Experimental — not wired.** The `actools migrate --point-in-time …` and `actools backup status` commands shown below **do not exist** in the current CLI (`actools migrate` is a read-only XeLaTeX guide). The scripts exist in `modules/backup/` but the standard installer does not wire them into cron. This section describes the planned design.

MariaDB binary logging plus daily encrypted dumps would let you restore the database to any second within the retention window. The current installer deploys daily gzip dumps only; binary logging and encrypted dumps are planned — see [`../ROADMAP.md#encrypted-backups`](../ROADMAP.md#encrypted-backups).

Planned syntax:

```bash
# (planned — not available today)
actools <pitr-restore> "2026-03-26 14:30:00" --dry-run
actools <pitr-restore> "2026-03-26 14:30:00"
```

How it works (planned): `db-full-backup.sh` runs daily at 02:00, dumping with `--master-data=2` so the binlog position is embedded. `binlog-rotate.sh` runs hourly, encrypting closed binlogs with age. The restore script finds the nearest full dump, decrypts, stops app containers, restores, replays binlogs to the target time, restarts. Target RPO ~1 hour, target RTO <15 minutes for in-place recovery.

---

## DNA resurrection

> **Experimental — not wired.** `actools immortalize` and `actools resurrect` are **not** registered commands. The scripts live in `modules/dr/`, are unvalidated against the current stack, and `resurrect.sh` would install a separate `actools-real` binary — do **not** run it on a live server. This section is design reference only.

The design: `immortalize` captures a complete server blueprint — OS, Docker versions, container manifests, modules, binlog position, redacted env keys — into an age-encrypted JSON snapshot. `resurrect` would replay it on a fresh server in 11 steps (install dependencies → create user → clone repo → restore secrets → start stack → restore database → install CLI + cron + RBAC → health check).

Regardless of this feature's status, **keep these three things in secure off-server storage** — they are needed for any manual recovery:

| File | Why |
|---|---|
| `actools.env` | All credentials |
| `~/.age-key.txt` | Decrypts every backup |
| `certs/mariadb/*-key.pem` | MariaDB TLS private keys |

A password manager or encrypted vault is fine. **Do not commit these to git.**

---

## GDPR compliance

> **Experimental — not wired.** `actools gdpr …` is **not** a registered command. The code lives in `modules/compliance/gdpr.sh` and is not validated against the current Drupal version. Design reference only.

Planned surface:

```bash
# (planned — not available today)
actools gdpr export user@example.com   # Art.15 — Right of Access
actools gdpr delete user@example.com   # Art.17 — Right to Erasure
actools gdpr audit  user@example.com   # audit trail for one user
actools gdpr report                    # full compliance status
```

Planned export format: JSON in `backups/gdpr-exports/` with profile, roles, content count, and audit-log entries. Planned deletion protection: UID 1 cannot be deleted; deletion requires typing the full email; a pre-deletion export is created as an audit record.

---

## Preview environments

> **Experimental — not wired.** `actools branch …` is **not** a registered command. The code lives in `modules/preview/branch.sh`. Design reference only.

The design: per-branch isolated Drupal environments for PR previews, design reviews, and risky migrations.

```bash
# (planned — not available today)
actools branch feature-payment            # create
actools branch --list                     # list active
actools branch --destroy feature-payment  # remove
actools branch --cleanup                  # auto-remove previews >7 days old
```

Each preview would get its own database, PHP container, and Caddy vhost with auto-TLS at `feature-payment.yourdomain.com`, requiring wildcard DNS (`*.yourdomain.com`).

---

## CI/CD generation

> **Experimental — not wired.** `actools ci …` is **not** a registered command. The code lives in `cli/commands/ci_generate.sh` (unsourced). Design reference only.

Planned surface:

```bash
# (planned — not available today)
actools ci --generate                      # GitHub Actions
actools ci --generate --platform=gitlab    # GitLab CI
```

Would generate three workflows from templates — **test** (PR: CodeSniffer, PHPStan, composer validate), **deploy** (merge: backup + pull + drush updb + health), **security** (weekly: composer audit + Drupal advisories) — into `.github/workflows/` or `.gitlab-ci.yml`.

---

## AI assistant

> **Experimental — not wired.** `actools ai …` is **not** a registered command. The code lives in `modules/ai/assistant.sh`. Design reference only.

The design: a small local model with codebase context for "how does this script work" questions.

```bash
# (planned — not available today)
actools ai "how does the queue worker handle timeouts?"
actools ai explain modules/backup/db-full-backup.sh
actools ai review --security
actools ai context                # rebuild the codebase index
```

Planned model: `deepseek-coder:1.3b` running locally via Ollama; no data leaves the server.

---

## Cloudflare tunnel

Zero open inbound ports on the VPS. Cloudflare proxies all traffic through an outbound-only tunnel.

```bash
actools tunnel status
actools tunnel restart
actools tunnel logs
```

The tunnel runs as a systemd service (`cloudflared.service`). Configuration template in `modules/network/cloudflared-config.yml.example`. Once active, you can remove the UFW rules for 80/443 — only SSH remains inbound.

See `modules/network/cloudflare-setup.md` for the one-time setup.

---

## Observability

> **Optional / standalone — not installed by default.** The standard installer does **not** deploy this stack. It is a separate compose file you bring up manually, and `actools cost-optimize` shown below is **not** a registered command.

Prometheus + Grafana on a separate compose file:

```bash
docker compose -f docker-compose.observability.yml up -d
```

Three pre-built dashboards: Node Exporter Full, cAdvisor, Redis. (Verify the compose file and dashboards against your stack before relying on them — this path is not exercised by the standard install or tests.)

---

## Storage

Multi-provider S3 — AWS, Backblaze B2, Wasabi, or any custom S3-compatible endpoint. The provider is auto-detected from the endpoint URL.

```bash
actools storage-test       # PUT/GET/DELETE round-trip
actools storage-info       # provider, bucket, endpoint, CDN
```

Configuration lives in `actools.env`. Credentials are injected via Docker environment variables — never written to Drupal's config system or config exports.

---

## What's not here

By design:

- Web-based installer or dashboard
- Multi-tenant SaaS features
- DrupalFortress governance (separate product)
- Kubernetes / multi-node orchestration
- Plugin marketplace

The community installer is single-server, CLI-first, calm. The hardened single-tenant platform with optional governance — DrupalFortress — is a separate product that reuses this installer's operator UX. See [`profiles/README.md`](../profiles/README.md) for the profile contract that lets it inherit.
