#!/usr/bin/env bats
# =============================================================================
# tests/core/validate_test.bats — behavior of the validate unit (validate_env)
# + the live S3-default trap tests (the P0-K authority rule).
#
# P0-K extraction: the loader is RE-POINTED at core/validate.sh — the live
# module — with the SAME assertions that captured the inline behavior, which
# is what proves the move was faithful.
#
# History: this file previously sourced the stale orphan core/validate.sh and
# tested its orphan-only twins (detect_s3_provider/validate_s3/...). P0-K
# retired the stale orphans: the live v14 code keeps S3 detection and the S3
# gate as TOP-LEVEL spine code (not functions), with the v14 default
# ${ENABLE_S3_STORAGE:-true} — the orphan's :-false must never survive. The
# statics below pin exactly that, and ban any S3 reference from the module.
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # ── P0-K loader (re-pointed) ── core/validate.sh is the live module.
  source "$REPO/core/validate.sh"

  # Logging stubs (the unit calls log/error; stub AFTER loading so they win)
  log()   { echo "LOG: $*"; }
  warn()  { echo "WARN: $*"; }
  error() { echo "ERROR: $*"; exit 1; }
}

# --- validate_env: format rules --------------------------------------------------

@test "PHP_MEMORY_LIMIT accepts 512m" {
  PHP_MEMORY_LIMIT=512m
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -eq 0 ]
}

@test "PHP_MEMORY_LIMIT accepts 2g" {
  PHP_MEMORY_LIMIT=2g
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -eq 0 ]
}

@test "PHP_MEMORY_LIMIT rejects 512MB" {
  PHP_MEMORY_LIMIT=512MB
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -ne 0 ]
}

@test "PHP_MEMORY_LIMIT rejects a non-size value" {
  PHP_MEMORY_LIMIT=bad
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -ne 0 ]
}

@test "PHP_VERSION accepts 8.3" {
  PHP_MEMORY_LIMIT=512m
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -eq 0 ]
}

@test "PHP_VERSION rejects 8" {
  PHP_MEMORY_LIMIT=512m
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8
  run validate_env
  [ "$status" -ne 0 ]
}

@test "validate_env passes on an empty environment (the :- defaults are valid)" {
  unset PHP_MEMORY_LIMIT WORKER_MEMORY_LIMIT DB_MEMORY_LIMIT PHP_VERSION
  run validate_env
  [ "$status" -eq 0 ]
  [[ "$output" == *"validation passed"* ]]
}

# --- v14 S3-default traps (the P0-K authority rule) -------------------------------

@test "live S3 gate keeps the v14 default ENABLE_S3_STORAGE:-true, never :-false" {
  grep -q 'ENABLE_S3_STORAGE:-true' "$REPO/actools.sh"
  ! grep -q 'ENABLE_S3_STORAGE:-false' "$REPO/actools.sh"
}

@test "every ENABLE_S3_STORAGE default in the live spine is :-true" {
  total=$(grep -o 'ENABLE_S3_STORAGE:-[a-z]*' "$REPO/actools.sh" | wc -l)
  trues=$(grep -o 'ENABLE_S3_STORAGE:-true'   "$REPO/actools.sh" | wc -l)
  [ "$trues" -ge 1 ]
  [ "$total" -eq "$trues" ]
}

# --- stale-orphan content ban (P0-K) ---------------------------------------------

@test "core/validate.sh has no ENABLE_S3_STORAGE code reference — the orphan's :-false twin is retired" {
  # The stale v9.2 orphan carried validate_s3() with ${ENABLE_S3_STORAGE:-false}.
  # The live S3 gate is top-level spine code in actools.sh (:-true); the live
  # module must contain no S3 logic at all. (Comment lines documenting the
  # retirement are allowed; CODE lines are not.)
  ! grep -vE '^[[:space:]]*#' "$REPO/core/validate.sh" | grep -q 'ENABLE_S3_STORAGE'
}

@test "core/validate.sh defines exactly validate_env — orphan twins retired" {
  run grep -cE '^[a-z_]+\(\)' "$REPO/core/validate.sh"
  [ "$output" = "1" ]
  grep -qE '^validate_env\(\)' "$REPO/core/validate.sh"
  ! grep -qE '^(detect_s3_provider|validate_s3|validate_xelatex|validate_environment_mode|validate_disk)\(\)' "$REPO/core/validate.sh"
  # ...and no variable assignments survive either.
  ! grep -qE '^[[:space:]]*(export[[:space:]]+)?[A-Z_]+=' "$REPO/core/validate.sh"
}
