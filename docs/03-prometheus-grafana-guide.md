# 03 — Prometheus & Grafana: Usage Guide for Actools

> **Applies to:** Actools v11.0+ · Prometheus 3.x · Grafana 11.x  
> **Access:** `ssh -L 3000:localhost:3000 actools@feesix.com` → http://localhost:3000  
> **Login:** `admin` / `actools_grafana`

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Starting & Stopping the Observability Stack](#2-starting--stopping-the-observability-stack)
3. [Accessing Grafana Securely](#3-accessing-grafana-securely)
4. [Understanding Your Three Dashboards](#4-understanding-your-three-dashboards)
5. [Prometheus — Querying Your Metrics](#5-prometheus--querying-your-metrics)
6. [Creating Custom Drupal Dashboards](#6-creating-custom-drupal-dashboards)
7. [Setting Up Alerts](#7-setting-up-alerts)
8. [Key Metrics to Watch](#8-key-metrics-to-watch)
9. [Correlating Metrics with Actools Health](#9-correlating-metrics-with-actools-health)
10. [Retention & Storage](#10-retention--storage)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    actools_actools_net                    │
│                                                           │
│  ┌──────────────┐    scrapes every 30s    ┌───────────┐  │
│  │  Prometheus  │ ◄──────────────────── │ cAdvisor  │  │
│  │  :9090       │                         │ (Docker)  │  │
│  │              │ ◄──────────────────── │node_export│  │
│  │  30d retention│                        │ (system)  │  │
│  └──────┬───────┘ ◄──────────────────── │redis_exp  │  │
│         │                                └───────────┘  │
│         │ data source                                     │
│         ▼                                                 │
│  ┌──────────────┐                                        │
│  │   Grafana    │  ← SSH tunnel → your browser          │
│  │   :3000      │                                        │
│  │  3 dashboards│                                        │
│  └──────────────┘                                        │
└─────────────────────────────────────────────────────────┘
```

**What each exporter collects:**

| Exporter | What it monitors |
|----------|-----------------|
| `node_exporter` | CPU, RAM, disk, network, load average for the whole server |
| `cAdvisor` | Per-container CPU, memory, network I/O for all Docker containers |
| `redis_exporter` | Redis hit rate, memory usage, commands per second, evictions |

**What is NOT collected yet (Phase 5 additions):**
- MariaDB slow query metrics (requires `mysqld_exporter`)
- PHP-FPM process metrics (requires `php-fpm_exporter`)
- Drupal application metrics (requires custom instrumentation)
- XeLaTeX job duration (requires custom metric)

---

## 2. Starting & Stopping the Observability Stack

The observability stack is separate from the main Actools stack to keep it optional.

```bash
# Start
docker compose -f /home/actools/docker-compose.observability.yml up -d

# Stop
docker compose -f /home/actools/docker-compose.observability.yml down

# Check status
docker compose -f /home/actools/docker-compose.observability.yml ps

# View logs
docker logs actools_prometheus 2>&1 | tail -20
docker logs actools_grafana 2>&1 | tail -20
```

### Auto-start on Boot

```bash
# Add to /etc/cron.d/actools-observability
@reboot actools cd /home/actools && docker compose -f docker-compose.observability.yml up -d
```

### Memory Usage of Observability Stack

From your actual server data:
- Prometheus: ~112MB
- Grafana: ~91MB
- cAdvisor: ~115MB
- node_exporter: ~15MB
- redis_exporter: ~10MB

**Total overhead: ~343MB** — well within your 6.3GB available RAM.

---

## 3. Accessing Grafana Securely

### SSH Tunnel (Recommended)

Port 3000 is bound to `127.0.0.1` — not publicly accessible. Access via tunnel:

**On your local machine (Windows PowerShell / Mac Terminal):**

```bash
# Open tunnel — keep this terminal open while using Grafana
ssh -L 3000:localhost:3000 -N actools@feesix.com

# If you need to specify SSH key:
ssh -L 3000:localhost:3000 -N -i ~/.ssh/your_key actools@feesix.com
```

Then open: **http://localhost:3000**

### Change the Default Password

Do this immediately after first login:

```bash
# Via API
curl -s -X PUT http://localhost:3000/api/user/password \
  -H "Content-Type: application/json" \
  -u admin:actools_grafana \
  -d '{"oldPassword":"actools_grafana","newPassword":"your_strong_password","confirmNew":"your_strong_password"}'
```

Or: Grafana → Profile icon → Change Password

### Create Read-Only Users for Team

```bash
# Create a viewer account for team members
curl -s -X POST http://localhost:3000/api/admin/users \
  -H "Content-Type: application/json" \
  -u admin:YOUR_ADMIN_PASS \
  -d '{
    "name": "Team Viewer",
    "email": "team@feesix.com",
    "login": "viewer",
    "password": "viewer_password",
    "role": "Viewer"
  }'
```

---

## 4. Understanding Your Three Dashboards

### Dashboard 1: Node Exporter Full

**URL:** http://localhost:3000/d/rYdddlPWk

This dashboard monitors the **entire server** (not just Docker containers).

**Key panels to watch:**

| Panel | What to look for | Alert threshold |
|-------|-----------------|-----------------|
| CPU Busy | Should be <70% normally | >85% sustained |
| RAM Used | Your server has 7.6GB | >80% = 6GB+ used |
| Disk Space Used % | Currently 19% | >80% = action needed |
| Load Average | Should match CPU count (4 cores) | >4.0 sustained |
| Network Traffic | Baseline your normal traffic | Sudden spikes = attack |

**Interpreting Load Average:**
- Your server has 4 CPU cores
- Load 1.0 = 1 core fully busy
- Load 4.0 = all cores at 100%
- Load >4.0 = processes waiting — system is overloaded

**Disk I/O panels:**
- `Disk Read/Write` — XeLaTeX PDF generation shows as write spikes
- `Disk Utilization` — should be <70% normally; >90% means I/O bottleneck

### Dashboard 2: cAdvisor Exporter

**URL:** http://localhost:3000/d/pMEd7m0Mz

This dashboard monitors **individual Docker containers**.

**How to filter to your containers:**

1. At the top, find the `container_name` dropdown
2. Select containers: `actools_caddy`, `actools_db`, `actools_php_prod`, `actools_worker_prod`, `actools_redis`

**Key panels:**

| Panel | Container to watch | What to look for |
|-------|-------------------|-----------------|
| Memory Usage | actools_db | Currently 181MB of 2GB limit (8%) |
| Memory Usage | actools_php_prod | 148MB of 512MB limit (28%) |
| Memory Usage | actools_worker_prod | Spikes during PDF generation |
| CPU Usage | actools_worker_prod | High during XeLaTeX compilation |
| Network I/O | actools_caddy | Your incoming traffic volume |

**XeLaTeX Job Identification:**
When a PDF is being generated, you will see:
- `actools_worker_prod` CPU spike to 80-100%
- `actools_worker_prod` memory jump from ~1MB to 200-400MB
- Duration: 2-30 seconds depending on document complexity

### Dashboard 3: Redis Dashboard

**URL:** http://localhost:3000/d/e008bc3f

**Key metrics for Drupal caching:**

| Metric | Current value | What it means |
|--------|--------------|---------------|
| Hit Rate | Monitor this | Should be >90% when site has traffic |
| Used Memory | 987KB | Very low — Redis barely being used |
| Max Memory | 244MB | Your configured limit |
| Evicted Keys | 0 | Good — no data being evicted |
| Commands/sec | Monitor during traffic | Correlates with Drupal page views |

**Interpreting Hit Rate:**
- 0% = Redis connected but nothing cached yet (cold start)
- 50% = Caching is working but cache is still warming up
- >90% = Good — most requests served from cache
- 100% = Rarely achievable in practice

**Note:** Your Redis hit rate will start at 0% and increase as the site gets traffic and the cache warms up. After 24-48 hours of normal traffic, expect >85%.

---

## 5. Prometheus — Querying Your Metrics

Access Prometheus directly: Open SSH tunnel with port 9090 also forwarded:

```bash
ssh -L 3000:localhost:3000 -L 9090:localhost:9090 -N actools@feesix.com
```

Then: **http://localhost:9090**

### Essential PromQL Queries

**Container memory usage (bytes):**
```promql
container_memory_usage_bytes{name=~"actools_.*"}
```

**Container CPU percentage:**
```promql
rate(container_cpu_usage_seconds_total{name=~"actools_.*"}[5m]) * 100
```

**Server RAM available:**
```promql
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

**Disk space remaining:**
```promql
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100
```

**Redis hit rate:**
```promql
rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100
```

**Network traffic in (bytes/sec):**
```promql
rate(node_network_receive_bytes_total{device="eth0"}[5m])
```

**Worker container memory over time:**
```promql
container_memory_usage_bytes{name="actools_worker_prod"}
```

### Useful Time Ranges

- `[5m]` — last 5 minutes (for rate calculations)
- `[1h]` — last hour (for trend analysis)
- `[24h]` — last 24 hours (for daily patterns)
- `[7d]` — last 7 days (for weekly patterns, needs 7d of data)

---

## 6. Creating Custom Drupal Dashboards

### Add a Drupal-Specific Dashboard

```bash
# Create a custom dashboard via Grafana API
cat > /tmp/drupal-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "Drupal Application Metrics",
    "panels": [
      {
        "title": "PHP Worker Memory",
        "type": "timeseries",
        "targets": [{
          "expr": "container_memory_usage_bytes{name=\"actools_php_prod\"} / 1048576",
          "legendFormat": "PHP Memory (MiB)"
        }],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "title": "XeLaTeX Worker Memory",
        "type": "timeseries",
        "targets": [{
          "expr": "container_memory_usage_bytes{name=\"actools_worker_prod\"} / 1048576",
          "legendFormat": "Worker Memory (MiB)"
        }],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "title": "Redis Cache Hit Rate",
        "type": "gauge",
        "targets": [{
          "expr": "rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100",
          "legendFormat": "Hit Rate %"
        }],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 70},
                {"color": "green", "value": 90}
              ]
            },
            "max": 100,
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 8}
      },
      {
        "title": "MariaDB Container Memory",
        "type": "timeseries",
        "targets": [{
          "expr": "container_memory_usage_bytes{name=\"actools_db\"} / 1048576",
          "legendFormat": "DB Memory (MiB)"
        }],
        "gridPos": {"h": 8, "w": 16, "x": 8, "y": 8}
      }
    ]
  },
  "folderId": 0,
  "overwrite": true
}
EOF

curl -s -X POST http://localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -u admin:YOUR_PASS \
  -d @/tmp/drupal-dashboard.json | python3 -m json.tool | grep -E "title|uid|message"
```

### Adding MariaDB Metrics (Phase 5)

To get MariaDB query metrics in Grafana, add `mysqld_exporter`:

```yaml
# Add to docker-compose.observability.yml
  mysqld_exporter:
    image: prom/mysqld-exporter:latest
    container_name: actools_mysqld_exporter
    restart: unless-stopped
    environment:
      DATA_SOURCE_NAME: "backup:YOUR_BACKUP_PASS@tcp(actools_db:3306)/"
    networks:
      - actools_actools_net
```

Then add to `prometheus.yml`:
```yaml
  - job_name: 'mariadb'
    static_configs:
      - targets: ['mysqld_exporter:9104']
```

Import dashboard ID `7362` (MariaDB Overview) from Grafana.com.

---

## 7. Setting Up Alerts

### Configure Email Alerting

In Grafana (via UI):

1. Navigate to: **Alerting → Contact points → Add contact point**
2. Name: `email-admin`
3. Type: Email
4. Addresses: `mpal_singh@yahoo.com`
5. Save

Or via API:

```bash
curl -s -X POST http://localhost:3000/api/v1/provisioning/contact-points \
  -H "Content-Type: application/json" \
  -u admin:YOUR_PASS \
  -d '{
    "name": "email-admin",
    "type": "email",
    "settings": {
      "addresses": "mpal_singh@yahoo.com",
      "subject": "Actools Alert: {{ .GroupLabels.alertname }}"
    }
  }'
```

### Configure Webhook (Slack/Telegram)

```bash
curl -s -X POST http://localhost:3000/api/v1/provisioning/contact-points \
  -H "Content-Type: application/json" \
  -u admin:YOUR_PASS \
  -d '{
    "name": "webhook",
    "type": "webhook",
    "settings": {
      "url": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
    }
  }'
```

### Essential Alert Rules

**Alert 1: High Memory Usage**

```bash
curl -s -X POST http://localhost:3000/api/v1/provisioning/alert-rules \
  -H "Content-Type: application/json" \
  -u admin:YOUR_PASS \
  -d '{
    "title": "High Server Memory",
    "condition": "C",
    "data": [
      {
        "refId": "A",
        "queryType": "",
        "relativeTimeRange": {"from": 300, "to": 0},
        "datasourceUid": "dfh5nngt9rhtse",
        "model": {
          "expr": "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)",
          "refId": "A"
        }
      },
      {
        "refId": "C",
        "queryType": "",
        "datasourceUid": "__expr__",
        "model": {
          "type": "threshold",
          "refId": "C",
          "conditions": [{"evaluator": {"params": [85], "type": "gt"}}]
        }
      }
    ],
    "for": "5m",
    "labels": {"severity": "warning"},
    "annotations": {"summary": "Server memory above 85%"}
  }'
```

**Alert 2: Disk Space Low**

Create via Grafana UI:
- Metric: `node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100`
- Condition: Less than `20`
- Duration: 5 minutes
- Message: "Disk space below 20% — current: {{ $value }}%"

**Alert 3: Container Down**

```promql
# Alert when any actools container stops
absent(container_last_seen{name=~"actools_caddy|actools_db|actools_php_prod"})
```

**Alert 4: XeLaTeX Worker OOM**

```promql
# Alert when worker memory exceeds 1.8GB (90% of 2GB limit)
container_memory_usage_bytes{name="actools_worker_prod"} > 1932735283
```

---

## 8. Key Metrics to Watch

### Daily Check (30 seconds)

```bash
actools health --verbose
```

This gives you the same information as checking Grafana manually, but in your terminal.

### Weekly Grafana Review

Open these panels each week and look for trends:

**1. Memory trend (Node Exporter Full → RAM Used)**
- Is memory usage creeping up week over week?
- Gradual increase = memory leak somewhere

**2. Disk I/O (Node Exporter Full → Disk R/W)**
- Heavy write during off-hours = backup or XeLaTeX batch jobs
- Heavy read during business hours = normal Drupal serving

**3. Container memory peak (cAdvisor → Memory Usage)**
- Filter to `actools_worker_prod`
- What is the peak memory during PDF generation?
- If >1.5GB, start planning for remote XeLaTeX (XELATEX_MODE=remote)

**4. Redis efficiency (Redis Dashboard → Hit Rate)**
- After 7 days of traffic, this should be >80%
- If <50% after a week, check that Redis module is enabled in Drupal

### Monthly Review

```bash
# Run cost optimization
actools cost-optimize

# Compare with last month's Grafana data
# Go to: Node Exporter → set time range to "Last 30 days"
# Check: Peak RAM, Peak CPU, Disk growth rate
```

---

## 9. Correlating Metrics with Actools Health

The `actools health --verbose` command and Grafana show the same underlying data — but from different angles.

| `actools health --verbose` | Equivalent Grafana query |
|---------------------------|-------------------------|
| Container status | cAdvisor → Container Running |
| PHP memory 148MiB/512MiB (28%) | cAdvisor → Memory Usage (php_prod) |
| TLS expires in 89 days | node_exporter + custom scraper |
| Disk 19% used | Node Exporter → Disk Space Used % |
| Slow queries: 0 | mysqld_exporter (Phase 5) |
| Redis evictions: 0 | Redis Dashboard → Evicted Keys |

**When to use which:**
- `actools health --verbose` — quick daily check, automation, alerts
- Grafana — trend analysis, debugging, presenting to stakeholders

### Setting Up Correlation Workflow

When `actools health --verbose` shows an issue:

```
✗ actools_worker_prod — restarting
```

1. Open Grafana → cAdvisor → filter to `actools_worker_prod`
2. Set time range to last 1 hour
3. Look at Memory Usage panel — did it spike to 2GB before dying?
4. Look at CPU panel — was it processing something when it died?
5. Cross-reference with: `docker logs actools_worker_prod 2>&1 | tail -50`

---

## 10. Retention & Storage

### Current Configuration

- Prometheus retention: 30 days
- Data location: Docker named volume `actools_prometheus_data`
- Grafana data: Docker named volume `actools_grafana_data`

### Check Current Storage Usage

```bash
# Prometheus data size
docker run --rm -v actools_prometheus_data:/data busybox \
  du -sh /data

# Grafana data size
docker run --rm -v actools_grafana_data:/data busybox \
  du -sh /data
```

### Adjust Retention Period

Edit `docker-compose.observability.yml`:

```yaml
prometheus:
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
    - '--storage.tsdb.retention.time=90d'    # ← Change from 30d
    - '--storage.tsdb.retention.size=5GB'    # ← Add size limit
```

### Estimated Storage Growth

Based on your 5-container stack with 30-second scrape interval:

- ~3MB/day for your current setup
- ~90MB for 30-day retention
- ~270MB for 90-day retention

This is well within your 59GB free disk space.

### Backup Grafana Dashboards

```bash
# Export all dashboards as JSON
for uid in rYdddlPWk pMEd7m0Mz e008bc3f; do
  curl -s -u admin:YOUR_PASS \
    "http://localhost:3000/api/dashboards/uid/${uid}" \
    > "/home/actools/backups/grafana-dashboard-${uid}-$(date +%F).json"
done

# Or export all at once
curl -s -u admin:YOUR_PASS \
  "http://localhost:3000/api/search?type=dash-db" \
  | python3 -c "import sys,json; [print(d['uid']) for d in json.load(sys.stdin)]" \
  | while read uid; do
    curl -s -u admin:YOUR_PASS \
      "http://localhost:3000/api/dashboards/uid/$uid" \
      > "/home/actools/backups/grafana-$uid-$(date +%F).json"
  done
```

### Quick Reference Card

```
Grafana:    http://localhost:3000 (via SSH tunnel)
Prometheus: http://localhost:9090 (via SSH tunnel)
SSH Tunnel: ssh -L 3000:localhost:3000 -L 9090:localhost:9090 -N actools@feesix.com

Dashboards:
  Node Exporter Full  → /d/rYdddlPWk  (server-wide metrics)
  cAdvisor            → /d/pMEd7m0Mz  (per-container metrics)
  Redis               → /d/e008bc3f   (cache metrics)

Key PromQL:
  Worker memory:  container_memory_usage_bytes{name="actools_worker_prod"} / 1048576
  Redis hit rate: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100
  Free disk:      node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100
  Server load:    node_load1
```

---

*Last updated: March 2026 · Actools v11.0 · [Back to docs index](../readme.md)*
