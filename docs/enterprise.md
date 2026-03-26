# Enterprise Hardening

> **Version:** v11.2.0 · **RPO:** ~1 hour · **RTO:** <15 minutes  
> Applies to: Actools v11.2.0+

Phase 4.5 closes the gap between a working Drupal platform and a production-grade enterprise system.

---

## Point-in-Time Recovery

MariaDB records every write to binary logs. Combined with daily full dumps, this allows restoring to any point in time — down to the second.

### How it works

| Job | Schedule | What |
|---|---|---|
| `db-full-backup.sh` | Daily 02:00 | Full encrypted dump with embedded binlog position |
| `binlog-rotate.sh` | Hourly :05 | Archive all closed binlogs, age-encrypted |

`--master-data=2` embeds the exact binlog file and position into the dump. The restore script uses this to know exactly where to start replaying logs.

Binlogs live in a separate Docker volume (`mariadb_binlogs`) — independent of the data volume. They survive a container recreate from a fresh dump.

### Restore to a point in time

```bash
# Always dry-run first
actools migrate --point-in-time "2026-03-26 14:30:00" --dry-run

# Actual restore — requires typing YES
actools migrate --point-in-time "2026-03-26 14:30:00"
```

The restore: finds the nearest full dump → decrypts → stops app containers → restores dump → replays binlogs to target time → restarts containers.

### Check status

```bash
actools backup status
```

---

## DNA Resurrection

`actools immortalize` captures a complete server blueprint — OS, Docker versions, running containers, modules, binlog position, SSL expiry, redacted env keys — into an age-encrypted JSON snapshot. `actools resurrect` replays it on a fresh server.

### Create a snapshot

```bash
actools immortalize
# → /home/actools/backups/dna/dna-YYYY-MM-DD-HHMMSS.json.age
```

Runs automatically daily at 03:00. Last 7 kept locally.

### Inspect a snapshot

```bash
age --decrypt -i ~/.age-key.txt backups/dna/dna-latest.json.age | python3 -m json.tool
```

### Rebuild on a fresh server

```bash
# On a new Hetzner CX22 (Ubuntu 24.04), as root:
curl -sSL https://raw.githubusercontent.com/actools-pl/actoolsDrupal/main/modules/dr/resurrect.sh \
  | bash -s -- --dna /path/to/dna.json.age --key /path/to/age-key.txt

# Preview without executing:
bash resurrect.sh --dna dna.json.age --key age-key.txt --dry-run
```

The script runs 11 steps: install dependencies → create user → clone repo → restore secrets → start stack → restore database → install CLI + cron + RBAC → health check.

### What to keep in secure off-server storage

| File | Why |
|---|---|
| `actools.env` | All credentials |
| `.age-key.txt` | Decrypts all backups and DNA snapshots |
| `certs/mariadb/*-key.pem` | MariaDB TLS private keys |

Never commit these to git. Store in a password manager or encrypted vault.

---

## GDPR Compliance

```bash
actools gdpr export user@example.com   # Art.15 — Right of Access
actools gdpr delete user@example.com   # Art.17 — Right to Erasure
actools gdpr audit  user@example.com   # audit trail for a user
actools gdpr report                    # full compliance status
```

### Export format

A JSON file in `backups/gdpr-exports/` containing profile, roles, content count, and all audit log entries referencing that user.

### Delete protection

UID 1 (superadmin) cannot be deleted. Deletion requires typing the full email address. A pre-deletion export is automatically created as an audit record.

### Compliance report output

```
── GDPR Compliance Report ────────────────────────────
User statistics:  Total: 12  Active: 11  Blocked: 1
Data retention:   DB backups: 7 dumps · Binlogs: 168 files
Encryption:       age at rest ✓ · TLS 1.3 in transit ✓
Compliance:
  ✓ Right of Access (Art.15)
  ✓ Right to Erasure (Art.17)
  ✓ Audit trail
  ✓ Encryption at rest
  ✓ Encryption in transit
  ✓ Data retention policy (7 days)
  ✓ Access control (RBAC)
```

---

## Operational runbooks

### Recover from accidental deletion

```bash
# 1. Find when it happened (Drupal watchdog or estimate)
# 2. Dry run
actools migrate --point-in-time "2026-03-26 13:45:00" --dry-run
# 3. Restore
actools migrate --point-in-time "2026-03-26 13:45:00"
# 4. Verify
actools health --verbose && curl https://feesix.com/health
```

### Server is dead — rebuild from scratch

```bash
# 1. Provision new Hetzner CX22 (Ubuntu 24.04)
# 2. Copy secrets to new server
scp actools.env age-key.txt root@new-server:/tmp/
# 3. Run resurrect
curl -sSL https://raw.githubusercontent.com/actools-pl/actoolsDrupal/main/modules/dr/resurrect.sh \
  -o resurrect.sh
sudo bash resurrect.sh --dna /path/to/dna-latest.json.age --key /tmp/age-key.txt
# 4. Update DNS A record if IP changed
```

### Handle a GDPR erasure request

```bash
actools gdpr export user@example.com  # export first, for your records
actools gdpr delete user@example.com  # confirm by typing email
actools gdpr audit  user@example.com  # verify deletion logged
```

### Add a new team member

```bash
sudo useradd -m -s /bin/bash actools-dev
echo "ssh-ed25519 AAAA..." | sudo tee -a /home/actools-dev/.ssh/authorized_keys
# Sudoers rules already scope what they can run
```

---

## Recovery targets

| Metric | Target | How |
|---|---|---|
| RPO | ~1 hour | Hourly binlog rotation |
| RTO | <15 minutes | DNA snapshot + resurrect script |
| Backup retention | 7 days | `BACKUP_RETENTION_DAYS` in actools.env |
| Audit retention | Unlimited | Append-only log files |

---

*Back to [docs index](README.md)*
