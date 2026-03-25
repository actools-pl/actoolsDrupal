#!/usr/bin/env bash
# =============================================================================
# core/state.sh — Actools Engine: State Management
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

init_state() {
  [[ -f "$STATE_FILE" ]] || echo '{"envs":{},"db_passes":{}}' > "$STATE_FILE"
  chown "$REAL_USER:$REAL_USER" "$STATE_FILE" 2>/dev/null || true
}

set_state()      { local tmp; tmp=$(mktemp); jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"; }
get_state()      { jq -r "$1" "$STATE_FILE" 2>/dev/null || echo "null"; }
is_installed()   { jq -e ".envs.$1 == true" "$STATE_FILE" >/dev/null 2>&1; }
mark_installed() { set_state ".envs.$1=true"; }

get_db_pass() {
  local env="$1" pass
  pass=$(get_state ".db_passes.${env}")
  if [[ "$pass" == "null" || -z "$pass" ]]; then
    pass=$(rand_pass)
    set_state ".db_passes.${env}=\"${pass}\""
  fi
  echo "$pass"
}

get_backup_pass() {
  local pass
  pass=$(get_state ".backup_user_pass")
  if [[ "$pass" == "null" || -z "$pass" ]]; then
    pass=$(rand_pass)
    set_state ".backup_user_pass=\"${pass}\""
  fi
  echo "$pass"
}
