#!/usr/bin/env bash
# =============================================================================
# installer/output.sh — Shared output helpers for the staged operator journey.
#
# Used by:  installer/init.sh, installer/preflight.sh, installer/handoff.sh,
#           cli/commands/doctor.sh, cli/commands/doctor_deep.sh
#
# Rendering rules (Doc 1 §4.4, §5.6):
#   - Every check shows one of:  OK  /  WARN  /  FAIL  /  SKIP
#   - Failures must be followed by a "Fix:" or "Next:" line
#   - Output is plain when stdout is not a TTY or ACTOOLS_PLAIN=1
#
# This file defines functions only. It is safe to source multiple times.
# =============================================================================

# Colour escapes — suppressed when not on a TTY or when ACTOOLS_PLAIN is set.
if [[ -t 1 && -z "${ACTOOLS_PLAIN:-}" ]]; then
  _COL_OK='\033[0;32m'
  _COL_WARN='\033[1;33m'
  _COL_FAIL='\033[0;31m'
  _COL_INFO='\033[0;36m'
  _COL_DIM='\033[2m'
  _COL_BOLD='\033[1m'
  _COL_NC='\033[0m'
else
  _COL_OK='' _COL_WARN='' _COL_FAIL='' _COL_INFO='' _COL_DIM='' _COL_BOLD='' _COL_NC=''
fi

# Title bar — printed once at the top of init/preflight/install/handoff/doctor.
print_title() {
  echo
  printf '%b%s%b\n' "$_COL_BOLD$_COL_INFO" "$*" "$_COL_NC"
  echo
}

# Section header — used inside long-running install output.
print_section() {
  echo
  printf '%b── %s ──%b\n' "$_COL_BOLD" "$*" "$_COL_NC"
}

# _print_status STATUS COLOUR LABEL [DETAIL]
# Internal helper. Produces fixed-width status columns for clean alignment.
_print_status() {
  local status="$1" colour="$2" label="$3" detail="${4:-}"
  printf "  %b%-6s%b %-18s %s\n" "$colour" "$status" "$_COL_NC" "$label" "$detail"
}

print_ok()   { _print_status "OK"   "$_COL_OK"   "$@"; }
print_warn() { _print_status "WARN" "$_COL_WARN" "$@"; }
print_fail() { _print_status "FAIL" "$_COL_FAIL" "$@"; }
print_skip() { _print_status "SKIP" "$_COL_DIM"  "$@"; }
print_info() { _print_status "·"    "$_COL_INFO" "$@"; }

# print_fix LINE [...]  — printed under a FAIL or WARN with the remediation.
# Indented to align with the detail column.
print_fix() {
  for line in "$@"; do
    printf "         %bFix:%b %s\n" "$_COL_DIM" "$_COL_NC" "$line"
  done
}

# print_next LINE [...] — final "Next:" block at the bottom of a stage.
print_next() {
  echo
  printf '%bNext:%b\n' "$_COL_BOLD" "$_COL_NC"
  for line in "$@"; do
    echo "  $line"
  done
}

# print_summary FAIL_COUNT WARN_COUNT [OK_MESSAGE] [READY_MESSAGE]
# Used at the bottom of preflight and doctor. Returns 0/1/2 by convention:
#   0  all OK
#   1  one or more failures
#   2  warnings only
print_summary() {
  local fails="$1" warns="$2"
  local ok_msg="${3:-All checks passed.}"
  local ready_msg="${4:-}"
  echo
  if (( fails == 0 && warns == 0 )); then
    echo "$ok_msg"
    [[ -n "$ready_msg" ]] && echo "$ready_msg"
    return 0
  elif (( fails == 0 )); then
    printf '%d warning(s) — see suggested actions above.\n' "$warns"
    [[ -n "$ready_msg" ]] && echo "$ready_msg"
    return 2
  else
    printf '%d failure(s), %d warning(s).\n' "$fails" "$warns"
    return 1
  fi
}
