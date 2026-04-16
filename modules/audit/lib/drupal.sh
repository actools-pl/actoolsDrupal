#!/usr/bin/env bash
# Layer 1 — Drupal truth checks (drush-based)

run_drupal() {
  section_header "DRUPAL"

  # Security advisories
  local advisories
  advisories=$(drush_exec "pm:security --format=json 2>/dev/null" || echo "")
  if echo "$advisories" | grep -q '"'; then
    record_finding "FAIL" "CRITICAL" \
      "Security advisories found" \
      "Modules with known vulnerabilities are installed" \
      "drush pm:security — review and update affected modules" \
      "ACT-SEC-05"
  else
    record_finding "PASS" "HIGH" "Security advisories: none found" "" "" ""
  fi

  # Cron last run
  local cron_last
  cron_last=$(cd /home/actools && docker compose exec -T php_prod bash -c "cd /opt/drupal/web/prod && ./vendor/bin/drush state:get system.cron_last 2>/dev/null" 2>/dev/null | tr -d "[:space:]" || echo "0")
  local now
  now=$(date +%s)
  if [[ -z "$cron_last" || "$cron_last" == "0" ]]; then
    record_finding "WARN" "MEDIUM" "Cron: last run time unavailable" "Cron may never have run" "drush cron" "ACT-CRON-01"
  else
    local cron_age=$(( now - cron_last ))
    if (( cron_age < 0 )); then cron_age=0; fi
    if (( cron_age > 7200 )); then
      local cron_hours=$(( cron_age / 3600 ))
      record_finding "WARN" "MEDIUM" "Cron last run: ${cron_hours}h ago" "Scheduled tasks may be delayed" "drush cron" "ACT-CRON-01"
    else
      local cron_mins=$(( cron_age / 60 ))
      record_finding "PASS" "LOW" "Cron: ran ${cron_mins} minutes ago" "" "" ""
    fi
  fi
  # Config drift
  local drift_count
  drift_count=$(drush_exec "config:status --format=list 2>/dev/null" | grep -c "." || echo "0")
  drift_count=$(echo "$drift_count" | tr -d '[:space:]')
  if (( drift_count > 0 )); then
    local priority="MEDIUM"
    # Check if security-relevant keys drifted
    local drift_detail
    drift_detail=$(drush_exec "config:status --format=list 2>/dev/null" || echo "")
    if echo "$drift_detail" | grep -qE "system.logging|system.performance|user.settings"; then
      priority="HIGH"
    fi
    record_finding "WARN" "$priority" \
      "Config drift detected (${drift_count} files)" \
      "Uncommitted changes may cause deployment failures" \
      "drush config:import" \
      "ACT-CFG-01"
  else
    record_finding "PASS" "LOW" "Config: no drift" "" "" ""
  fi

  # Trusted host patterns — config check (behavioral test in integration.sh)
  local settings_file
  settings_file=$(find /var/www/html/prod/web/sites -name "settings.php" 2>/dev/null | head -1)
  settings_file="${settings_file:-/var/www/html/prod/web/sites/default/settings.php}"
  local trusted_check
  trusted_check=$(docker compose exec -T php_prod bash -c \
    "grep -c 'trusted_host_patterns' ${settings_file} 2>/dev/null || echo 0" 2>/dev/null | tr -d '[:space:]' || echo "0")
  if (( trusted_check == 0 )); then
    record_finding "FAIL" "CRITICAL" \
      "trusted_host_patterns not configured" \
      "Any Host header accepted — HTTP host injection possible" \
      "Add \$settings['trusted_host_patterns'] to settings.php" \
      "ACT-SEC-04"
  else
    record_finding "PASS" "HIGH" "trusted_host_patterns: configured" "" "" ""
  fi

  # Error display in production
  local error_level
  error_level=$(docker compose exec -T php_prod bash -c \
    "grep -E 'error_level|display_errors' ${settings_file:-/dev/null} 2>/dev/null || echo ''" 2>/dev/null || echo "")
  if echo "$error_level" | grep -qE "verbose|TRUE"; then
    record_finding "FAIL" "HIGH" \
      "Error display enabled in production" \
      "Stack traces and debug info exposed to visitors" \
      "Set \$config['system.logging']['error_level'] = 'hide'" \
      "ACT-CFG-02"
  else
    record_finding "PASS" "MEDIUM" "Error display: hidden" "" "" ""
  fi

  # Session cookie security
  local session_secure
  session_secure=$(docker compose exec -T php_prod bash -c \
    "grep -c 'cookie_secure' ${settings_file:-/dev/null} 2>/dev/null || echo 0" 2>/dev/null | tr -d '[:space:]' || echo "0")
  if (( session_secure == 0 )); then
    record_finding "WARN" "MEDIUM" \
      "Session cookie secure flag not set" \
      "Session cookies may be transmitted over HTTP" \
      "Add \$settings['session_write_interval'] and cookie_secure to settings.php" \
      "ACT-CFG-02"
  else
    record_finding "PASS" "MEDIUM" "Session cookies: secure" "" "" ""
  fi

  # Module update status
  local updates
  updates=$(drush_exec "pm:list --status=enabled --format=list 2>/dev/null" | wc -l | tr -d '[:space:]' || echo "0")
  record_finding "INFO" "LOW" "Enabled modules: ${updates}" "" "" ""

  # Queue backlog
  local queue_count
  queue_count=$(drush_exec "queue:list --format=json 2>/dev/null" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(v.get('items',0) for v in d.values() if isinstance(v,dict)))" \
    2>/dev/null | tr -d '[:space:]' || echo "0")
  if (( queue_count > 100 )); then
    record_finding "WARN" "MEDIUM" \
      "Queue backlog: ${queue_count} items" \
      "Worker may be stopped or processing too slowly" \
      "actools worker-run — check actools worker-logs for errors" \
      "ACT-WORK-01"
  else
    record_finding "PASS" "LOW" "Queue backlog: ${queue_count} items" "" "" ""
  fi
}
