#!/usr/bin/env bash
# =============================================================================
# core/secrets.sh — secret generation + per-env DB/backup password persistence
#
# LIVE AUTHORITY (P0-K): carries the monolith's exact rand_pass/gen_if_empty/
# get_db_pass/get_backup_pass definitions, extracted VERBATIM from the inline
# v14 blocks in actools.sh. Sourced by actools.sh on the live install path,
# before the top-level secret-generation calls.
#
# Required collaborators/globals (provided by actools.sh BEFORE any call):
#   log/error            — core/bootstrap.sh (gen_if_empty calls them)
#   get_state/set_state  — core/state.sh (get_db_pass/get_backup_pass call
#                          them; STATE_FILE semantics live there)
#   openssl              — rand_pass entropy source
#
# Functions only — no variable assignments — so the module is inert under
# `set -u` at source time. The TOP-LEVEL secret flow deliberately STAYS in
# actools.sh, in its original order: gen_if_empty DB_ROOT_PASS /
# DRUPAL_ADMIN_PASS, then the v9.2 fix7 writeback loop ("secret-writeback
# order unchanged" — P0-K). The stale v9.2 orphan's writeback_secrets() twin
# is retired; the live writeback is spine code, not a unit function.
# =============================================================================

rand_pass() { while true; do p=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9'); [ ${#p} -ge 22 ] && echo "${p:0:22}" && break; done; }

gen_if_empty() {
  local var="$1"
  local val="${!var:-}"
  [[ "$val" == *"CHANGEME"* ]] && error "$var contains 'CHANGEME' -- set a real value."
  if [[ -z "$val" ]]; then
    log "$var empty -- auto-generating..."
    printf -v "$var" '%s' "$(rand_pass)"
    log "$var generated."
  fi
}

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
