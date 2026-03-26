# Enterprise Hardening — Phase 4.5

> **Version:** v11.2.0  
> **Status:** Complete  
> **Commits:** `d0c2a84` → `14bfd03`

Phase 4.5 closes the gap between a working Drupal platform and a production-grade enterprise system. It adds six capabilities that together deliver:

- **RPO ~1 hour** — at most 1 hour of data loss in any failure scenario
- **RTO <15 minutes** — from bare metal to running Drupal in under 15 minutes
- **Audit trail** — every action logged with timestamp, operator, and arguments
- **Compliance-ready** — GDPR Art.15/17, encryption at rest and in transit

---

## Table of Contents

1. [Binary Logging + Point-in-Time Recovery](#1-binary-logging--point-in-time-recovery)
2. [RBAC + Audit Trail](#2-rbac--audit-trail)
3. [MariaDB SSL / TLS 1.3](#3-mariadb-ssl--tls-13)
4. [DNA Resurrection System](#4-dna-resurrection-system)
5. [GDPR Compliance Tools](#5-gdpr-compliance-tools)
6. [Cloudflare Tunnel](#6-cloudflare-tunnel)
7. [Operational Runbooks](#7-operational-runbooks)

---

## 1. Binary Logging + Point-in-Time Recovery

### What it does

MariaDB records every write operation to binary logs. Combined with daily full dumps, this allows restoring the database to any point in time — down to the second.

### Configuration

Binary logging is enabled via `modules/backup/99-binlog.cnf`:

```ini
[mysqld]
log_bin         = /var/log/mysql/mysql-bin.log
binlog_format   = ROW
expire_logs_days = 7
max_binlog_size  = 100M
sync_binlog      = 1
server_id        = 1
```

`sync_binlog=1` ensures every transaction is flushed to disk before the client receives acknowledgement — safest setting, negligible overhead on NVMe.

Binlogs live in a separate Docker named volume (`mariadb_binlogs`) independent of the data volume — they survive a container recreate from a fresh dump.

### Scheduled jobs

| Job | Schedule | What it does |
|---|---|---|
| `db-full-backup.sh` | Daily 02:00 | `mysqldump --single-transaction --flush-logs --master-data=2`, age-encrypted |
| `binlog-rotate.sh` | Hourly :05 | Flush + archive all closed binlogs, age-encrypted |

`--master-data=2` embeds the exact binlog file and position into the dump as a comment. The restore script uses this to know exactly where to start replaying logs.

### Restore to a point in time

```bash
# Dry run first — shows what would happen
actools migrate --point-in-time "2026-03-26 14:30:00" --dry-run

# Actual restore — requires typing YES
actools migrate --point-in-time "2026-03-26 14:30:00"
```

What the restore does:
1. Finds the most recent full dump before the target datetime
2. Decrypts it using the age private key
3. Stops `php_prod` and `worker_prod` containers
4. Restores the full dump into MariaDB
5. Decrypts and replays binlogs up to the target datetime via `mysqlbinlog --stop-datetime`
6. Restarts app containers

### Check backup status

```bash
actools backup status
# Shows: latest dump, binlog archive count, current binlog position
```

### Files

```
modules/backup/
├── 99-binlog.cnf        MariaDB binary log config
├── db-full-backup.sh    Daily full dump script
├── binlog-rotate.sh     Hourly binlog archiver
├── pitr-restore.sh      Point-in-time restore engine
├── cli-pitr.sh          CLI integration
└── actools-db-backup.cron  Cron drop-in (/etc/cron.d/)
```

---

## 2. RBAC + Audit Trail

### Roles

Three system users with scoped access to `actools` CLI commands:

| Role | User | Permitted commands |
|---|---|---|
| Developer | `actools-dev` | `branch`, `drush`, `logs`, `status`, `health`, `shell`, `worker-logs`, `worker-status` |
| Operations | `actools-ops` | All `actools` commands |
| Viewer | `actools-viewer` | `status`, `health`, `logs`, `worker-status`, `tls-status` (read-only) |

### Setup

```bash
# Users are created on fresh install via resurrect.sh
# On existing server, create manually:
sudo useradd -m -s /bin/bash actools-dev
sudo useradd -m -s /bin/bash actools-ops
sudo useradd -m -s /bin/bash actools-viewer

# Install sudoers rules
sudo cp modules/security/sudoers-roles /etc/sudoers.d/actools-roles
sudo chmod 440 /etc/sudoers.d/actools-roles
```

### Audit trail

Every `actools` invocation is logged before execution:

```
2026-03-26T21:37:18Z user=actools euid=1000 args=status
2026-03-26T21:50:21Z user=actools euid=1000 args=backup status
2026-03-26T22:13:00Z user=actools euid=1000 args=immortalize
```

Log location: `/home/actools/logs/audit.log`

The audit wrapper (`/usr/local/bin/actools-audit`) is a symlink target of `/usr/local/bin/actools`. It logs then calls the real binary (`actools-real`).

### Files

```
modules/security/
├── sudoers-roles    Sudoers rules for dev/ops/viewer
└── actools-audit    Audit wrapper script
```

---

## 3. MariaDB SSL / TLS 1.3

### What it does

All connections to MariaDB are encrypted with TLS 1.3. `require_secure_transport=ON` means the server rejects any non-SSL connection — including from the PHP containers.

### Certificate setup

Self-signed certificates with a 10-year validity, stored in `certs/mariadb/`:

```bash
# CA
certs/mariadb/ca-cert.pem       # CA certificate (committed)
certs/mariadb/ca-key.pem        # CA private key (gitignored)

# Server
certs/mariadb/server-cert.pem   # Server certificate (committed)
certs/mariadb/server-key.pem    # Server private key (gitignored)

# Client
certs/mariadb/client-cert.pem   # Client certificate (committed)
certs/mariadb/client-key.pem    # Client private key (gitignored)
```

Private keys are gitignored. Back them up separately in secure storage alongside `actools.env` and `.age-key.txt`.

### Verify SSL is active

```bash
docker compose exec db mariadb -uroot -p"${DB_ROOT_PASS}" --batch \
  -e 'SHOW VARIABLES LIKE "require_secure_transport"; SHOW STATUS LIKE "Ssl_cipher";'

# Expected output:
# require_secure_transport   ON
# Ssl_cipher                 TLS_AES_256_GCM_SHA384
```

### Regenerating certificates

```bash
cd /home/actools/certs/mariadb

# New CA
openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=Actools MariaDB CA/O=Actools/C=PL"

# New server cert
openssl req -newkey rsa:2048 -days 3650 -nodes \
  -keyout server-key.pem -out server-req.pem \
  -subj "/CN=actools_db/O=Actools/C=PL"
openssl x509 -req -in server-req.pem -days 3650 \
  -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
rm server-req.pem

chmod 644 server-key.pem ca-key.pem
docker compose restart db
```

---

## 4. DNA Resurrection System

### What it does

`actools immortalize` captures a complete server blueprint — OS details, Docker versions, running containers, installed modules, binlog position, SSL cert expiry, redacted env keys — into an age-encrypted JSON snapshot. `actools resurrect` replays this blueprint on a fresh server.

### Create a snapshot

```bash
actools immortalize
# → /home/actools/backups/dna/dna-YYYY-MM-DD-HHMMSS.json.age

# With off-site upload (requires RCLONE_REMOTE in actools.env)
actools immortalize --upload
```

Snapshots are taken automatically daily at 03:00 via cron. The last 7 are kept locally.

### Decrypt and inspect a snapshot

```bash
age --decrypt -i ~/.age-key.txt \
  /home/actools/backups/dna/dna-2026-03-26-221009.json.age \
  | python3 -m json.tool | less
```

### Resurrect on a fresh server

```bash
# On the new server (as root):
curl -sSL https://raw.githubusercontent.com/actools-pl/actoolsDrupal/main/modules/dr/resurrect.sh \
  -o resurrect.sh

bash resurrect.sh \
  --dna /path/to/dna-latest.json.age \
  --key /path/to/age-key.txt

# Dry run (shows all steps without executing):
bash resurrect.sh --dna dna.json.age --key age-key.txt --dry-run
```

### Resurrection steps

The script walks through 11 steps automatically:

1. Decrypt DNA snapshot
2. Install system dependencies (Docker, age, git)
3. Create `actools` system user
4. Clone repository from GitHub
5. Restore secrets (pause for manual copy of `actools.env`, age key, certs)
6. Start Docker stack
7. Restore database (from latest encrypted dump)
8. Install `actools` CLI
9. Install cron jobs
10. Install RBAC sudoers
11. Final health check

### What to keep in secure off-server storage

These files are never committed to git. Keep them in a password manager or encrypted storage:

| File | Why |
|---|---|
| `actools.env` | All credentials |
| `.age-key.txt` | Decrypts all backups and DNA snapshots |
| `certs/mariadb/*-key.pem` | MariaDB TLS private keys |

### Files

```
modules/dr/
├── immortalize.sh   Snapshot creator
└── resurrect.sh     Fresh server restore script
```

---

## 5. GDPR Compliance Tools

### Commands

```bash
# Right of Access (Art. 15) — export everything stored about a user
actools gdpr export user@example.com

# Right to Erasure (Art. 17) — delete user account + all authored content
actools gdpr delete user@example.com

# Audit trail — all logged actions relating to a user
actools gdpr audit user@example.com

# Compliance report — users, retention, encryption status, checklist
actools gdpr report
```

### Export format

`actools gdpr export` produces a JSON file in `/home/actools/backups/gdpr-exports/`:

```json
{
  "export_date": "2026-03-26T22:25:54Z",
  "requested_by": "actools",
  "gdpr_basis": "Art. 15 GDPR — Right of Access",
  "profile": {
    "uid": "1",
    "name": "admin",
    "email": "user@example.com",
    "status": "active",
    "created": "2026-03-25 18:20:42",
    "last_login": "2026-03-26 10:00:00",
    "roles": ["administrator"]
  },
  "content": {
    "total_nodes": "12",
    "note": "First 100 nodes shown"
  },
  "audit_entries": [...]
}
```

### Delete protection

- UID 1 (superadmin) cannot be deleted
- Requires typing the full email address to confirm
- Pre-deletion export is automatically created as an audit record
- All deletions logged to `logs/gdpr.log` with operator and timestamp

### Audit logs

Two logs are maintained:

| Log | Contents |
|---|---|
| `logs/audit.log` | Every `actools` CLI invocation (user, timestamp, args) |
| `logs/gdpr.log` | GDPR-specific actions (export, delete, audit, report) |

### Compliance checklist

Running `actools gdpr report` verifies:

- ✓ Right of Access (Art. 15)
- ✓ Right to Erasure (Art. 17)
- ✓ Audit trail
- ✓ Encryption at rest (age)
- ✓ Encryption in transit (TLS 1.3)
- ✓ Data retention policy
- ✓ Access control (RBAC)

### Files

```
modules/compliance/
└── gdpr.sh    Export, delete, audit, report functions
```

---

## 6. Cloudflare Tunnel

> **Status:** Pending — requires Cloudflare account with feesix.com DNS managed by Cloudflare.

Cloudflare Tunnel will remove all inbound open ports (80, 443) from UFW. All traffic will route through an encrypted outbound tunnel — the server makes no inbound connections.

Once a Cloudflare account is set up:

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb

# Authenticate and create tunnel
cloudflared tunnel login
cloudflared tunnel create actools-feesix

# Configure (see modules/network/cloudflared-config.yml)
cloudflared tunnel --config /home/actools/cloudflared-config.yml run

# Close inbound ports
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
sudo ufw delete allow 443/udp
```

Note: Caddy will need to switch from HTTP ACME challenge to Cloudflare DNS challenge for certificate renewal once ports 80/443 are closed.

---

## 7. Operational Runbooks

### Runbook: recover from accidental data deletion

```bash
# 1. Find when the deletion happened (Drupal watchdog or your own knowledge)
# 2. Dry run first
actools migrate --point-in-time "2026-03-26 13:45:00" --dry-run

# 3. Run restore (stops Drupal, restores, replays, restarts)
actools migrate --point-in-time "2026-03-26 13:45:00"

# 4. Verify
actools health --verbose
curl https://feesix.com/health
```

### Runbook: server is dead, rebuild from scratch

```bash
# On new Hetzner CX22 (Ubuntu 24.04):

# 1. Copy secrets from secure storage to new server
scp actools.env age-key.txt new-server:/tmp/

# 2. Download and run resurrect
curl -sSL https://raw.githubusercontent.com/actools-pl/actoolsDrupal/main/modules/dr/resurrect.sh \
  -o resurrect.sh
sudo bash resurrect.sh \
  --dna /path/to/latest-dna.json.age \
  --key /tmp/age-key.txt

# 3. When prompted, place secrets:
cp /tmp/actools.env /home/actools/actools.env
cp /tmp/age-key.txt /home/actools/.age-key.txt

# 4. After resurrection completes
actools health --verbose
# Update DNS A record to new server IP if needed
```

### Runbook: handle a GDPR erasure request

```bash
# 1. Verify user exists
actools gdpr audit user@example.com

# 2. Export first (for your records)
actools gdpr export user@example.com

# 3. Delete (will ask for email confirmation)
actools gdpr delete user@example.com

# 4. Confirm deletion
actools gdpr audit user@example.com
```

### Runbook: add a new team member

```bash
# Developer access
sudo useradd -m -s /bin/bash actools-dev
sudo passwd actools-dev
# Add their SSH public key
sudo mkdir -p /home/actools-dev/.ssh
sudo echo "ssh-ed25519 AAAA..." >> /home/actools-dev/.ssh/authorized_keys

# They can now run:
# sudo -u actools actools branch <name>
# sudo -u actools actools drush prod <cmd>
# sudo -u actools actools logs
```

---

## Recovery Targets Summary

| Metric | Target | How achieved |
|---|---|---|
| RPO | ~1 hour | Hourly binlog rotation |
| RTO | <15 minutes | DNA snapshot + resurrect script |
| Backup retention | 7 days | `BACKUP_RETENTION_DAYS` in actools.env |
| Cert validity | 10 years | Self-signed MariaDB certs |
| Audit retention | Unlimited | Append-only log files |
