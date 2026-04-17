#!/usr/bin/env bash
# Layer 2 — Stack truth (platform around Drupal)

run_stack() {
  section_header "STACK"

  # All containers running
  local containers_up
  containers_up=$(cd "$ACTOOLS_HOME" && docker compose ps --format json 2>/dev/null | \
    python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
total=0; up=0
for l in lines:
  if not l.strip(): continue
  try:
    d=json.loads(l); total+=1
    if d.get('State','')=='running': up+=1
  except: pass
print(f'{up}/{total}')
" 2>/dev/null || echo "?/?")
  local up_count total_count
  up_count=$(echo "$containers_up" | cut -d'/' -f1)
  total_count=$(echo "$containers_up" | cut -d'/' -f2)
  if [[ "$up_count" == "$total_count" && "$up_count" != "?" ]]; then
    record_finding "PASS" "CRITICAL" "Containers: all ${up_count}/${total_count} running" "" "" ""
  else
    record_finding "FAIL" "CRITICAL" \
      "Containers: only ${containers_up} running" \
      "One or more services are down — site may be partially or fully unavailable" \
      "actools status — docker compose ps — docker compose up -d" \
      "ACT-STACK-01"
  fi

  # Site returns 200
  local domain="${BASE_DOMAIN:-localhost}"
  local http_code
  http_code=$(curl -sso /dev/null -w "%{http_code}" --max-time 15 "https://${domain}" 2>/dev/null || echo "000")
  if [[ "$http_code" == "200" ]]; then
    record_finding "PASS" "CRITICAL" "Site response: HTTP ${http_code}" "" "" ""
  else
    record_finding "FAIL" "CRITICAL" \
      "Site not responding: HTTP ${http_code}" \
      "Site is down or returning errors to visitors" \
      "actools health — actools logs — check Caddy and PHP-FPM containers" \
      "ACT-STACK-02"
  fi

  # TLS valid
  local tls_expiry
  tls_expiry=$(echo | openssl s_client -servername "${domain}" -connect "${domain}:443" 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
  if [[ -n "$tls_expiry" ]]; then
    local expiry_epoch
    expiry_epoch=$(date -d "$tls_expiry" +%s 2>/dev/null || echo "0")
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    if (( days_left < 14 )); then
      record_finding "FAIL" "CRITICAL" \
        "TLS certificate expires in ${days_left} days" \
        "Site will show security warnings to all visitors after expiry" \
        "actools tls-status — check Caddy ACME renewal — verify DNS is reachable" \
        "ACT-TLS-01"
    elif (( days_left < 30 )); then
      record_finding "WARN" "HIGH" \
        "TLS certificate expires in ${days_left} days" \
        "Certificate renewal should be automatic — verify it is working" \
        "actools tls-status — check Caddy logs for renewal errors" \
        "ACT-TLS-01"
    else
      record_finding "PASS" "HIGH" "TLS: valid, ${days_left} days remaining" "" "" ""
    fi
  else
    record_finding "WARN" "HIGH" \
      "TLS certificate status could not be checked" \
      "Certificate may be expired or misconfigured" \
      "actools tls-status" \
      "ACT-TLS-01"
  fi

  # Disk pressure
  local disk_pct
  disk_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")
  if (( disk_pct >= 90 )); then
    record_finding "FAIL" "CRITICAL" \
      "Disk usage critical: ${disk_pct}%" \
      "At this level MariaDB and Drupal file writes will start failing" \
      "df -h — docker system prune — clear old backups in ~/backups/" \
      "ACT-DISK-01"
  elif (( disk_pct >= 80 )); then
    record_finding "WARN" "HIGH" \
      "Disk usage high: ${disk_pct}%" \
      "Approaching critical threshold — plan cleanup before it fails" \
      "df -h — clear old logs and backups" \
      "ACT-DISK-01"
  else
    record_finding "PASS" "LOW" "Disk: ${disk_pct}% used" "" "" ""
  fi

  # Memory pressure
  local mem_available
  mem_available=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
  if (( mem_available < 256 )); then
    record_finding "WARN" "HIGH" \
      "Available memory low: ${mem_available}MB" \
      "OOM kills possible — PHP-FPM or MariaDB may crash under load" \
      "actools oom — free -h — consider reducing container memory limits or upgrading server" \
      "ACT-MEM-01"
  else
    record_finding "PASS" "LOW" "Memory: ${mem_available}MB available" "" "" ""
  fi

  # Backup freshness
  local latest_backup
  latest_backup=$(ls -t "${ACTOOLS_HOME}/backups/"*.sql.gz 2>/dev/null | head -1 || echo "")
  if [[ -z "$latest_backup" ]]; then
    record_finding "FAIL" "HIGH" \
      "No backup found" \
      "No database backup exists — data loss risk if server fails" \
      "actools backup — verify cron: crontab -l" \
      "ACT-BKUP-01"
  else
    local backup_age_hours
    backup_age_hours=$(( ( $(date +%s) - $(stat -c %Y "$latest_backup") ) / 3600 ))
    if (( backup_age_hours > 26 )); then
      record_finding "WARN" "HIGH" \
        "Last backup: ${backup_age_hours}h ago" \
        "Backup cron may have failed — RPO at risk" \
        "actools backup — check cron: crontab -l" \
        "ACT-BKUP-01"
    else
      local backup_size
      backup_size=$(du -sh "$latest_backup" 2>/dev/null | cut -f1 || echo "?")
      record_finding "PASS" "HIGH" "Backup: ${backup_age_hours}h ago (${backup_size})" "" "" ""
    fi
  fi

  # MariaDB reachable
  local db_ping
  db_ping=$(cd "$ACTOOLS_HOME" && docker compose exec -T db mariadb-admin ping \
    -uroot -p"${DB_ROOT_PASS:-}" 2>/dev/null --silent 2>/dev/null || echo "fail")
  if echo "$db_ping" | grep -qi "alive"; then
    record_finding "PASS" "CRITICAL" "MariaDB: reachable" "" "" ""
  else
    record_finding "FAIL" "CRITICAL" \
      "MariaDB: not responding" \
      "Database is unreachable — site is down" \
      "docker compose restart db — docker compose logs db" \
      "ACT-STACK-03"
  fi

  # Worker container health
  local worker_health
  worker_health=$(cd "$ACTOOLS_HOME" && docker inspect actools_worker_prod \
    --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
  if [[ "$worker_health" == "healthy" ]]; then
    record_finding "PASS" "MEDIUM" "Worker container: healthy" "" "" ""
  else
    record_finding "WARN" "MEDIUM" \
      "Worker container: ${worker_health}" \
      "PDF generation queue may not be processing" \
      "actools pdf-test — actools worker-logs" \
      "ACT-WORK-01"
  fi
}

run_performance() {
  section_header "PERFORMANCE"

  local domain="${BASE_DOMAIN:-localhost}"

  # TTFB
  local ttfb
  ttfb=$(curl -sso /dev/null -w "%{time_starttransfer}" --max-time 30 "https://${domain}" 2>/dev/null || echo "0")
  local ttfb_ms
  ttfb_ms=$(echo "$ttfb * 1000" | bc 2>/dev/null | cut -d. -f1 || echo "0")
  if (( ttfb_ms > 2000 )); then
    record_finding "WARN" "MEDIUM" \
      "TTFB high: ${ttfb_ms}ms" \
      "Slow time-to-first-byte — check PHP-FPM pool and database query load" \
      "actools slow-log prod — actools redis-info" \
      "ACT-PERF-01"
  else
    record_finding "PASS" "LOW" "TTFB: ${ttfb_ms}ms" "" "" ""
  fi
}
