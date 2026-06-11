#!/usr/bin/env bats
# =============================================================================
# tests/core/bootstrap_test.bats — behavior of the bootstrap unit
# (log / warn / error / section / dryrun) + the v14 path-semantics trap tests.
#
# P0-K extraction: the loader is RE-POINTED at core/bootstrap.sh — the live
# module — with the SAME assertions that captured the inline behavior, which
# is what proves the move was faithful.
#
# The functions read the globals R/G/Y/C/NC (colors) and dryrun reads DRY_RUN
# at call time; the tests provide them, exactly as the live spine does.
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # ── P0-K loader (re-pointed) ── core/bootstrap.sh is the live module.
  source "$REPO/core/bootstrap.sh"

  # Globals the unit relies on (set by the live spine before first call)
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'
}

# --- log / warn / error -------------------------------------------------------

@test "log prints the INFO tag and the message" {
  run log "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO ]"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "warn prints the WARN tag and the message" {
  run warn "be careful"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN ]"* ]]
  [[ "$output" == *"be careful"* ]]
}

@test "error prints the ERROR tag and exits 1" {
  run error "boom"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[ERROR]"* ]]
  [[ "$output" == *"boom"* ]]
}

@test "log timestamps with date '+%F %T' format" {
  run log "ts"
  [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

# --- section -------------------------------------------------------------------

@test "section prints a three-line banner containing the title" {
  run section "My Title"
  [ "$status" -eq 0 ]
  [[ "$output" == *"My Title"* ]]
  [[ "$output" == *"══════"* ]]
  # banner = rule, title, rule (plus the leading blank from \n)
  rules=$(printf '%s\n' "$output" | grep -c "══════")
  [ "$rules" -eq 2 ]
}

# --- dryrun --------------------------------------------------------------------

@test "dryrun with DRY_RUN=true announces instead of executing" {
  DRY_RUN=true
  run dryrun echo "side-effect"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
  [[ "$output" == *"Would run: echo side-effect"* ]]
}

@test "dryrun with DRY_RUN=true does not execute the command" {
  DRY_RUN=true
  marker="$BATS_TEST_TMPDIR/touched"
  run dryrun touch "$marker"
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "dryrun with DRY_RUN=false executes the command" {
  DRY_RUN=false
  run dryrun echo "ran-for-real"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran-for-real"* ]]
  [[ "$output" != *"[DRY-RUN]"* ]]
}

@test "dryrun with DRY_RUN=false propagates the command's exit status" {
  DRY_RUN=false
  run dryrun false
  [ "$status" -ne 0 ]
}

# --- v14 path-semantics traps (the P0-K authority rule) ------------------------

@test "live INSTALL_DIR stays BASH_SOURCE-relative (v14), never the orphan's REAL_HOME form" {
  grep -qF 'INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' "$REPO/actools.sh"
  ! grep -qF 'INSTALL_DIR="$REAL_HOME"' "$REPO/actools.sh"
}

@test "live ENV_FILE and STATE_FILE stay INSTALL_DIR-anchored (v14), not REAL_HOME-anchored" {
  grep -qF 'ENV_FILE="$INSTALL_DIR/actools.env"' "$REPO/actools.sh"
  grep -qF 'STATE_FILE="$INSTALL_DIR/.actools-state.json"' "$REPO/actools.sh"
  ! grep -qF 'ENV_FILE="$REAL_HOME/actools.env"' "$REPO/actools.sh"
  ! grep -qF 'STATE_FILE="$REAL_HOME/.actools-state.json"' "$REPO/actools.sh"
}

@test "core/bootstrap.sh defines functions only — no stale v9.2 orphan assignment survives" {
  # The stale orphan set INSTALL_DIR="$REAL_HOME" and re-derived
  # MODE/REAL_USER/ENV_FILE/STATE_FILE/LOG_*/version. The live module must
  # never assign any of these — path/variable authority stays in actools.sh.
  ! grep -qE '^[[:space:]]*(export[[:space:]]+)?(INSTALL_DIR|ENV_FILE|STATE_FILE|REAL_HOME|REAL_USER|MODE|ACTOOLS_VERSION|LOCK_FILE|LOG_FILE|LOG_DIR|RUN_LOG|PKG_DONE_FLAG|DRY_RUN)=' "$REPO/core/bootstrap.sh"
  # ...and it must define exactly the five bootstrap functions.
  run grep -cE '^[a-z_]+\(\)' "$REPO/core/bootstrap.sh"
  [ "$output" = "5" ]
}
