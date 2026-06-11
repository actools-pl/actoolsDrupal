# Enterprise Hardening (planned / experimental)

> **Status: design reference — NOT operational today.** This document describes **planned** enterprise and disaster-recovery features. The standard installer does **not** deploy them, and the commands shown throughout — `actools immortalize`, `actools resurrect`, `actools gdpr …`, `actools migrate --point-in-time …`, `actools backup status` — are **not registered** in the `actools` CLI: running them returns *unknown command*. The supporting scripts exist under `modules/backup/`, `modules/dr/`, and `modules/compliance/` but are unwired and unvalidated against the current stack. **Do not rely on the runbooks below in a real incident.** See [`../ROADMAP.md`](../ROADMAP.md) for status.

The intent of this page: capture the target design for a future production-grade tier (~1 hour RPO, <15 minute RTO). Nothing here is part of the community installer today.

---

## Point-in-Time Recovery *(planned — not deployed)*

MariaDB records every write to binary logs. Combined with daily full dumps, this would allow restoring to any point in time. **The standard installer deploys daily gzip dumps only**; binary logging and encrypted dumps are planned — see [`../ROADMAP.md#encrypted-backups`](../ROADMAP.md#encrypted-backups).

### How it would work

| Job | Schedule | What |
|---|---|---|
| `db-full-backup.sh` *(not deployed)* | Daily 02:00 | Full encrypted dump with embedded binlog position |
| `binlog-rotate.sh` *(not deployed)* | Hourly :05 | Archive all closed binlogs, age-encrypted |

`--master-data=2` would embed the binlog file and position into the dump. Binlogs would live in a separate Docker volume (`mariadb_binlogs`).

### Restore to a point in time *(planned syntax — these commands do not exist today)*

```bash
# (planned — not available)
actools <pitr-restore> "2026-03-26 14:30:00" --dry-run
actools <pitr-restore> "2026-03-26 14:30:00"
```

The PITR scripts exist in `modules/backup/` but are not invoked by the standard installer.

---

## DNA Resurrection *(planned — not wired; do not run)*

The design: `immortalize` would capture a complete server blueprint into an age-encrypted JSON snapshot, and `resurrect` would replay it on a fresh server. **Neither is a registered command.** The `modules/dr/resurrect.sh` script is unvalidated and would install a separate `actools-real` binary — **do not run it on a real server.**

```bash
# (planned — not available)
actools immortalize
# inspect a snapshot, if one existed:
age --decrypt -i ~/.age-key.txt backups/dna/dna-latest.json.age | python3 -m json.tool
```

The design's rebuild flow is 11 steps (install dependencies → create user → clone repo → restore secrets → start stack → restore database → install CLI + cron + RBAC → health check). It is **not** an operational procedure today.

### What to keep in secure off-server storage

Independent of this feature, **keep these for any manual recovery:**

| File | Why |
|---|---|
| `actools.env` | All credentials |
| `.age-key.txt` | Decrypts all backups |
| `certs/mariadb/*-key.pem` | MariaDB TLS private keys |

Never commit these to git. Store in a password manager or encrypted vault.

---

## GDPR Compliance *(planned — not wired)*

`actools gdpr …` is **not** a registered command. The code lives in `modules/compliance/gdpr.sh` and is unvalidated against the current Drupal version.

```bash
# (planned — not available)
actools gdpr export user@example.com   # Art.15 — Right of Access
actools gdpr delete user@example.com   # Art.17 — Right to Erasure
actools gdpr audit  user@example.com   # audit trail for a user
actools gdpr report                    # full compliance status
```

Planned export format: JSON in `backups/gdpr-exports/`. Planned delete protection: UID 1 cannot be deleted; deletion requires typing the full email; a pre-deletion export is created.

---

## Operational runbooks *(PLANNED DESIGN — not operational; commands shown are not available)*

> These illustrate the **intended** recovery design. They are **not** procedures you can run today — the `actools migrate --point-in-time`, `actools resurrect`, and `actools gdpr` commands do not exist. For real recovery today, use the shipped `actools backup` / `actools restore` / `actools restore-test` commands (see [`command-reference.md`](command-reference.md)).

### Recover from accidental deletion *(planned)*

```bash
# (planned — not available)
actools <pitr-restore> "2026-03-26 13:45:00" --dry-run
actools <pitr-restore> "2026-03-26 13:45:00"
```

### Server is dead — rebuild from scratch *(planned)*

```bash
# (planned — modules/dr/resurrect.sh is unwired/unvalidated; do not run on a real server)
```

### Handle a GDPR erasure request *(planned)*

```bash
# (planned — not available)
actools gdpr export user@example.com
actools gdpr delete user@example.com
```

### Add a new team member

```bash
sudo useradd -m -s /bin/bash actools-dev
echo "ssh-ed25519 AAAA..." | sudo tee -a /home/actools-dev/.ssh/authorized_keys
# Note: scoped sudoers/RBAC roles are part of the planned hardening tier, not the standard install.
```

---

## Recovery targets *(planned)*

| Metric | Target | How (planned) |
|---|---|---|
| RPO | ~1 hour | Hourly binlog rotation *(not deployed)* |
| RTO | <15 minutes | DNA snapshot + resurrect script *(not deployed)* |
| Backup retention | 7 days | `BACKUP_RETENTION_DAYS` in actools.env |
| Audit retention | Unlimited | Append-only log files |

---

*Back to [docs index](README.md)*
