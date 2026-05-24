# Troubleshooting

Symptom-first. Find your symptom in the headers below, follow the steps. Every fix tells you what command to run.

If something isn't here, `actools doctor` is almost always the right first command — it tells you which subsystem is unhappy, and the Fix line beneath each failure is the literal next command.

---

## DNS

### `preflight` says DNS has no A record

Point your domain's A record at the server IP, then re-run preflight.

```bash
curl ifconfig.me                  # what the server thinks its IP is
dig +short example.com            # what DNS resolves to
```

Until they match, Caddy cannot issue TLS. The install will still run — the site just stays on HTTP until DNS propagates. Re-run `actools caddy-reload` once DNS is correct.

### `preflight` says DNS resolves to a different IP

Either your A record is stale or you're behind a proxy. Update the A record. If you're using Cloudflare in proxy mode, the resolved IP will be Cloudflare's, not yours — that's fine for the running site but `preflight` will warn. See [`advanced.md`](advanced.md#cloudflare-tunnel).

---

## TLS

### `doctor` says TLS expires soon

Let's Encrypt auto-renews 30 days before expiry. If you're seeing this warning, renewal is being blocked. Common causes:

- DNS no longer points to this server → fix the A record
- Port 80 blocked → must be reachable for HTTP-01 challenge
- Rate-limited by Let's Encrypt → wait and retry, or use staging endpoint

```bash
actools caddy-reload
actools tls-status
```

### Browser shows "Not secure"

Caddy hasn't issued yet. Confirm DNS first, then check Caddy logs:

```bash
actools logs caddy
```

Look for `obtaining certificate` and the outcome. The most common message is `unable to authorize` — that means DNS or port 80.

---

## Docker

### `actools status` shows containers missing or restarting

```bash
actools logs <name>               # what does it say
docker compose down               # full reset
docker compose up -d              # bring back up
```

If a container restarts in a loop, the logs will show why. The most common causes after a working install: out of disk (`actools doctor` flags this) or out of memory (`actools oom`).

### `Cannot connect to Docker daemon` after install

You need to reconnect SSH for the docker group to activate:

```bash
exit
ssh sysadmin@<server>
```

Or, in the same session:

```bash
newgrp docker
```

---

## Database

### `doctor` says Database unreachable

```bash
actools status                    # is db container up
actools logs db                   # what does it say
```

If the container is up but `mariadb -uroot` fails, the password is wrong. The root password lives in `actools.env` as `DB_ROOT_PASS`. The credentials file at `~/.actools-db-creds` should match.

### `mariadb-dump: not found` during backup

You're on a pre-v9.2 install. MariaDB 11.4 renamed `mariadump` to `mariadb-dump`. Update Actools:

```bash
cd ~/actoolsDrupal
git pull
sudo ./actools.sh update
```

---

## Disk

### `doctor` says Disk over 80%

```bash
df -h
du -sh ~/backups/                 # backups usually the biggest
```

Old backups past retention can be deleted:

```bash
find ~/backups -name 'prod_db_*.sql.gz' -mtime +14 -delete
```

`BACKUP_RETENTION_DAYS` in `actools.env` controls retention. Default is 7 days.

Docker can also accumulate old images:

```bash
docker system prune -af           # safe; removes unused images and layers
```

---

## Backup and restore

### `restore-test` fails checksum

The backup file is corrupted. Check the next-most-recent backup:

```bash
ls -lh ~/backups/prod_db_*.sql.gz
actools restore prod ~/backups/prod_db_PREVIOUS.sql.gz
```

If you have rclone configured for offsite backups, fetch from there:

```bash
rclone copy "${RCLONE_REMOTE}/prod_db_OK.sql.gz" ~/backups/
```

### `restore` says "No backups found"

`actools backup` to create one. The backup cron may not have run yet on a fresh install. Verify cron:

```bash
cat /etc/cron.daily/actools-backup
```

---

## Install failed mid-way

The installer is idempotent. Re-running `install` resumes from where it stopped:

```bash
sudo ./actools.sh install
```

If a specific environment failed, install just that one:

```bash
sudo ./actools.sh env prod
```

The full install log is at `~/logs/install/actools-LATEST.log`:

```bash
actools log-dir
tail -200 ~/logs/install/actools-*.log
```

---

## When in doubt

```bash
actools doctor
```

Then read the Fix lines beneath any FAIL. If `doctor` itself errors, you probably haven't reconnected SSH since install — log out, log back in, retry.

If you've worked through this doc and the symptom isn't covered, the install logs and `actools doctor` output are what to bring to the GitHub issue tracker.
