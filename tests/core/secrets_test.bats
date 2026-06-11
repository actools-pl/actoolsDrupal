#!/usr/bin/env bats
# =============================================================================
# tests/core/secrets_test.bats — behavior of the secrets unit
# (rand_pass / gen_if_empty / get_db_pass / get_backup_pass) + the live
# top-level secret-writeback loop (v9.2 fix7).
#
# P0-K extraction: the loader is RE-POINTED at core/secrets.sh — the live
# module — with the SAME assertions that captured the inline behavior, which
# is what proves the move was faithful. The live top-level writeback loop
# (v9.2 fix7) stays in actools.sh and stays pinned here via the extractor.
#
# History: this file previously sourced the stale orphan core/secrets.sh and
# tested its orphan-only writeback_secrets() twin. P0-K retired the stale
# orphans; the writeback behavior is pinned where it actually lives — the
# top-level loop in actools.sh (which P0-K deliberately did NOT move).
#
# get_db_pass/get_backup_pass call get_state/set_state (the state unit) and
# rand_pass at runtime, and rely on STATE_FILE — the tests provide all three,
# exactly as the live spine does.
# =============================================================================

load extract_inline

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # ── P0-K loader (re-pointed) ── core/secrets.sh is the live module.
  source "$REPO/core/secrets.sh"
  # runtime collaborators from the state unit (live module since P0-K state
  # extraction — re-pointed in the same commit that moved them)
  source "$REPO/core/state.sh"

  # Logging stubs (the unit calls log/error; stub AFTER loading so they win)
  log()   { echo "LOG: $*"; }
  warn()  { echo "WARN: $*"; }
  error() { echo "ERROR: $*"; exit 1; }

  # Globals the unit relies on
  STATE_FILE="$BATS_TEST_TMPDIR/.actools-state.json"
  echo '{"envs":{},"db_passes":{}}' > "$STATE_FILE"
}

# --- rand_pass ------------------------------------------------------------------

@test "rand_pass generates a non-empty string" {
  result=$(rand_pass)
  [ -n "$result" ]
}

@test "rand_pass generates exactly 22 characters" {
  result=$(rand_pass)
  [ "${#result}" -eq 22 ]
}

@test "rand_pass generates only alphanumeric characters" {
  result=$(rand_pass)
  [[ "$result" =~ ^[A-Za-z0-9]+$ ]]
}

@test "rand_pass generates different values each time" {
  pass1=$(rand_pass)
  pass2=$(rand_pass)
  [ "$pass1" != "$pass2" ]
}

# --- gen_if_empty ---------------------------------------------------------------

@test "gen_if_empty leaves an existing value unchanged" {
  MY_VAR="existing_value"
  gen_if_empty MY_VAR
  [ "$MY_VAR" = "existing_value" ]
}

@test "gen_if_empty generates a 22-char alphanumeric value when empty" {
  MY_VAR=""
  gen_if_empty MY_VAR
  [ -n "$MY_VAR" ]
  [ "${#MY_VAR}" -eq 22 ]
  [[ "$MY_VAR" =~ ^[A-Za-z0-9]+$ ]]
}

@test "gen_if_empty errors on a CHANGEME value" {
  MY_VAR="CHANGEME"
  run gen_if_empty MY_VAR
  [ "$status" -ne 0 ]
  [[ "$output" == *"CHANGEME"* ]]
}

# --- get_db_pass ----------------------------------------------------------------

@test "get_db_pass generates and persists a 22-char password for a fresh env" {
  pass=$(get_db_pass prod)
  [ "${#pass}" -eq 22 ]
  [[ "$pass" =~ ^[A-Za-z0-9]+$ ]]
  run jq -r '.db_passes.prod' "$STATE_FILE"
  [ "$output" = "$pass" ]
}

@test "get_db_pass is stable — the second call returns the persisted password" {
  pass1=$(get_db_pass prod)
  pass2=$(get_db_pass prod)
  [ "$pass1" = "$pass2" ]
}

@test "get_db_pass returns a pre-existing stored password verbatim" {
  echo '{"envs":{},"db_passes":{"stg":"already-stored-pass"}}' > "$STATE_FILE"
  pass=$(get_db_pass stg)
  [ "$pass" = "already-stored-pass" ]
}

@test "get_db_pass keeps per-env passwords independent" {
  p_prod=$(get_db_pass prod)
  p_dev=$(get_db_pass dev)
  [ "$p_prod" != "$p_dev" ]
  run jq -r '.db_passes.dev' "$STATE_FILE"
  [ "$output" = "$p_dev" ]
}

# --- get_backup_pass ------------------------------------------------------------

@test "get_backup_pass generates and persists a 22-char password when unset" {
  pass=$(get_backup_pass)
  [ "${#pass}" -eq 22 ]
  [[ "$pass" =~ ^[A-Za-z0-9]+$ ]]
  run jq -r '.backup_user_pass' "$STATE_FILE"
  [ "$output" = "$pass" ]
}

@test "get_backup_pass is stable across calls" {
  pass1=$(get_backup_pass)
  pass2=$(get_backup_pass)
  [ "$pass1" = "$pass2" ]
}

# --- live secret-writeback loop (v9.2 fix7 — stays top-level in actools.sh) -----

_writeback_harness() {  # <env-file> <db-pass> <admin-pass>
  {
    echo 'log() { :; }'
    printf 'ENV_FILE=%q\n'          "$1"
    printf 'DB_ROOT_PASS=%q\n'      "$2"
    printf 'DRUPAL_ADMIN_PASS=%q\n' "$3"
    extract_inline_writeback "$REPO/actools.sh"
  } > "$BATS_TEST_TMPDIR/writeback_harness.sh"
  bash "$BATS_TEST_TMPDIR/writeback_harness.sh"
}

@test "live writeback fills an empty DB_ROOT_PASS= line" {
  envf="$BATS_TEST_TMPDIR/env"
  printf 'DB_ROOT_PASS=\nDRUPAL_ADMIN_PASS=\n' > "$envf"
  run _writeback_harness "$envf" "newpassword123" "adminpass456"
  [ "$status" -eq 0 ]
  grep -q '^DB_ROOT_PASS=newpassword123$' "$envf"
  grep -q '^DRUPAL_ADMIN_PASS=adminpass456$' "$envf"
}

@test "live writeback does not overwrite an already-set value" {
  envf="$BATS_TEST_TMPDIR/env"
  printf 'DB_ROOT_PASS=alreadyset\nDRUPAL_ADMIN_PASS=\n' > "$envf"
  run _writeback_harness "$envf" "shouldnotreplace" "adminpass"
  [ "$status" -eq 0 ]
  grep -q '^DB_ROOT_PASS=alreadyset$' "$envf"
}

@test "live writeback handles a trailing comment on the empty line (fix7)" {
  envf="$BATS_TEST_TMPDIR/env"
  printf 'DB_ROOT_PASS=   # set before install\nDRUPAL_ADMIN_PASS=\n' > "$envf"
  run _writeback_harness "$envf" "newpass999" "adminpass"
  [ "$status" -eq 0 ]
  grep -q '^DB_ROOT_PASS=newpass999$' "$envf"
}

# --- stale-orphan content ban (P0-K) ---------------------------------------------

@test "core/secrets.sh defines exactly the four secrets functions — orphan twin retired" {
  # The stale v9.2 orphan carried a writeback_secrets() twin of the live
  # top-level loop; it must never reappear — the writeback stays spine code.
  run grep -cE '^[a-z_]+\(\)' "$REPO/core/secrets.sh"
  [ "$output" = "4" ]
  ! grep -qE '^writeback_secrets\(\)' "$REPO/core/secrets.sh"
  # ...and no variable assignments survive either.
  ! grep -qE '^[[:space:]]*(export[[:space:]]+)?[A-Z_]+=' "$REPO/core/secrets.sh"
}
