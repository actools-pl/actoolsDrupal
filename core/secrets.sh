#!/usr/bin/env bash
# =============================================================================
# core/secrets.sh — Actools Engine: Secret Generation and Writeback
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

rand_pass() { openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 22; }

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

writeback_secrets() {
  for var in DB_ROOT_PASS DRUPAL_ADMIN_PASS; do
    local val="${!var}"
    if grep -qP "^${var}=\\s*(#.*)?$" "$ENV_FILE" 2>/dev/null; then
      sed -i "s|^${var}=.*|${var}=${val}|" "$ENV_FILE"
      log "${var} written back to env file."
    fi
  done
}
