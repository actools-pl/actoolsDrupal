#!/usr/bin/env bash
# =============================================================================
# installer/preflight.sh — Server readiness check (Doc 1 §9.3, §5.3).
#
# Runs the base check set and, if a profile defines them, profile-extra
# checks. Each check emits one of OK/WARN/FAIL with a Fix line on
# anything actionable.
#
# Exit codes:
#   0  ready to install
#   1  one or more failures — fix and re-run
#   2  warnings only — install can proceed
#
# Required globals (set by actools.sh before sourcing):
#   INSTALL_DIR, ENV_FILE, STATE_FILE
# =============================================================================

run_preflight() {
  print_title "ACTOOLS PREFLIGHT"

  local fails=0 warns=0

  # ── Check 1: OS supported ──────────────────────────────────────────────
  if grep -qE 'Ubuntu (24\.04|22\.04)' /etc/os-release 2>/dev/null; then
    local os_name
    os_name=$(grep '^PRETTY_NAME' /etc/os-release | cut -d'"' -f2)
    print_ok "OS" "$os_name"
  elif grep -q '^ID=ubuntu' /etc/os-release 2>/dev/null; then
    local os_name
    os_name=$(grep '^PRETTY_NAME' /etc/os-release | cut -d'"' -f2)
    print_warn "OS" "$os_name — Ubuntu 24.04 is the tested target"
    ((warns++)) || true
  else
    print_fail "OS" "not Ubuntu — installer is Ubuntu 24.04 only"
    print_fix "Re-provision the VPS with Ubuntu 24.04."
    ((fails++)) || true
  fi

  # ── Check 2: actools.env exists ────────────────────────────────────────
  if [[ ! -f "$ENV_FILE" ]]; then
    print_fail "actools.env" "missing"
    print_fix "sudo ./actools.sh init --domain <d> --email <e>"
    print_summary "$((fails + 1))" "$warns"
    return 1
  fi
  print_ok "actools.env" "found"

  # Load it for the remaining checks
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a

  # ── Check 3: Required env vars ─────────────────────────────────────────
  if [[ -z "${BASE_DOMAIN:-}" || "${BASE_DOMAIN}" == "example.com" ]]; then
    print_fail "BASE_DOMAIN" "not set or still placeholder"
    print_fix "Edit $ENV_FILE or re-run init with --domain"
    ((fails++)) || true
  else
    print_ok "BASE_DOMAIN" "$BASE_DOMAIN"
  fi

  if [[ -z "${DRUPAL_ADMIN_EMAIL:-}" ]]; then
    print_fail "DRUPAL_ADMIN_EMAIL" "not set"
    ((fails++)) || true
  elif [[ ! "${DRUPAL_ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    print_fail "DRUPAL_ADMIN_EMAIL" "invalid: $DRUPAL_ADMIN_EMAIL"
    ((fails++)) || true
  else
    print_ok "DRUPAL_ADMIN_EMAIL" "$DRUPAL_ADMIN_EMAIL"
  fi

  # ── Check 4: RAM ───────────────────────────────────────────────────────
  local ram_mb
  ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
  if (( ram_mb < 1500 )); then
    print_fail "RAM" "${ram_mb} MB — 2 GB minimum"
    print_fix "Resize the VPS to at least 2 GB."
    ((fails++)) || true
  elif (( ram_mb < 2500 )); then
    print_warn "RAM" "${ram_mb} MB — 4 GB recommended"
    ((warns++)) || true
  else
    print_ok "RAM" "${ram_mb} MB"
  fi

  # ── Check 5: Disk ──────────────────────────────────────────────────────
  local disk_kb disk_gb
  disk_kb=$(df / | awk 'NR==2 {print $4}')
  disk_gb=$(( disk_kb / 1048576 ))
  if (( disk_gb < 20 )); then
    print_fail "Disk" "${disk_gb} GB free — 20 GB required"
    print_fix "Free space or resize the VPS."
    ((fails++)) || true
  elif (( disk_gb < 40 )); then
    print_warn "Disk" "${disk_gb} GB free — 40 GB recommended"
    ((warns++)) || true
  else
    print_ok "Disk" "${disk_gb} GB free"
  fi

  # ── Check 6: Ports 80/443 ──────────────────────────────────────────────
  local blockers=""
  for port in 80 443; do
    if ss -lnt "sport = :$port" 2>/dev/null | grep -q LISTEN; then
      blockers+="${port} "
    fi
  done
  if [[ -n "$blockers" ]]; then
    print_warn "Ports" "in use: ${blockers}— another service will conflict with Caddy"
    print_fix "Stop the service holding those ports before installing."
    ((warns++)) || true
  else
    print_ok "Ports" "80 and 443 free"
  fi

  # ── Check 7: DNS points to this server ─────────────────────────────────
  local server_ip dns_ip
  server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || true)
  dns_ip=$(getent hosts "${BASE_DOMAIN}" 2>/dev/null | awk '{print $1}' | head -1 || true)
  if [[ -z "$dns_ip" ]]; then
    print_warn "DNS" "${BASE_DOMAIN} has no A record yet"
    print_fix "Point A record to ${server_ip:-this server} before HTTPS can issue."
    ((warns++)) || true
  elif [[ -n "$server_ip" && "$server_ip" != "$dns_ip" ]]; then
    print_warn "DNS" "${BASE_DOMAIN} → ${dns_ip} (this server is ${server_ip})"
    print_fix "Update the A record to ${server_ip} before TLS will issue."
    ((warns++)) || true
  else
    print_ok "DNS" "${BASE_DOMAIN} → ${dns_ip}"
  fi

  # ── Check 8: Existing install state ────────────────────────────────────
  if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1 \
     && jq -e '.envs.prod == true' "$STATE_FILE" >/dev/null 2>&1; then
    print_warn "Install state" "Drupal already installed"
    print_fix "Use 'sudo ./actools.sh update' instead of install."
    ((warns++)) || true
  else
    print_ok "Install state" "fresh server"
  fi

  # ── Profile-extra checks (community defines none) ──────────────────────
  # community.profile sets PROFILE_PREFLIGHT_EXTRA=(), so profile_preflight_extra
  # yields nothing and this loop body never executes — community is byte-identical.
  # A non-default profile routes each declared extra through the resolver
  # (resolve_profile_check "preflight"): a check that resolves to an INSTALLED
  # handler runs it (the handler prints its own status line; a non-zero return
  # counts as a failure); a check the profile DECLARES but whose handler is NOT
  # installed is a hard FAILURE for a non-default profile (P0-H) — a promised
  # readiness check the deployment cannot run must not pass as a silent skip.
  if [[ -f "${INSTALL_DIR}/installer/profile.sh" ]]; then
    # shellcheck source=/dev/null
    source "${INSTALL_DIR}/installer/profile.sh"
    # Source dispatch.sh after profile.sh has set ACTOOLS_PROFILE. P0-H: the
    # preflight-extra resolver is now consumed here (was "available, not called").
    # shellcheck source=/dev/null
    source "${INSTALL_DIR}/installer/dispatch.sh" 2>/dev/null || true
    local extra handler
    while IFS= read -r extra; do
      [[ -z "$extra" ]] && continue
      handler="$(actools::dispatch::resolve_profile_check "preflight" "$extra" 2>/dev/null)"
      if [[ -n "$handler" ]] && declare -F "$handler" >/dev/null 2>&1; then
        if "$handler" "$extra"; then
          : # handler emitted its own OK/WARN line
        else
          ((fails++)) || true
        fi
      else
        print_fail "Profile check" "${extra} — declared by profile but no handler installed"
        print_fix "Install the profile's preflight handler for '${extra}', or remove it from PROFILE_PREFLIGHT_EXTRA."
        ((fails++)) || true
      fi
    done < <(profile_preflight_extra)
  fi

  # ── Summary ─────────────────────────────────────────────────────────────
  if (( fails == 0 && warns == 0 )); then
    echo
    echo "Ready to install."
    print_next "sudo ./actools.sh install"
    return 0
  elif (( fails == 0 )); then
    echo
    printf '%d warning(s) — install can proceed but review above first.\n' "$warns"
    print_next "sudo ./actools.sh install"
    return 2
  else
    echo
    printf '%d failure(s), %d warning(s) — fix the failures, then re-run preflight.\n' "$fails" "$warns"
    print_next "sudo ./actools.sh preflight"
    return 1
  fi
}
