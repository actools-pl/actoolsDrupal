# Advanced features

Everything beyond the daily five commands. None of this is required to run a working Drupal site. Enable the pieces you actually need.

The goal of this page is to keep the README and quick-start narrow. The features are real and useful — they just don't belong in the first install journey.

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

MariaDB binary logging plus daily encrypted dumps would let you restore the database to any second within the retention window. The current installer deploys daily gzip dumps only; binary logging and encrypted dumps are planned — see [`../ROADMAP.md#encrypted-backups`](../ROADMAP.md#encrypted-backups).

```bash
# Dry-run first — shows exactly what would happen
actools migrate --point-in-time "2026-03-26 14:30:00" --dry-run

# Real restore — requires typing YES
actools migrate --point-in-time "2026-03-26 14:30:00"
```

How it works (planned): `db-full-backup.sh` runs daily at 02:00, dumping with `--master-data=2` so the binlog position is embedded. `binlog-rotate.sh` runs hourly, encrypting closed binlogs with age. The restore script finds the nearest full dump, decrypts, stops app containers, restores, replays binlogs to the target time, restarts.

Target RPO ~1 hour (hourly binlog rotation), target RTO <15 minutes for in-place recovery.

These scripts exist in `modules/backup/` but the standard installer does not currently wire them into cron. Encrypted backup deployment with PITR is planned — see [`../ROADMAP.md#encrypted-backups`](../ROADMAP.md#encrypted-backups).

Status:

```bash
actools backup status
```

---

## DNA resurrection

`actools immortalize` captures a complete server blueprint — OS, Docker versions, container manifests, modules, binlog position, redacted env keys — into an age-encrypted JSON snapshot. `actools resurrect` replays it on a fresh server.

```bash
# Create a snapshot — runs automatically daily at 03:00
actools immortalize
actools immortalize --upload     # also push to rclone remote

# Inspect
age --decrypt -i ~/.age-key.txt backups/dna/dna-latest.json.age | python3 -m json.tool

# On a fresh Hetzner CX22, as root
curl -sSL https://raw.githubusercontent.com/actools-pl/actoolsDrupal/main/modules/dr/resurrect.sh \
  | bash -s -- --dna /path/to/dna.json.age --key /path/to/age-key.txt

# Preview without executing
bash resurrect.sh --dna dna.json.age --key age-key.txt --dry-run
```

The resurrect script runs 11 steps: install dependencies → create user → clone repo → restore secrets → start stack → restore database → install CLI + cron + RBAC → health check.

**Keep these three things in secure off-server storage:**

| File | Why |
|---|---|
| `actools.env` | All credentials |
| `~/.age-key.txt` | Decrypts every backup and every DNA snapshot |
| `certs/mariadb/*-key.pem` | MariaDB TLS private keys |

A password manager or encrypted vault is fine. **Do not commit these to git.**

---

## GDPR compliance

```bash
actools gdpr export user@example.com   # Art.15 — Right of Access
actools gdpr delete user@example.com   # Art.17 — Right to Erasure
actools gdpr audit  user@example.com   # audit trail for one user
actools gdpr report                    # full compliance status
```

Export format: JSON file in `backups/gdpr-exports/` with profile, roles, content count, and all audit log entries referencing that user.

Deletion protection: UID 1 (superadmin) cannot be deleted. Deletion requires typing the full email address as confirmation. A pre-deletion export is automatically created as an audit record.

---

## Preview environments

Per-branch isolated Drupal environments for PR previews, design reviews, and risky migrations.

```bash
actools branch feature-payment            # create
actools branch --list                     # list active
actools branch --destroy feature-payment  # remove
actools branch --cleanup                  # auto-remove previews >7 days old
```

Each preview gets its own database, PHP container, and Caddy vhost with auto-TLS at `feature-payment.yourdomain.com`. Requires wildcard DNS (`*.yourdomain.com`).

A daily cron sweeps abandoned previews.

---

## CI/CD generation

```bash
actools ci --generate                      # GitHub Actions
actools ci --generate --platform=gitlab    # GitLab CI
```

Generates three workflows from templates:

- **test** — runs on every PR (PHP CodeSniffer, PHPStan, composer validate)
- **deploy** — runs on merge to main (backup + pull + drush updb + health)
- **security** — weekly (composer audit + Drupal advisories)

Output lands in `.github/workflows/` (or `.gitlab-ci.yml`) with your domain and paths filled in.

---

## AI assistant

A small local model with codebase context for "how does this script work" questions.

```bash
actools ai "how does the queue worker handle timeouts?"
actools ai explain modules/backup/db-full-backup.sh
actools ai review --security
actools ai review --performance
actools ai context                # rebuild the codebase index
```

Model: `deepseek-coder:1.3b` (776 MB) running locally via Ollama. No data leaves the server. The context builder indexes all `core/`, `modules/`, and `cli/` bash files, so answers reference real function names and line numbers — not hallucinated patterns.

This is an opt-in feature. Disable Ollama if you don't want a 776 MB model on the box.

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

Prometheus + Grafana on a separate compose file.

```bash
docker compose -f docker-compose.observability.yml up -d
```

Three pre-built dashboards: Node Exporter Full, cAdvisor, Redis. Prometheus data source is auto-configured via API.

`actools cost-optimize` reads real container memory usage versus configured limits and suggests changes.

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
