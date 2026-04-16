# Actools Audit — Fix Catalog
## docs/fix_catalog.md

Every WARN and FAIL from `actools audit` maps to a FIX_ID here.
Future: `actools fix --id ACT-*` will auto-remediate where safe.

---

## CRITICAL / Security

| FIX_ID | Issue | Fix command |
|--------|-------|-------------|
| ACT-SEC-04 | trusted_host_patterns not configured or spoof not rejected | Add `$settings['trusted_host_patterns']` to settings.php |
| ACT-SEC-05 | Security advisories found for installed modules | `drush pm:security` → update affected modules |
| ACT-PRIV-01 | Private file path not configured | Set `$settings['file_private_path']` in settings.php |
| ACT-TLS-01 | TLS certificate expiring or expired | `actools tls-status` — verify Caddy ACME renewal |
| ACT-STACK-01 | Containers not all running | `docker compose up -d` — `actools status` |
| ACT-STACK-02 | Site not responding | `actools health` — `actools logs` |
| ACT-STACK-03 | MariaDB unreachable | `docker compose restart db` |
| ACT-DISK-01 | Disk usage critical (>90%) | `df -h` — clear old backups and logs |

---

## High

| FIX_ID | Issue | Fix command |
|--------|-------|-------------|
| ACT-CFG-01 | Config drift detected | `drush config:import` |
| ACT-CFG-02 | settings.php insecure (error display, session cookies) | Edit settings.php — set error_level = 'hide', cookie_secure = TRUE |
| ACT-REDIS-01 | Redis not confirmed as Drupal cache backend | Verify `$settings['cache']` in settings.php — `actools drush prod cr` |
| ACT-REDIS-02 | Redis behavioral test failed (write/read/TTL) | `actools redis-info` — check eviction policy |
| ACT-BKUP-01 | No backup or backup too old | `actools backup` — verify cron with `crontab -l` |
| ACT-MEM-01 | Available memory low (<256MB) | `free -h` — `actools oom` — consider server upgrade |
| ACT-SEC-01 | HSTS or HTTPS redirect missing | Add `Strict-Transport-Security` to Caddyfile |
| ACT-SEC-02 | Security headers missing (X-Frame, X-Content-Type, Referrer) | Add missing headers to Caddyfile header block |

---

## Medium

| FIX_ID | Issue | Fix command |
|--------|-------|-------------|
| ACT-CRON-01 | Cron not run in last 2 hours | `drush cron` — verify cron container or system cron |
| ACT-WORK-01 | Worker container unhealthy or not processing | `actools pdf-test` — `actools worker-logs` |
| ACT-WORK-02 | Queue worker enqueue test failed | `actools worker-status` — `actools worker-run` |
| ACT-HTTP-01 | Cache-Control or compression headers missing | Verify Caddyfile `encode` and `header` directives |
| ACT-SEC-03 | Docker images using :latest tag | Pin versions in docker-compose.yml |
| ACT-DB-01 | Database prefix is default | Set prefix in settings.php (reduces automated attack surface) |

---

## Low

| FIX_ID | Issue | Fix command |
|--------|-------|-------------|
| ACT-SEC-02 | Minor header issues (Referrer-Policy) | Add to Caddyfile header block |
| ACT-PERF-01 | TTFB high (>2000ms) | `actools slow-log prod` — `actools redis-info` |

---

## Pro Tier (actools audit --deep)

| FIX_ID | Issue | Available in |
|--------|-------|-------------|
| ACT-BKUP-01 | Backup restore test (verify backup integrity) | Pro — `--deep` |
| ACT-SEC-DEEP | OWASP ZAP passive scan | Pro — `--deep` |
| ACT-SEC-TLS | SSLyze TLS configuration analysis | Pro — `--deep` |
| ACT-SEC-PORT | Nmap port scan | Pro — `--deep` |
| ACT-SEC-MOD | Drupal Security Review module full scan | Pro — `--deep` |

---

*fix_catalog.md — Actools Audit v1.0*
*Parent: modules/audit/audit.sh*
