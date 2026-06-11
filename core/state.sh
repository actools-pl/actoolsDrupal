#!/usr/bin/env bash
# =============================================================================
# core/state.sh — Actools state management (jq-backed JSON state file)
#
# LIVE AUTHORITY (P0-K): carries the monolith's exact init_state/set_state/
# get_state/is_installed/mark_installed definitions, extracted VERBATIM from
# the inline v14 block in actools.sh. Sourced by actools.sh on the live
# install path.
#
# Required globals (set by actools.sh BEFORE any of these is called):
#   STATE_FILE — "$INSTALL_DIR/.actools-state.json" (INSTALL_DIR-anchored,
#                v14 path semantics); read at call time.
#   REAL_USER  — the invoking sudo user (chown of the state file, best-effort).
#
# Functions only — no variable assignments — so the module is inert under
# `set -u` at source time. The jq/state-file semantics are byte-identical to
# the inline v14 code: atomic tmp+mv writes, the literal string "null" for
# missing keys/files, `.envs.<env> == true` install markers.
#
# get_db_pass/get_backup_pass are NOT here — they belong to the secrets unit
# (core/secrets.sh, P0-K). The stale v9.2 orphan that previously lived here
# carried twins of them; that content is retired.
# =============================================================================

init_state() {
  [[ -f "$STATE_FILE" ]] || echo '{"envs":{},"db_passes":{}}' > "$STATE_FILE"
  chown "$REAL_USER:$REAL_USER" "$STATE_FILE" 2>/dev/null || true
}

set_state()      { local tmp; tmp=$(mktemp); jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"; }
get_state()      { jq -r "$1" "$STATE_FILE" 2>/dev/null || echo "null"; }
is_installed()   { jq -e ".envs.$1 == true" "$STATE_FILE" >/dev/null 2>&1; }
mark_installed() { set_state ".envs.$1=true"; }
