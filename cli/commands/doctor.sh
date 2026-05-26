#!/usr/bin/env bash
# =============================================================================
# cli/commands/doctor.sh — Daily operator health check (Doc 1 §10).
#
# Runs nine surface-level checks and prints a one-page summary.
#
# Exit codes:
#   0  all checks OK
#   1  one or more critical checks failed
#   2  warnings only
#
# Flags:
#   --deep   Not available in this edition. Deep mode is in development.
#            Delegates to doctor_deep.sh which prints the gate message.
#
# Sourced from cli/actools. Required globals:
#   INSTALL_DIR  — repository / installation root
# =============================================================================

run_doctor() {
  # Deep gate — single flag, matches `actools audit --deep` pattern.
  for arg in "$@"; do
    if [[ "$arg" == "--deep" ]]; then
      # shellcheck source=/dev/null
      source "${INSTALL_DIR}/cli/commands/doctor_deep.sh"
      run_doctor_deep
      return $?
    fi
  done

  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh" 2>/dev/null || {
    echo "Cannot load installer/output.sh" >&2
    return 3
  }

  # Load env file for credentials and BASE_DOMAIN
  local env_file="${INSTALL_DIR}/actools.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  fi

  # D.0: Source dispatch.sh after env file has made ACTOOLS_PROFILE available.
  # Resolvers are available for D.1+ doctor-check dispatch; not called in D.0.
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/dispatch.sh" 2>/dev/null || true

  print_title "ACTOOLS DOCTOR"

  # Report active profile — doctrine claim: active profile is always operator-visible.
  echo "Active profile: ${ACTOOLS_PROFILE:-community} (source: ${_actools_profile_source:-default})"
  echo

  local fails=0 warns=0

  # ── 1. Site URL reachable ─────────────────────────────────────────────
  local http_code
  http_code=$(curl -sso /dev/null -w "%{http_code}" --max-time 5 \
    "https://${BASE_DOMAIN:-localhost}" 2>/dev/null || echo "ERR")
  case "$http_code" in
    200|301|302|303|307|308)
      print_ok "Site" "https://${BASE_DOMAIN} (HTTP ${http_code})"
      ;;
    ERR)
      print_fail "Site" "https://${BASE_DOMAIN} unreachable"
      print_fix "actools status"
      ((fails++)) || true
      ;;
    5*)
      print_fail "Site" "HTTP ${http_code}"
      print_fix "actools logs php_prod"
      ((fails++)) || true
      ;;
    *)
      print_warn "Site" "HTTP ${http_code}"
      ((warns++)) || true
      ;;
  esac

  # ── 2. TLS valid ───────────────────────────────────────────────────────
  local expiry expiry_epoch now_epoch days_left
  expiry=$(echo | timeout 5 openssl s_client -connect "${BASE_DOMAIN}:443" \
    -servername "${BASE_DOMAIN}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [[ -n "$expiry" ]]; then
    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    if (( days_left < 7 )); then
      print_fail "TLS" "expires in ${days_left} days"
      print_fix "actools caddy-reload && actools tls-status"
      ((fails++)) || true
    elif (( days_left < 30 )); then
      print_warn "TLS" "expires in ${days_left} days"
      ((warns++)) || true
    else
      print_ok "TLS" "valid (${days_left} days remaining)"
    fi
  else
    print_warn "TLS" "certificate could not be read"
    ((warns++)) || true
  fi

  # ── 3. Containers ──────────────────────────────────────────────────────
  local containers=("actools_caddy" "actools_db" "actools_php_prod" "actools_redis" "actools_worker_prod")
  local running=0 total=${#containers[@]}
  for c in "${containers[@]}"; do
    local status
    status=$(docker inspect "$c" --format='{{.State.Status}}' 2>/dev/null || echo missing)
    [[ "$status" == "running" ]] && ((running++)) || true
  done
  if (( running == total )); then
    print_ok "Containers" "${running}/${total} running"
  elif (( running > 0 )); then
    print_fail "Containers" "${running}/${total} running"
    print_fix "actools status"
    ((fails++)) || true
  else
    print_fail "Containers" "none running"
    print_fix "actools status  &&  docker compose up -d"
    ((fails++)) || true
  fi

  # ── 4. Database reachable ──────────────────────────────────────────────
  if docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS:-}" \
       -e "SELECT 1;" >/dev/null 2>&1; then
    print_ok "Database" "reachable"
  else
    print_fail "Database" "unreachable"
    print_fix "actools logs db"
    ((fails++)) || true
  fi

  # ── 5. Redis reachable ─────────────────────────────────────────────────
  if [[ "${ENABLE_REDIS:-true}" == "true" ]]; then
    if docker exec actools_redis redis-cli ping 2>/dev/null | grep -q PONG; then
      print_ok "Redis" "reachable"
    else
      print_fail "Redis" "unreachable"
      print_fix "actools logs redis"
      ((fails++)) || true
    fi
  else
    print_skip "Redis" "disabled in actools.env"
  fi

  # ── 6. Disk ────────────────────────────────────────────────────────────
  local disk_pct disk_free
  disk_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  disk_free=$(df -h / | awk 'NR==2 {print $4}')
  if (( disk_pct > 90 )); then
    print_fail "Disk" "${disk_pct}% used (${disk_free} free)"
    print_fix "Clear old backups or grow the volume."
    ((fails++)) || true
  elif (( disk_pct > 80 )); then
    print_warn "Disk" "${disk_pct}% used (${disk_free} free)"
    ((warns++)) || true
  else
    print_ok "Disk" "${disk_pct}% used (${disk_free} free)"
  fi

  # ── 7. Backup recency ──────────────────────────────────────────────────
  local backups_dir="${INSTALL_DIR}/backups"
  local latest_backup backup_age_h
  latest_backup=$(ls -t "${backups_dir}"/prod_db_*.sql.gz 2>/dev/null | head -1)
  if [[ -z "$latest_backup" ]]; then
    print_warn "Backups" "none found in ${backups_dir}"
    print_fix "actools backup"
    ((warns++)) || true
  else
    backup_age_h=$(( ( $(date +%s) - $(stat -c %Y "$latest_backup") ) / 3600 ))
    if (( backup_age_h > 48 )); then
      print_warn "Backups" "latest is ${backup_age_h}h old"
      print_fix "actools backup"
      ((warns++)) || true
    else
      print_ok "Backups" "latest is ${backup_age_h}h old"
    fi
  fi

  # ── 8. Restore-test recency ────────────────────────────────────────────
  local rtest_marker="${INSTALL_DIR}/backups/.restore-test-last"
  if [[ ! -f "$rtest_marker" ]]; then
    print_warn "Restore test" "never run"
    print_fix "actools restore-test"
    ((warns++)) || true
  else
    local rtest_age_d
    rtest_age_d=$(( ( $(date +%s) - $(stat -c %Y "$rtest_marker") ) / 86400 ))
    if (( rtest_age_d > 7 )); then
      print_warn "Restore test" "last run ${rtest_age_d}d ago"
      print_fix "actools restore-test"
      ((warns++)) || true
    else
      print_ok "Restore test" "last run ${rtest_age_d}d ago"
    fi
  fi

  # ── 9. Drupal bootstrap ────────────────────────────────────────────────
  if docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T php_prod \
       bash -c "cd /var/www/html/prod && ./vendor/bin/drush status --field=bootstrap" 2>/dev/null \
       | grep -q Successful; then
    print_ok "Drupal" "bootstrap successful"
  else
    print_fail "Drupal" "bootstrap failed"
    print_fix "actools drush prod status"
    ((fails++)) || true
  fi

  echo
  if (( fails == 0 && warns == 0 )); then
    echo "All checks passed."
    return 0
  elif (( fails == 0 )); then
    printf '%d warning(s) — see suggested actions above.\n' "$warns"
    return 2
  else
    printf '%d failure(s), %d warning(s).\n' "$fails" "$warns"
    return 1
  fi
}
