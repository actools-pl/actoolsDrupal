#!/usr/bin/env bats
# =============================================================================
# tests/core/state_test.bats — behavior of the state unit
# (init_state / set_state / get_state / is_installed / mark_installed).
#
# P0-K extraction: the loader is RE-POINTED at core/state.sh — the live
# module — with the SAME assertions that captured the inline behavior, which
# is what proves the move was faithful.
#
# The unit relies on the globals STATE_FILE and REAL_USER (set by the live
# spine) and on jq; the tests provide them. The jq/state-file path semantics
# (atomic tmp+mv writes, "null" on missing keys) are part of the captured
# behavior and MUST NOT change in the extraction.
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # ── P0-K loader (re-pointed) ── core/state.sh is the live module.
  source "$REPO/core/state.sh"

  # Globals the unit relies on
  STATE_FILE="$BATS_TEST_TMPDIR/.actools-state.json"
  REAL_USER="$(id -un)"
}

# --- init_state ----------------------------------------------------------------

@test "init_state creates the empty state skeleton" {
  [ ! -f "$STATE_FILE" ]
  init_state
  [ -f "$STATE_FILE" ]
  run jq -c . "$STATE_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = '{"envs":{},"db_passes":{}}' ]
}

@test "init_state is idempotent — it never clobbers an existing state file" {
  echo '{"envs":{"prod":true},"db_passes":{"prod":"keepme"}}' > "$STATE_FILE"
  init_state
  run jq -r '.db_passes.prod' "$STATE_FILE"
  [ "$output" = "keepme" ]
  run jq -r '.envs.prod' "$STATE_FILE"
  [ "$output" = "true" ]
}

# --- set_state / get_state ------------------------------------------------------

@test "set_state and get_state round-trip a value through jq" {
  init_state
  set_state '.answer="forty-two"'
  run get_state '.answer'
  [ "$status" -eq 0 ]
  [ "$output" = "forty-two" ]
}

@test "set_state writes atomically and leaves valid JSON" {
  init_state
  set_state '.db_passes.prod="p1"'
  set_state '.db_passes.stg="p2"'
  run jq -r '.db_passes.prod + ":" + .db_passes.stg' "$STATE_FILE"
  [ "$output" = "p1:p2" ]
}

@test "get_state returns the literal string null for a missing key" {
  init_state
  run get_state '.does.not.exist'
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "get_state returns the literal string null when the state file is absent" {
  [ ! -f "$STATE_FILE" ]
  run get_state '.anything'
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

# --- is_installed / mark_installed ----------------------------------------------

@test "is_installed is false for an environment never marked" {
  init_state
  run is_installed prod
  [ "$status" -ne 0 ]
}

@test "mark_installed flips is_installed to true and persists envs.<env>=true" {
  init_state
  run is_installed prod
  [ "$status" -ne 0 ]
  mark_installed prod
  run is_installed prod
  [ "$status" -eq 0 ]
  run jq -r '.envs.prod' "$STATE_FILE"
  [ "$output" = "true" ]
}

@test "mark_installed for one env does not mark another" {
  init_state
  mark_installed stg
  run is_installed prod
  [ "$status" -ne 0 ]
  run is_installed stg
  [ "$status" -eq 0 ]
}

# --- stale-orphan content ban (P0-K) ---------------------------------------------

@test "core/state.sh defines exactly the five state functions — orphan twins retired" {
  # The stale v9.2 orphan also carried get_db_pass/get_backup_pass twins;
  # those belong to the secrets unit and must never reappear here.
  run grep -cE '^[a-z_]+\(\)' "$REPO/core/state.sh"
  [ "$output" = "5" ]
  ! grep -qE '^(get_db_pass|get_backup_pass)\(\)' "$REPO/core/state.sh"
  # ...and no variable assignments survive either.
  ! grep -qE '^[[:space:]]*(export[[:space:]]+)?[A-Z_]+=' "$REPO/core/state.sh"
}
