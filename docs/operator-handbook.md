# Operator handbook

Daily operations on a running Actools install. Five commands cover most of what you need; the rest are documented in `command-reference.md`.

---

## The five commands you actually use

```bash
actools doctor       # one-page health summary
actools status       # container status (docker compose ps)
actools logs [svc]   # stream logs; omit service for all
actools backup       # run a backup now
actools update       # pull + drush updb + caddy reload
```

If you only learn these five, you can operate the platform.

---

## Doctor — your daily check

`actools doctor` is the first command you run each morning.

```
ACTOOLS DOCTOR

  OK     Site               https://example.com (HTTP 200)
  OK     TLS                valid (62 days remaining)
  OK     Containers         5/5 running
  OK     Database           reachable
  OK     Redis              reachable
  OK     Disk               42% used (28G free)
  OK     Backups            latest is 18h old
  WARN   Restore test       last run 9d ago
         Fix: actools restore-test
  OK     Drupal             bootstrap successful

1 warning(s) — see suggested actions above.
```

Exit codes: `0` all green, `2` warnings only, `1` one or more critical failures. CI-safe.

`actools doctor --deep` is in development — when it ships, it will add 30-day trend regression, configuration drift detection, capacity forecasting, and anomaly detection on slow.log and FPM access patterns. `actools doctor` (no flag) covers everyday operational health.

---

## Backups

Daily backups run automatically via cron. To run one manually:

```bash
actools backup
```

To verify the latest backup actually restores cleanly (touches a temp database — no data loss):

```bash
actools restore-test
```

`doctor` warns if `restore-test` hasn't run in a week. Run it monthly at minimum.

To restore from a specific backup:

```bash
actools restore prod                              # most recent
actools restore prod /path/to/specific.sql.gz     # a chosen file
```

You'll be prompted for confirmation before any database is overwritten.

For point-in-time recovery to any second within the binlog retention window, see [`advanced.md`](advanced.md#point-in-time-recovery).

---

## Updates

The single command:

```bash
actools update
```

Takes a pre-update database snapshot, pulls newer container images, runs `drush updb` and `drush cr` in every installed environment, then reloads Caddy. Idempotent — safe to re-run.

Before running, `actools dry-run` shows the steps `actools update` will take. (Note: dry-run currently prints a static description; it does not inspect your specific install state — pending Drupal updates, available container image versions, etc. Treat the output as a procedure description, not a per-install plan.)

---

## Logs

```bash
actools logs              # all containers, follow
actools logs php_prod     # just PHP-FPM
actools logs caddy        # just Caddy
```

Slow-request log for PHP:

```bash
actools slow-log prod
```

Redis memory and eviction:

```bash
actools redis-info
```

Recent OOM events on the host:

```bash
actools oom
```

---

## Containers

```bash
actools status            # docker compose ps
actools restart           # restart everything
actools restart php_prod  # restart one service
actools stats             # live docker stats
```

To open a shell in a container:

```bash
actools shell php_prod
```

To run a drush command:

```bash
actools drush prod cache:rebuild
actools drush prod user:login admin
```

---

## TLS

```bash
actools tls-status        # certificate expiry dates
actools caddy-reload      # zero-downtime config reload
```

`doctor` fails if TLS expires in <7 days, warns at <30. Let's Encrypt auto-renews 30 days before expiry, so a failure here means something is blocking renewal — usually DNS or rate limits.

---

## Worker and PDF

```bash
actools worker-status     # Drupal queue depth
actools worker-logs       # stream worker container logs
actools worker-run        # run queue manually
actools pdf-test          # test XeLaTeX in worker
```

---

## When something goes wrong

```bash
actools doctor            # what's broken
actools logs <svc>        # what it's saying
actools status            # is the container even up
```

If `doctor` shows a FAIL, follow the Fix line beneath it. The fix is the literal next command to type.

For specific problems, see [`troubleshooting.md`](troubleshooting.md).

---

## What's not in this handbook

PITR, DNA snapshot/resurrection, GDPR tools, preview environments, AI assistant, Cloudflare tunnels, CI generators, `actools audit` — all live in [`advanced.md`](advanced.md). They're useful but not required to operate the platform.
