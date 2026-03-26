#!/usr/bin/env bash
# =============================================================================
# cli/commands/cost_optimize.sh — Phase 2: Cost & Memory Optimization
# Reads real Docker stats and suggests memory limit changes
# =============================================================================

cmd_cost_optimize() {
  local stats_dir="/home/actools/logs/stats"
  local today
  today=$(date +%F)

  echo ""
  echo "=== Actools Cost & Memory Optimizer ==="
  echo "Analysing Docker stats from: ${stats_dir}"
  echo ""

  if ! ls "${stats_dir}"/*.jsonl &>/dev/null; then
    echo "No stats data found. Stats collect hourly via cron."
    echo "Run manually: sudo /etc/cron.hourly/actools-stats"
    return 1
  fi

  # Count data points
  local total_lines
  total_lines=$(cat "${stats_dir}"/*.jsonl 2>/dev/null | wc -l)
  local days
  days=$(ls "${stats_dir}"/*.jsonl 2>/dev/null | wc -l)
  echo "Data points : ${total_lines} readings across ${days} day(s)"
  echo "Latest file : ${today}.jsonl"
  echo ""

  # Analyse each container
  local containers=("actools_caddy" "actools_php_prod" "actools_worker_prod" "actools_redis" "actools_db")

  printf "%-22s %-12s %-12s %-12s %-20s\n" "Container" "Peak MiB" "Avg MiB" "Limit" "Recommendation"
  printf "%-22s %-12s %-12s %-12s %-20s\n" "---------" "--------" "-------" "-----" "--------------"

  for container in "${containers[@]}"; do
    # Extract memory usage in MiB for this container
    local readings
    readings=$(cat "${stats_dir}"/*.jsonl 2>/dev/null \
      | grep "\"container\":\"${container}\"" \
      | grep -v '"mem":"0B' \
      | sed 's/.*"mem":"\([0-9.]*\)MiB.*/\1/' \
      | grep -E '^[0-9]')

    if [[ -z "$readings" ]]; then
      printf "%-22s %-12s %-12s %-12s %-20s\n" "$container" "no data" "-" "-" "insufficient data"
      continue
    fi

    # Calculate peak and average
    local peak avg
    peak=$(echo "$readings" | awk 'BEGIN{max=0} {if($1>max)max=$1} END{printf "%.0f", max}')
    avg=$(echo "$readings" | awk '{sum+=$1; count++} END{printf "%.0f", sum/count}')

    # Get current limit from running container
    local limit_raw limit_display
    limit_raw=$(docker inspect "${container}" \
      --format='{{.HostConfig.Memory}}' 2>/dev/null || echo "0")

    if [[ "$limit_raw" == "0" ]]; then
      limit_display="unlimited"
    else
      limit_display="$(( limit_raw / 1048576 ))MiB"
    fi

    # Generate recommendation
    local recommendation
    local limit_mib=$(( limit_raw / 1048576 ))

    if [[ "$limit_raw" == "0" ]]; then
      recommendation="set a limit"
    elif [[ $peak -lt $(( limit_mib / 4 )) ]]; then
      local suggested=$(( peak * 2 ))
      recommendation="reduce to ${suggested}MiB (saves $(( limit_mib - suggested ))MiB)"
    elif [[ $peak -gt $(( limit_mib * 85 / 100 )) ]]; then
      local suggested=$(( peak * 2 ))
      recommendation="INCREASE to ${suggested}MiB (at risk!)"
    else
      recommendation="OK — within safe range"
    fi

    printf "%-22s %-12s %-12s %-12s %-20s\n" \
      "$container" "${peak}MiB" "${avg}MiB" "$limit_display" "$recommendation"
  done

  echo ""
  echo "=== MariaDB Buffer Pool Analysis ==="
  local bp_hit_rate
  bp_hit_rate=$(docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN \
    -e "SELECT ROUND((1 - (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS
        WHERE VARIABLE_NAME='Innodb_buffer_pool_reads') /
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS
        WHERE VARIABLE_NAME='Innodb_buffer_pool_read_requests')) * 100, 2)
        AS hit_rate;" 2>/dev/null || echo "unavailable")

  echo "InnoDB buffer pool hit rate: ${bp_hit_rate}%"
  if [[ "$bp_hit_rate" != "unavailable" ]]; then
    local rate_int
    rate_int=$(echo "$bp_hit_rate" | cut -d. -f1)
    if (( rate_int >= 95 )); then
      echo "Status: GOOD — buffer pool is well sized"
    elif (( rate_int >= 85 )); then
      echo "Status: OK — consider increasing INNODB_BUFFER_POOL slightly"
    else
      echo "Status: LOW — increase INNODB_BUFFER_POOL in actools.env"
    fi
  fi

  echo ""
  echo "=== Redis Memory Analysis ==="
  local redis_used redis_max
  redis_used=$(docker exec actools_redis redis-cli info memory 2>/dev/null \
    | grep "used_memory_human" | cut -d: -f2 | tr -d '[:space:]')
  redis_max=$(docker exec actools_redis redis-cli info memory 2>/dev/null \
    | grep "maxmemory_human" | cut -d: -f2 | tr -d '[:space:]')
  echo "Redis used: ${redis_used:-unavailable}  /  Max: ${redis_max:-unavailable}"

  echo ""
  echo "=== Suggested actools.env changes ==="
  echo "Review the recommendations above and update actools.env accordingly."
  echo "Then run: sudo ./actools.sh update"
  echo ""
  echo "Note: Changes only apply after 'docker compose up -d' restarts containers."
}
