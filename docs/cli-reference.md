# CLI Reference

> Run `actools help` on the server for a live summary.  
> Applies to: Actools v11.2.0+

---

## Health & monitoring

```bash
actools health                    # HTTP check — site up or down
actools health --verbose          # full report: containers, memory, TLS, disk
actools health --cost             # memory optimization opportunities
actools cost-optimize             # detailed cost analysis with recommendations
actools stats                     # live Docker resource usage (htop-style)
```

---

## Stack management

```bash
actools status                    # container status (docker compose ps)
actools logs [service]            # stream logs — omit service for all
actools restart [service]         # restart one or all containers
actools update                    # pre-snapshot → pull → drush updb → health check
```

Services: `caddy`, `php_prod`, `worker_prod`, `db`, `redis`

---

## Database & recovery

```bash
actools backup db                 # full encrypted dump now
actools backup binlogs            # rotate and archive binary logs now
actools backup status             # latest dump, binlog count, current position

actools migrate [env]             # show pending migrations + table sizes
actools migrate --apply [env]     # apply with pre-migration backup
actools migrate --rollback [env]  # rollback to pre-migration snapshot
actools migrate --point-in-time "YYYY-MM-DD HH:MM:SS"  # restore to any second
actools migrate --point-in-time "YYYY-MM-DD HH:MM:SS" --dry-run  # preview only

actools restore-test              # verify latest backup integrity
actools restore [env] [file]      # restore with confirmation prompt
```

---

## Disaster recovery

```bash
actools immortalize               # snapshot complete server state → DNA
actools immortalize --upload      # snapshot + upload to rclone remote
actools resurrect --dna <file> --key <key>        # restore on fresh server
actools resurrect --dna <file> --key <key> --dry-run  # preview steps only
```

---

## Preview environments

```bash
actools branch feature-123        # create isolated preview environment
actools branch --list             # list active previews
actools branch --destroy feature-123  # destroy a preview
actools branch --cleanup          # remove previews older than 7 days
```

Each preview gets its own database, PHP container, and Caddy vhost with auto-TLS at `feature-123.yourdomain.com`.

---

## GDPR compliance

```bash
actools gdpr export user@example.com   # Art.15 — export all data for a user
actools gdpr delete user@example.com   # Art.17 — delete user + all content
actools gdpr audit  user@example.com   # audit trail for a specific user
actools gdpr report                    # full compliance status report
```

---

## Drupal

```bash
actools drush [env] [command]     # run any drush command
actools shell [service]           # bash inside a container
```

Examples:
```bash
actools drush prod cache:rebuild
actools drush prod user:login admin
actools shell php_prod
```

---

## Worker & PDF

```bash
actools worker-logs               # stream worker container logs
actools worker-status             # Drupal queue depth and status
actools worker-run                # trigger queue worker manually
actools pdf-test                  # test XeLaTeX compilation in worker
```

---

## Storage

```bash
actools storage-test              # S3 PUT → GET → DELETE round-trip
actools storage-info              # provider, bucket, endpoint, CDN host
```

---

## Network & TLS

```bash
actools caddy-reload              # zero-downtime Caddy config reload
actools tls-status                # certificate expiry dates for all domains
```

---

## Observability

```bash
actools redis-info                # Redis memory usage and hit rate
actools slow-log [env]            # PHP-FPM slow request log
```

---

## CI/CD generation

```bash
actools ci --generate                          # GitHub Actions pipelines
actools ci --generate --platform=gitlab        # GitLab CI pipeline
```

Generates three workflows: test (on every PR), deploy (on merge to main), security (weekly).

---

## AI assistant

```bash
actools ai "question"             # ask anything about your codebase
actools ai explain modules/backup/db-full-backup.sh
actools ai review --security      # security review of entire codebase
actools ai review --performance   # performance review
actools ai context                # rebuild codebase index
```

Model: deepseek-coder:1.3b running locally via Ollama. Answers reference actual function names and line numbers.

---

*Back to [docs index](README.md)*
