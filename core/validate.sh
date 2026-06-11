#!/usr/bin/env bash
# =============================================================================
# core/validate.sh — env-file format validation
#
# LIVE AUTHORITY (P0-K): carries the monolith's exact validate_env definition,
# extracted VERBATIM from the inline v14 block in actools.sh. Sourced by
# actools.sh on the live install path, immediately before the validate_env
# call.
#
# Required collaborators (provided by actools.sh BEFORE the call):
#   log/error — core/bootstrap.sh
# Reads PHP_MEMORY_LIMIT / WORKER_MEMORY_LIMIT / DB_MEMORY_LIMIT / PHP_VERSION
# with :- defaults — safe under `set -u` even when unset.
#
# Functions only — no variable assignments. The S3 gate, S3 provider
# auto-detection, XeLaTeX/environment-mode/disk checks deliberately STAY
# top-level in actools.sh — they are spine code in v14, not unit functions.
# In particular the live S3 default is ${ENABLE_S3_STORAGE:-true}; the stale
# v9.2 orphan that previously lived here carried validate_s3() with :-false
# plus detect_s3_provider/validate_xelatex/validate_environment_mode/
# validate_disk twins — ALL retired (P0-K). This module must never reference
# ENABLE_S3_STORAGE.
# =============================================================================

validate_env() {
  [[ "${PHP_MEMORY_LIMIT:-512m}" =~ ^[0-9]+[mg]$ ]] || \
    error "PHP_MEMORY_LIMIT format invalid ('${PHP_MEMORY_LIMIT}'). Use: 512m or 2g"
  [[ "${WORKER_MEMORY_LIMIT:-2g}" =~ ^[0-9]+[mg]$ ]] || \
    error "WORKER_MEMORY_LIMIT format invalid ('${WORKER_MEMORY_LIMIT}'). Use: 2g or 1024m"
  [[ "${DB_MEMORY_LIMIT:-2g}" =~ ^[0-9]+[mg]$ ]] || \
    error "DB_MEMORY_LIMIT format invalid ('${DB_MEMORY_LIMIT}'). Use: 2g or 1024m"
  [[ "${PHP_VERSION:-8.3}" =~ ^[0-9]+\.[0-9]+$ ]] || \
    error "PHP_VERSION format invalid: '${PHP_VERSION}'. Expected e.g. 8.3"
  log ".env validation passed."
}
