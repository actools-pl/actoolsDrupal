#!/usr/bin/env bash
# =============================================================================
# core/bootstrap.sh — Actools bootstrap logging + dry-run helpers
#
# LIVE AUTHORITY (P0-K): carries the monolith's exact log/warn/error/section/
# dryrun definitions, extracted VERBATIM from the inline v14 block in
# actools.sh. Sourced by actools.sh on the live install path immediately after
# the color variables are set.
#
# Required globals (set by actools.sh BEFORE any of these is called):
#   R G Y C NC — ANSI color codes (actools.sh sets them just above the source
#                line); read at call time.
#   DRY_RUN    — read by dryrun() at call time only (actools.sh sets it right
#                after sourcing this module, before the first dryrun call).
#
# This module defines functions ONLY — no variable assignments — so it is
# inert under `set -u` at source time and CANNOT alter path semantics. The
# stale v9.2 orphan that previously lived here re-derived MODE/REAL_USER and
# set INSTALL_DIR/ENV_FILE/STATE_FILE/LOG_* to $REAL_HOME-anchored paths; that
# content is retired (P0-K). Path authority stays in actools.sh:
# INSTALL_DIR is BASH_SOURCE-relative, ENV_FILE/STATE_FILE are
# INSTALL_DIR-anchored.
# =============================================================================

log()     { echo -e "${G}[INFO ]${NC} $(date '+%F %T') $*"; }
warn()    { echo -e "${Y}[WARN ]${NC} $(date '+%F %T') $*"; }
error()   { echo -e "${R}[ERROR]${NC} $(date '+%F %T') $*"; exit 1; }
section() {
  echo -e "\n${C}══════════════════════════════════════════════════${NC}"
  echo -e "${C}  $*${NC}"
  echo -e "${C}══════════════════════════════════════════════════${NC}"
}
dryrun() { "$DRY_RUN" && { echo -e "${Y}[DRY-RUN]${NC} Would run: $*"; return 0; } || "$@"; }
