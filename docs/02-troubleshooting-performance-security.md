# 02 — Troubleshooting, Performance & Security: MariaDB · Caddy · XeLaTeX

> **Applies to:** Actools v11.0+ · MariaDB 11.4 · Caddy 2.8 · XeLaTeX (texlive)  
> **Quick health check:** `actools health --verbose`

---

## Table of Contents

1. [MariaDB — Troubleshooting](#1-mariadb--troubleshooting)
2. [MariaDB — Performance Tuning](#2-mariadb--performance-tuning)
3. [MariaDB — Security Hardening](#3-mariadb--security-hardening)
4. [Caddy — Troubleshooting](#4-caddy--troubleshooting)
5. [Caddy — Performance Tuning](#5-caddy--performance-tuning)
6. [Caddy — Security Hardening](#6-caddy--security-hardening)
7. [XeLaTeX — Troubleshooting](#7-xelatex--troubleshooting)
8. [XeLaTeX — Performance Tuning](#8-xelatex--performance-tuning)
9. [XeLaTeX — Security Hardening](#9-xelatex--security-hardening)
10. [Common Error Reference](#10-common-error-reference)

---

## 1. MariaDB — Troubleshooting

### Container Not Starting

```bash
# Check container status
docker compose ps db

# Check logs — always start here
docker logs actools_db 2>&1 | tail -30

# Common causes and fixes:
```

**Error: `Permission denied` on `/var/log/mysql/slow.log`**
```bash
# Fix: Pre-create log file with correct ownership
sudo touch /home/actools/logs/db/slow.log
sudo chown 999:999 /home/actools/logs/db/slow.log
sudo chmod 664 /home/actools/logs/db/slow.log
docker compose restart db
```

**Error: `healthcheck.sh: not found`**
```bash
# This means you're using mysqladmin (removed in MariaDB 11.4)
# Fix: Check docker-compose.yml healthcheck section
grep "healthcheck" /home/actools/docker-compose.yml
# Should show: healthcheck.sh --connect --innodb_initialized
# NOT: mysqladmin ping
```

**Error: `Access denied for user 'root'`**
```bash
# Password mismatch between container and actools.env
# Get the password the container was started with:
docker inspect actools_db --format='{{range .Config.Env}}{{println .}}{{end}}' | grep MARIADB_ROOT

# Compare with actools.env:
grep DB_ROOT_PASS /home/actools/actools.env

# If they differ, either:
# 1. Reset the password:
docker exec actools_db mariadb -uroot -p"OLD_PASS" -e \
  "ALTER USER 'root'@'%' IDENTIFIED BY 'NEW_PASS';"
# 2. Or drop and recreate the volume (loses all data):
docker compose down && docker volume rm actools_db_data
```

**Error: `InnoDB: innodb_log_file_size` mismatch**
```bash
# This happens when you change innodb_log_file_size with existing data
# Fix: Stop DB, remove old log files, restart
docker compose stop db
docker run --rm -v actools_db_data:/var/lib/mysql busybox \
  rm -f /var/lib/mysql/ib_logfile0 /var/lib/mysql/ib_logfile1
docker compose start db
```

### Connection Issues from PHP

```bash
# Test connection from inside php_prod container
docker compose exec -T php_prod bash -c \
  "php -r \"new PDO('mysql:host=db;dbname=actools_prod', 'actools_prod', 'PASS');\""

# Check network connectivity
docker compose exec php_prod ping -c 3 db

# Check MariaDB is listening
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" \
  -e "SHOW STATUS LIKE 'Threads_connected';"
```

### Slow Queries

```bash
# View slow query log
sudo tail -f /home/actools/logs/db/slow.log

# Or via Actools CLI
actools slow-log prod

# Count slow queries since startup
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN \
  -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';"

# Find the worst queries
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" \
  -e "SELECT * FROM information_schema.processlist WHERE time > 5 ORDER BY time DESC;"
```

### Database Corruption

```bash
# Check all tables in a database
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" actools_prod \
  -e "CHECK TABLE $(docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN \
  -e "SELECT GROUP_CONCAT(table_name) FROM information_schema.tables \
  WHERE table_schema='actools_prod';")"

# Repair a specific table
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" actools_prod \
  -e "REPAIR TABLE cache_data;"

# Full repair (use only when DB won't start)
docker exec actools_db mariadb-check \
  -uroot -p"${DB_ROOT_PASS}" --all-databases --auto-repair
```

---

## 2. MariaDB — Performance Tuning

### Current Performance Snapshot

```bash
# InnoDB buffer pool hit rate (should be >99%)
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN -e "
SELECT ROUND((1 - (
  SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS
  WHERE VARIABLE_NAME='Innodb_buffer_pool_reads'
) / (
  SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS
  WHERE VARIABLE_NAME='Innodb_buffer_pool_read_requests'
)) * 100, 2) AS buffer_pool_hit_rate;"

# Key statistics
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e "
SHOW GLOBAL STATUS WHERE Variable_name IN (
  'Queries', 'Slow_queries', 'Threads_connected',
  'Innodb_buffer_pool_read_requests', 'Innodb_buffer_pool_reads',
  'Key_reads', 'Key_read_requests'
);"
```

### Tuning my.cnf for Actools Stack

Edit `/home/actools/my.cnf` and restart:

```ini
[mysqld]
# Buffer pool — set to 50-60% of DB_MEMORY_LIMIT
# Current: 2g limit, 181MB actual usage → reduce to 512MB
innodb_buffer_pool_size = 512M
innodb_buffer_pool_instances = 1   # 1 per GB of buffer pool

# Log file size — larger = less flushing, more recovery time
innodb_log_file_size = 256M

# Flush behaviour — 1=safest (fsync on commit), 2=faster (OS cache)
innodb_flush_log_at_trx_commit = 1

# Connection limits
max_connections = 100
wait_timeout = 300         # Kill idle connections after 5 min
interactive_timeout = 300

# Query cache (disabled in MariaDB 10.1.7+, use Redis instead)
query_cache_size = 0
query_cache_type = 0

# Slow query logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
log_queries_not_using_indexes = 1

# Binary logging (needed for replication/backup tools)
# Disable if not using replication to save I/O
skip-log-bin

# Character set
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

# Table cache
table_open_cache = 2000
table_definition_cache = 1000

# InnoDB I/O
innodb_io_capacity = 200       # HDD: 200, SSD: 2000
innodb_io_capacity_max = 400   # HDD: 400, SSD: 4000
```

```bash
# Apply changes
docker compose restart db
sleep 10
actools health --verbose
```

### Index Optimisation

```bash
# Find tables missing primary keys
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e "
SELECT t.table_schema, t.table_name
FROM information_schema.tables t
LEFT JOIN information_schema.table_constraints tc
  ON t.table_schema = tc.table_schema
  AND t.table_name = tc.table_name
  AND tc.constraint_type = 'PRIMARY KEY'
WHERE t.table_schema = 'actools_prod'
  AND tc.constraint_name IS NULL;"

# Show all indexes on a table
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" actools_prod \
  -e "SHOW INDEX FROM node;"

# Analyse query plan for slow queries
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" actools_prod \
  -e "EXPLAIN SELECT * FROM search_index WHERE word = 'drupal';"
```

### Memory Allocation

Based on Actools cost-optimize output (your server shows DB using 181MB of 2048MB):

```bash
# Current waste: 1.7GB over-allocated
# Recommended: reduce DB_MEMORY_LIMIT to 512m in actools.env
# Update docker-compose.yml and restart:
docker compose up -d db
```

---

## 3. MariaDB — Security Hardening

### Remove Unnecessary Users

```bash
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e "
SELECT user, host FROM mysql.user;
-- Remove anonymous users:
DELETE FROM mysql.user WHERE user='';
-- Remove test database:
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;"
```

### Restrict Root Login

```bash
# Root should only connect from localhost inside the container
docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e "
UPDATE mysql.user SET host='localhost' WHERE user='root' AND host='%';
FLUSH PRIVILEGES;"
```

### Enable Password Validation

```ini
# Add to my.cnf
[mysqld]
plugin_load_add = simple_password_check
simple_password_check_digits = 1
simple_password_check_letters_same_case = 1
simple_password_check_other_characters = 1
simple_password_check_minimal_length = 16
```

### Audit Logging (Phase 5)

```ini
# my.cnf — log all queries for audit trail
[mysqld]
plugin_load_add = server_audit
server_audit_logging = ON
server_audit_events = CONNECT,QUERY_DDL,QUERY_DML_NO_SELECT
server_audit_file_path = /var/log/mysql/audit.log
```

### Backup Security

```bash
# Verify backup integrity
sha256sum -c /home/actools/backups/prod_db_$(date +%F).sql.gz.sha256

# Test restore (never test in production — use a preview environment)
actools branch backup-test
# Then restore into the preview DB and verify
```

---

## 4. Caddy — Troubleshooting

### Container Not Starting

```bash
# Check logs
docker logs actools_caddy 2>&1 | tail -20

# Validate Caddyfile syntax without restarting
docker exec actools_caddy caddy validate --config /etc/caddy/Caddyfile

# Common errors and fixes:
```

**Error: `Unexpected next token after '{' on same line`**
```bash
# Caddy 2.8 requires multi-line blocks
# WRONG:
# log { level INFO }
# CORRECT:
# log {
#     level INFO
# }
```

**Error: `no such host` / TLS certificate not obtained**
```bash
# DNS not resolving — Caddy can't get Let's Encrypt cert
nslookup feesix.com
# Should return: 46.62.200.12

# Check Caddy logs for ACME details
docker logs actools_caddy 2>&1 | grep -i "acme\|certificate\|tls"

# Force certificate renewal
docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile
```

**Error: `no upstreams available`**
```bash
# PHP-FPM container is down
docker compose ps php_prod
docker logs actools_php_prod 2>&1 | tail -10
docker compose restart php_prod
```

### Zero-Downtime Reload

```bash
# Use caddy reload, NOT docker compose restart caddy
# reload: zero-downtime config update
# restart: brief downtime (connections dropped)

docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile

# Or via Actools CLI
actools caddy-reload
```

### Check Active Certificates

```bash
actools tls-status

# Check expiry directly
echo | openssl s_client -connect feesix.com:443 -servername feesix.com 2>/dev/null \
  | openssl x509 -noout -dates
```

### Rate Limit Testing

```bash
# Test that rate limiting is working on login endpoint
for i in {1..6}; do
  curl -sI -X POST https://feesix.com/user/login | grep -E "HTTP|Retry"
done
# 6th request should return 429 Too Many Requests
```

---

## 5. Caddy — Performance Tuning

### HTTP/3 QUIC Performance

Your current Caddyfile already has `protocols h1 h2 h3`. Verify HTTP/3 is working:

```bash
# Check alt-svc header (advertises HTTP/3 support)
curl -sI https://feesix.com | grep alt-svc
# Should show: alt-svc: h3=":443"; ma=2592000
```

### Enable OCSP Stapling

Add to Caddyfile global block:

```caddyfile
{
    email mpal_singh@yahoo.com
    log {
        level INFO
    }
    servers {
        protocols h1 h2 h3
    }
    # OCSP stapling — reduces TLS handshake time
    ocsp_stapling on
}
```

### Static File Caching

Your current Caddyfile already has:
```caddyfile
header @static Cache-Control "public, max-age=31536000, immutable"
```

Extend to include fonts and additional types:

```caddyfile
@static {
    file
    path *.css *.js *.png *.jpg *.jpeg *.gif *.svg
         *.woff2 *.woff *.ttf *.eot *.ico *.pdf *.webp
}
```

### Compression

Your Caddyfile has `encode zstd gzip`. Verify it's working:

```bash
curl -sI -H "Accept-Encoding: br,gzip,deflate" https://feesix.com \
  | grep content-encoding
# Should show: content-encoding: zstd or gzip
```

### Connection Limits (Phase 5)

```caddyfile
{
    servers {
        protocols h1 h2 h3
        max_header_size 16KB
        timeouts {
            read_body   10s
            read_header 10s
            write        30s
            idle        120s
        }
    }
}
```

---

## 6. Caddy — Security Hardening

### Current Security Headers

Your Caddyfile already sets:
```caddyfile
Strict-Transport-Security "max-age=31536000; includeSubDomains"
X-Content-Type-Options    "nosniff"
X-Frame-Options           "SAMEORIGIN"
Referrer-Policy           "strict-origin-when-cross-origin"
-Server                   # Removes Server header
```

### Add Content Security Policy (CSP)

Add to the `header` block in `drupal_base` snippet:

```caddyfile
header {
    # Existing headers...
    Content-Security-Policy "
        default-src 'self';
        script-src 'self' 'unsafe-inline' 'unsafe-eval';
        style-src 'self' 'unsafe-inline';
        img-src 'self' data: https:;
        font-src 'self' data:;
        frame-ancestors 'none';
        base-uri 'self';
        form-action 'self';
    "
    Permissions-Policy "geolocation=(), microphone=(), camera=()"
}
```

### HSTS Preloading

To add feesix.com to browser HSTS preload lists:

```caddyfile
Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
```

Then submit at: https://hstspreload.org

### Block Bad Bots

```caddyfile
@badbots {
    header User-Agent *AhrefsBot*
    header User-Agent *SemrushBot*
    header User-Agent *MJ12bot*
    header User-Agent *DotBot*
}
respond @badbots 403
```

### Block by Country (Cloudflare — Phase 5)

Move behind Cloudflare and use Cloudflare's geo-blocking rules instead of server-level blocking.

### Admin Path Restriction

```caddyfile
@admin {
    path /admin/* /user/login
}
# Allow only specific IPs to admin
@adminblock {
    path /admin/* /user/login
    not remote_ip 1.2.3.4/32  # Your office/home IP
}
respond @adminblock 403
```

---

## 7. XeLaTeX — Troubleshooting

### Container Health Check

```bash
# Check if XeLaTeX works inside worker container
actools pdf-test

# Manual test
docker exec actools_worker_prod xelatex --version

# Check worker container status
docker compose ps worker_prod
docker logs actools_worker_prod 2>&1 | tail -20
```

### PDF Generation Fails

**Error: `xelatex: command not found`**
```bash
# Worker image wasn't built with XeLaTeX
# Rebuild the image
docker build -t actools_worker:latest \
  -f /home/actools/Dockerfile.worker \
  /home/actools/
docker compose up -d worker_prod
actools pdf-test
```

**Error: `! Font ... not found`**
```bash
# Missing font inside the container
docker exec actools_worker_prod bash -c "fc-list | grep -i 'liberation\|dejavu'"

# Install missing fonts (add to Dockerfile.worker before rebuild)
# RUN apt-get install -y fonts-liberation fonts-dejavu
```

**Error: `Emergency stop` / LaTeX compilation error**
```bash
# This is a LaTeX syntax error in your .tex content
# Test with a minimal document inside the container
docker exec actools_worker_prod bash -c "
cat > /tmp/test.tex << 'TEX'
\documentclass{article}
\begin{document}
Hello World
\end{document}
TEX
xelatex -interaction=nonstopmode -output-directory=/tmp /tmp/test.tex
echo Exit code: $?
"
```

**Error: `OOM killed` (worker container)**
```bash
# XeLaTeX is hitting the 2GB memory limit
# Check peak usage
docker stats actools_worker_prod --no-stream

# Increase WORKER_MEMORY_LIMIT in actools.env
# WORKER_MEMORY_LIMIT=3g
# Then update docker-compose.yml and restart
```

### Slow PDF Generation

```bash
# Time a PDF compilation
docker exec actools_worker_prod bash -c "
time xelatex -interaction=nonstopmode \
  -output-directory=/tmp /tmp/test.tex > /dev/null 2>&1"

# Check if swap is being used (bad for performance)
free -h
swapon --show
```

---

## 8. XeLaTeX — Performance Tuning

### Enable Compilation Cache

XeLaTeX caches font metrics between runs. Ensure the cache directory persists:

```yaml
# In docker-compose.yml worker_prod service, add volume:
volumes:
  - ./docroot/prod:/var/www/html/prod
  - ./logs/worker:/var/log/worker
  - xelatex_cache:/root/.texmf-var    # ← Add this
```

```yaml
# At the top-level volumes section:
volumes:
  xelatex_cache:
```

### Precompile Common Preambles

For documents using the same preamble, use XeLaTeX's format files:

```bash
# Inside the worker container, create a format file
docker exec actools_worker_prod bash -c "
cat > /tmp/actools-base.tex << 'TEX'
\documentclass{article}
\usepackage{fontspec}
\usepackage{geometry}
\usepackage{hyperref}
TEX
xelatex -ini -jobname=actools-base \
  '&xelatex /tmp/actools-base.tex\dump'
"
```

### Parallel PDF Generation

```bash
# In your Drupal queue worker, process multiple PDFs in parallel
# (adjust based on available RAM — each XeLaTeX process uses ~200-400MB)
docker compose exec worker_prod bash -c "
  cd /var/www/html/prod
  ./vendor/bin/drush queue:run actools_document_export \
    --time-limit=600 \
    --items-limit=5    # Process 5 PDFs per run
"
```

### Reduce Font Loading Time

```bash
# Rebuild font cache inside the container (run once after adding fonts)
docker exec actools_worker_prod fc-cache -fv
```

---

## 9. XeLaTeX — Security Hardening

### Restrict Shell Access from LaTeX

Add to your XeLaTeX compilation command in PHP:

```php
// In PdfService.php — disable shell escape
$command = sprintf(
  'xelatex -interaction=nonstopmode -no-shell-escape -output-directory=%s %s',
  escapeshellarg($outputDir),
  escapeshellarg($texFile)
);
```

**Never use `-shell-escape`** unless absolutely necessary. It allows LaTeX to execute arbitrary system commands.

### Sanitise User Input Before LaTeX Compilation

```php
// Never pass user input directly to LaTeX
// Sanitise all dynamic content:
function sanitizeForLatex(string $input): string {
    $specialChars = ['\\', '&', '%', '$', '#', '_', '{', '}', '~', '^'];
    foreach ($specialChars as $char) {
        $input = str_replace($char, '\\' . $char, $input);
    }
    return $input;
}
```

### Isolate XeLaTeX Process

The worker container already runs with:
```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - SETUID
  - SETGID
  - DAC_OVERRIDE
```

This prevents privilege escalation. Add read-only filesystem where possible:

```yaml
worker_prod:
  read_only: true
  tmpfs:
    - /tmp:size=512m,mode=1777
    - /root/.texmf-var:size=256m
```

### Scan Generated PDFs

```bash
# Install ClamAV inside the worker container (Phase 5)
# Add to Dockerfile.worker:
# RUN apt-get install -y clamav && freshclam

# Scan before serving
# docker exec actools_worker_prod clamscan /path/to/generated.pdf
```

---

## 10. Common Error Reference

| Error | Component | Cause | Fix |
|-------|-----------|-------|-----|
| `mysqladmin: not found` | MariaDB | MariaDB 11.4 removed mysqladmin | Use `healthcheck.sh --connect` |
| `mysql: not found` | MariaDB | MariaDB 11.4 removed mysql binary | Use `mariadb` instead |
| `pull access denied` | Docker | Trying to pull local image from registry | Add `pull_policy: never` |
| `Unexpected token after '{'` | Caddy | Inline block syntax rejected in 2.8 | Expand to multi-line |
| `unbound variable DB_PASS` | Bash | `set -u` + subshell doesn't inherit vars | Use local variable, not env prefix |
| `Permission denied: slow.log` | MariaDB | Log file owned by root, not UID 999 | `chown 999:999 logs/db/slow.log` |
| `xelatex: not found` | Worker | Worker image built without XeLaTeX | Rebuild image from Dockerfile.worker |
| `Font not found` | XeLaTeX | Missing font package in worker image | Add font package to Dockerfile.worker |
| `OOM killed` | Worker | XeLaTeX exceeded memory limit | Increase `WORKER_MEMORY_LIMIT` |
| `TLS cert not obtained` | Caddy | DNS not resolving to server IP | Fix DNS A record, wait for propagation |
| `no upstreams available` | Caddy | PHP-FPM container down | `docker compose restart php_prod` |
| `403 on /admin` | Caddy | IP restriction active | Check Caddyfile admin path rules |

---

### Daily Health Routine

```bash
# Morning check (30 seconds)
actools health --verbose

# Weekly check
actools cost-optimize
actools health --cost

# After any Drupal update
actools migrate --plan prod
actools drush prod cr
```

---

*Last updated: March 2026 · Actools v11.0 · [Back to docs index](../readme.md)*
