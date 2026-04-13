# Operations

> Quick health check: `actools health --verbose`  
> Applies to: Actools v11.2.0+ · MariaDB 11.4 · Caddy 2.8

---

## Backups

### How backups work

Two jobs run automatically:

| Job | Schedule | What |
|---|---|---|
| Full dump | Daily 02:00 | `mariadb-dump --single-transaction`, age-encrypted, rclone upload |
| Binlog rotation | Hourly :05 | Closed binary logs compressed + age-encrypted |

Together these give RPO ~1 hour. For point-in-time restore see [Enterprise hardening](enterprise.md).

### Check backup status

```bash
actools backup status
# Shows: latest dump file + size, binlog archive count, current binlog position
```

### Run a backup manually

```bash
actools backup db           # full dump now
actools backup binlogs      # rotate binlogs now
```

### Verify a backup

```bash
actools restore-test        # decrypts latest dump, counts tables, reports pass/fail
```

### Restore from backup

```bash
actools restore prod        # list available backups → choose → confirm → restore
actools restore prod /home/actools/backups/db/2026-03-26/full-dump-210531.sql.gz.age
```

---

## Updates

### Drupal core and modules

```bash
actools update
# 1. Creates pre-update snapshot
# 2. Pulls latest container images
# 3. Runs drush updb (database updates)
# 4. Runs drush cr (cache rebuild)
# 5. Health check — rolls back if it fails
```

### Stack updates (Docker images)

```bash
# Pull new images and restart
cd /home/actools
docker compose pull
docker compose up -d
actools health
```

### Actools itself

```bash
cd /home/actools
git pull origin main
# Re-install CLI if updated
sudo cp cli/actools /usr/local/bin/actools-real
```

---

## Health checks

```bash
actools health                    # quick — HTTP 200 check
actools health --verbose          # full report
```

Full report covers: container status, memory pressure per container, TLS certificate expiry, disk space, PHP slow log warnings.

### What healthy looks like

```
=== Actools Health Check ===
── Containers ──────────────────────────
  ✓ actools_caddy — running
  ✓ actools_db — running
  ✓ actools_php_prod — running
  ✓ actools_redis — running
  ✓ actools_worker_prod — running
── Memory Pressure ─────────────────────
  ✓ actools_php_prod: 120MiB / 512MiB (23%)
  ✓ actools_db: 125MiB / 2048MiB (6%)
── TLS Certificate ─────────────────────
  ✓ feesix.com — expires in 88 days
── Disk Space ──────────────────────────
  ✓ /: 8.2G used of 38G (22%)
```

---

## Troubleshooting

### MariaDB

**Container not starting**
```bash
docker compose logs db --tail=30
```

**`Permission denied` on `/var/log/mysql/slow.log`**
```bash
sudo touch /home/actools/logs/db/slow.log
sudo chown 999:999 /home/actools/logs/db/slow.log
docker compose restart db
```

**`Access denied for user 'root'`** — password mismatch between container and `actools.env`
```bash
# Check what password the container has
docker inspect actools_db --format='{{range .Config.Env}}{{println .}}{{end}}' | grep MARIADB_ROOT

# Compare with env file
grep DB_ROOT_PASS /home/actools/actools.env
```

**`healthcheck.sh: not found`** — means `mysqladmin` is in the healthcheck (removed in MariaDB 11.4)
```bash
grep "healthcheck" /home/actools/docker-compose.yml
# Must show: healthcheck.sh --connect --innodb_initialized
```

**Can't connect using `mysql` command** — MariaDB 11.4 renamed the binary
```bash
# Use mariadb instead of mysql
docker compose exec db mariadb -uroot -p"${DB_ROOT_PASS}"
```

### Caddy

**Certificate not renewing**
```bash
docker compose logs caddy --tail=50 | grep -i "error\|cert\|acme"

# Force renewal
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**`Caddyfile:N: unrecognized directive`**
```bash
# Validate config before reload
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

**Preview environment vhost not responding**
```bash
# Check Caddy picked up the new vhost
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
actools health
```

### XeLaTeX / PDF worker

**PDF generation failing**
```bash
actools pdf-test
actools worker-logs
```

**`xelatex: command not found` inside container**
```bash
docker compose exec worker_prod which xelatex
# If missing — rebuild the worker image
docker compose build worker_prod
docker compose up -d worker_prod
```

**Queue not processing**
```bash
actools worker-status             # check queue depth
actools worker-run                # trigger manually
actools worker-logs               # stream logs
```

**Out of memory during PDF generation**
```bash
# Increase worker memory limit in docker-compose.yml
# mem_limit: "4g"  (default: 2g)
docker compose up -d worker_prod
```

### Common error reference

| Error | Cause | Fix |
|---|---|---|
| `403 Forbidden` on image pull | Docker Compose v2 trying to pull local image | Add `pull_policy: never` to local image services |
| `DB_ROOT_PASS` writeback fails | Line has trailing comment | Remove inline comments from `.env` values |
| `innodb_log_file_size` mismatch | Changed log size with existing data | Stop db, remove `ib_logfile*`, restart |
| `QUIC is not supported` | UDP port 443 not open | `sudo ufw allow 443/udp` |
| Caddy rate limit on login | Expected — Caddy caddy-ratelimit active | Adjust zone config in Caddyfile if too aggressive |

---

*Back to [docs index](README.md)*

---

## Resource Usage — Real World Numbers

Measured on feesix.com (Hetzner CX22 — 2 vCPU, 4GB RAM) under normal load:

| Container | CPU | Memory | Limit |
|---|---|---|---|
| actools_caddy | 0.00% | 17 MB | — |
| actools_php_prod | 0.01% | 111 MB | 512 MB |
| actools_redis | 0.78% | 4 MB | 256 MB |
| actools_db | 0.03% | 258 MB | 2 GB |
| **Total** | **~1%** | **~390 MB** | — |

A €10 Hetzner CX22 (4GB RAM) runs the full stack using under 400MB RAM at idle.
Leaves 3.6GB headroom for traffic spikes, XeLaTeX PDF generation, and growth.

*Measured April 13, 2026 — production feesix.com*
