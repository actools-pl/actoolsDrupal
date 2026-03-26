#!/usr/bin/env bash
# =============================================================================
# modules/health/checks.sh — Phase 2: Semantic Health Checks
# =============================================================================

health_check_all() {
  local issues=0

  echo ""
  echo "=== Actools Health Check ==="
  echo "$(date '+%F %T')"
  echo ""

  # --- Container status ---
  echo "── Containers ──────────────────────────"
  local containers=("actools_caddy" "actools_db" "actools_php_prod" "actools_redis" "actools_worker_prod")
  for c in "${containers[@]}"; do
    local status health
    health=$(docker inspect "$c" --format="{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" 2>/dev/null || echo "none")
    status=$(docker inspect "$c" --format='{{.State.Status}}' 2>/dev/null || echo "missing")
    

    if [[ "$status" == "running" ]]; then
      if [[ "$health" == "healthy" || "$health" == "none" || "$health" == "" ]]; then
        echo "  ✓ ${c} — ${status}"
      else
        echo "  ✗ ${c} — ${status} (health: ${health})"
        (( issues++ )) || true
      fi
    else
      echo "  ✗ ${c} — ${status}"
      (( issues++ )) || true
    fi
  done

  # --- Memory pressure ---
  echo ""
  echo "── Memory Pressure ─────────────────────"
  local containers_with_limits=("actools_php_prod:512" "actools_db:2048" "actools_redis:256")
  for entry in "${containers_with_limits[@]}"; do
    local name="${entry%%:*}"
    local limit_mib="${entry##*:}"
    local mem_raw
    mem_raw=$(docker stats --no-stream --format "{{.MemUsage}}" "$name" 2>/dev/null \
      | grep -oP '^[\d.]+(?=MiB)' || echo "0")
    if [[ -n "$mem_raw" && "$mem_raw" != "0" ]]; then
      local mem_int="${mem_raw%.*}"
      local pct=$(( mem_int * 100 / limit_mib ))
      if (( pct > 85 )); then
        echo "  ✗ ${name}: ${mem_raw}MiB / ${limit_mib}MiB (${pct}%) — CRITICAL"
        (( issues++ )) || true
      elif (( pct > 70 )); then
        echo "  ! ${name}: ${mem_raw}MiB / ${limit_mib}MiB (${pct}%) — WARNING"
      else
        echo "  ✓ ${name}: ${mem_raw}MiB / ${limit_mib}MiB (${pct}%)"
      fi
    fi
  done

  # --- TLS certificate expiry ---
  echo ""
  echo "── TLS Certificate ─────────────────────"
  local expiry expiry_epoch now_epoch days_left
  expiry=$(echo | openssl s_client -connect "${BASE_DOMAIN}:443" \
    -servername "${BASE_DOMAIN}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | cut -d= -f2)
  if [[ -n "$expiry" ]]; then
    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    if (( days_left < 14 )); then
      echo "  ✗ ${BASE_DOMAIN} — expires in ${days_left} days — RENEW NOW"
      (( issues++ )) || true
    else
      echo "  ✓ ${BASE_DOMAIN} — expires in ${days_left} days"
    fi
  else
    echo "  ! TLS check unavailable"
  fi

  # --- Disk space ---
  echo ""
  echo "── Disk Space ──────────────────────────"
  local disk_pct disk_free
  disk_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  disk_free=$(df -h / | awk 'NR==2 {print $4}')
  if (( disk_pct > 85 )); then
    echo "  ✗ Disk: ${disk_pct}% used (${disk_free} free) — CRITICAL"
    (( issues++ )) || true
  elif (( disk_pct > 70 )); then
    echo "  ! Disk: ${disk_pct}% used (${disk_free} free) — WARNING"
  else
    echo "  ✓ Disk: ${disk_pct}% used (${disk_free} free)"
  fi

  # --- MariaDB slow queries ---
  echo ""
  echo "── MariaDB ─────────────────────────────"
  local slow_queries
  slow_queries=$(docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN \
    -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null | awk '{print $2}')
  if [[ -n "$slow_queries" ]]; then
    if (( slow_queries > 100 )); then
      echo "  ! Slow queries: ${slow_queries} — check slow query log"
    else
      echo "  ✓ Slow queries: ${slow_queries}"
    fi
  fi

  # --- Redis eviction ---
  echo ""
  echo "── Redis ───────────────────────────────"
  local evicted
  evicted=$(docker exec actools_redis redis-cli info stats 2>/dev/null \
    | grep evicted_keys | cut -d: -f2 | tr -d '[:space:]')
  if [[ -n "$evicted" && "$evicted" -gt 0 ]]; then
    echo "  ! Redis evicted keys: ${evicted} — consider increasing REDIS_MEMORY_LIMIT"
  else
    echo "  ✓ Redis evictions: 0"
  fi

  # --- Summary ---
  echo ""
  echo "────────────────────────────────────────"
  if (( issues == 0 )); then
    echo "  ✓ All checks passed — system healthy"
  else
    echo "  ✗ ${issues} issue(s) found — review above"
    [[ -n "${NOTIFY_WEBHOOK:-}" ]] && \
      curl -fsS -X POST "${NOTIFY_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"Actools health: ${issues} issue(s) on ${BASE_DOMAIN}\"}" \
        --max-time 10 &>/dev/null || true
  fi
  echo ""
}
