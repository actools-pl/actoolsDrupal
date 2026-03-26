# Observability

> Applies to: Actools v11.0+ · Prometheus · Grafana

---

## Start the observability stack

```bash
docker compose -f docker-compose.observability.yml up -d
```

This adds: Prometheus, Grafana, Node Exporter, cAdvisor, Redis Exporter.

---

## Access Grafana

Grafana runs on port 3000 — not exposed to the internet. Access via SSH tunnel:

```bash
ssh -L 3000:localhost:3000 actools@yourdomain.com
```

Then open: `http://localhost:3000`  
Login: `admin` / value of `GRAFANA_ADMIN_PASS` in `actools.env`

---

## Pre-built dashboards

Three dashboards are installed automatically:

**Node Exporter Full** — server-level metrics
- CPU usage, load average, context switches
- RAM: total, used, cached, buffers
- Disk: I/O, read/write throughput, latency
- Network: bytes in/out, packets, errors

**cAdvisor** — per-container metrics
- CPU per container
- Memory per container vs limits
- Network per container
- Container restart count

**Redis** — cache health
- Hit rate (target: >90%)
- Memory usage vs `maxmemory`
- Commands per second
- Connected clients

---

## Key metrics to watch

```promql
# Memory pressure — container using >80% of its limit
container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.8

# MariaDB connections approaching limit
mysql_global_status_threads_connected / mysql_global_variables_max_connections > 0.8

# Redis hit rate dropping
rate(redis_keyspace_hits_total[5m]) /
(rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))

# Disk filling up
(node_filesystem_size_bytes - node_filesystem_free_bytes) /
node_filesystem_size_bytes > 0.85
```

---

## Alerting

Prometheus alerting rules live in `modules/observability/alerts.yml`. To add an alert:

```yaml
# modules/observability/alerts.yml
groups:
  - name: actools
    rules:
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} memory >85%"
```

Reload Prometheus after changes:
```bash
curl -X POST http://localhost:9090/-/reload
```

---

## Metrics retention

Default: 30 days. Change via `PROMETHEUS_RETENTION_DAYS` in `actools.env`.

```bash
# Current storage used by Prometheus
docker compose exec prometheus du -sh /prometheus
```

---

## CLI shortcuts

```bash
actools redis-info                # Redis memory + hit rate snapshot
actools slow-log prod             # PHP-FPM slow requests (>1s)
actools health --cost             # memory optimization recommendations
actools cost-optimize             # detailed analysis with specific actions
```

---

*Back to [docs index](README.md)*
