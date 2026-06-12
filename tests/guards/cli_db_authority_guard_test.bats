#!/usr/bin/env bats
# =============================================================================
# tests/guards/cli_db_authority_guard_test.bats — P0-N guard
# (live CLI path: the six DB functions are defined ONLY in modules/db/core.sh)
#
# FAILS when any of the six canonical DB-layer names
#   db_exec_root db_exec_root_stdin db_dump_container setup_backup_db_user
#   wait_db check_db_creds
# is DEFINED (`^name()`) on the LIVE CLI PATH. P0-N converged the one live
# dual-truth left after P0-M — cli/commands/doctor.sh carried its own (then
# byte-identical) db_exec_root copy, so a future fix to the module would
# silently not reach `doctor`. This guard exists so that copy — or any new
# one — can never come back on a live CLI file.
#
# The LIVE CLI PATH (this guard's scope) is:
#   * cli/actools (the CLI entrypoint, installed by copy — P0-F), PLUS
#   * every `source "${INSTALL_DIR}/cli/commands/<f>.sh"` target parsed out
#     of cli/actools (today: doctor.sh). One level, per the P0-N spec — the
#     live CLI path is what cli/actools itself wires in.
#
# Excluded by construction (NOT scanned):
#   * modules/db/core.sh — the P0-M AUTHORITY. It is not a cli/commands file
#     and the builder never recurses into source lines of live command files,
#     so doctor.sh's `source .../modules/db/core.sh` cannot drag the authority
#     into its own ban. (A sanity arm below pins that the authority still
#     defines all six.)
#   * the eight DEAD-TWIN cli/commands files (backup, ci_generate,
#     cost_optimize, health, restore, storage, update, worker) — their cmd_*
#     functions are called 0x in cli/actools (every command is inline), so
#     cli/actools sources none of them and the builder naturally excludes
#     them. Several still define DB-fn copies on disk; that is P0-O's job
#     (deletion), and this guard stays green before and after it.
#
# Non-vacuous: a permanent fixture arm builds a simulated live CLI tree with
# an injected db_exec_root definition (once on a live command file, once on
# cli/actools itself) and the SAME oracle must fail it.
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

CLI_DB_FUNCTIONS=(
  db_exec_root
  db_exec_root_stdin
  db_dump_container
  setup_backup_db_user
  wait_db
  check_db_creds
)

DEAD_TWINS=(
  cli/commands/backup.sh
  cli/commands/ci_generate.sh
  cli/commands/cost_optimize.sh
  cli/commands/health.sh
  cli/commands/restore.sh
  cli/commands/storage.sh
  cli/commands/update.sh
  cli/commands/worker.sh
)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# ---------------------------------------------------------------------------
# build_live_cli_set <repo_root>
# Fills the global LIVE_CLI_SET array with cli/actools plus every
# `source "${INSTALL_DIR}/cli/commands/<f>.sh"` target parsed out of
# cli/actools (static one-level derivation; both `source` and `.` forms).
# ---------------------------------------------------------------------------
build_live_cli_set() {
  local repo="$1" t
  LIVE_CLI_SET=("cli/actools")
  while IFS= read -r t; do
    [[ -n "$t" ]] && LIVE_CLI_SET+=("cli/commands/${t}")
  done < <(sed -n -E \
    's/^[[:space:]]*(source|\.)[[:space:]]+"\$\{INSTALL_DIR\}\/cli\/commands\/([^"]+)".*/\2/p' \
    "$repo/cli/actools" | sort -u)
}

# ---------------------------------------------------------------------------
# _assert_cli_db_authority <repo_root>
# The single oracle every arm uses (including the non-vacuity arms, which
# expect it to FAIL on the doctored trees). Fails — echoing each violation —
# if any canonical DB name is DEFINED on the live CLI path, or if a live
# source target is missing (wrong wiring must not pass silently).
# ---------------------------------------------------------------------------
_assert_cli_db_authority() {
  local repo="$1" f fn hits
  local -a violations=()
  build_live_cli_set "$repo"

  for f in "${LIVE_CLI_SET[@]}"; do
    [[ -f "$repo/$f" ]] || {
      echo "live CLI source target missing on disk: $f"
      echo "(cli/actools sources it — wrong wiring, not a guard exemption)"
      return 1
    }
    for fn in "${CLI_DB_FUNCTIONS[@]}"; do
      hits="$(grep -nE "^${fn}\(\)" "$repo/$f" || true)"
      [[ -n "$hits" ]] && violations+=("$f:${hits%%:*}: ${fn}() defined")
    done
  done

  if (( ${#violations[@]} > 0 )); then
    echo "DB-layer function DEFINED on the live CLI path:"
    printf '  %s\n' "${violations[@]}"
    echo ""
    echo "The six DB functions have exactly ONE authority: modules/db/core.sh"
    echo "(P0-M). A live CLI file must source the module, never redefine —"
    echo "a local copy is the dual-truth P0-N removed from doctor.sh: a fix"
    echo "to the module would silently not reach the copy."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Sanity arms: the builder resolves the known live CLI shape, and the
# authority itself still defines all six names (the guard bans definitions
# everywhere on the live CLI path BECAUSE the module provides them).
# ---------------------------------------------------------------------------

@test "live-CLI-set sanity: cli/actools plus its sourced command files (doctor.sh today)" {
  build_live_cli_set "$REPO"
  (( ${#LIVE_CLI_SET[@]} >= 2 )) || {
    echo "Live CLI set suspiciously small (${#LIVE_CLI_SET[@]}):"
    printf '  %s\n' "${LIVE_CLI_SET[@]}"
    return 1
  }
  local must found
  for must in "cli/actools" "cli/commands/doctor.sh"; do
    found=0
    for f in "${LIVE_CLI_SET[@]}"; do [[ "$f" == "$must" ]] && found=1; done
    (( found )) || {
      echo "Expected live CLI file missing from the derived set: $must"
      printf 'Set was:\n'; printf '  %s\n' "${LIVE_CLI_SET[@]}"
      return 1
    }
  done
}

@test "authority sanity: modules/db/core.sh defines all six canonical DB functions" {
  local fn
  for fn in "${CLI_DB_FUNCTIONS[@]}"; do
    grep -qE "^${fn}\(\)" "$REPO/modules/db/core.sh" || {
      echo "Authority broken: ${fn}() not defined in modules/db/core.sh."
      echo "doctor's DB check (and the installer) resolve the six names there."
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# Main arm: the live CLI path defines none of the six.
# ---------------------------------------------------------------------------

@test "no DB-layer function is defined on the live CLI path (authority: modules/db/core.sh)" {
  _assert_cli_db_authority "$REPO"
}

# ---------------------------------------------------------------------------
# Non-vacuity arms (permanent): the SAME oracle must BITE on an injected
# definition. The fixture is a simulated live CLI tree: a minimal cli/actools
# that sources one command file, with db_exec_root injected (a) on the live
# command file — the exact doctor.sh regression P0-N removed — and (b) on
# cli/actools itself. Each arm self-checks that the injection took.
# ---------------------------------------------------------------------------

_make_fixture_tree() {
  # _make_fixture_tree <dir> — minimal live CLI shape mirroring the real one.
  local dir="$1"
  mkdir -p "$dir/cli/commands"
  cat > "$dir/cli/actools" <<'FIX'
#!/usr/bin/env bash
INSTALL_DIR="${ACTOOLS_HOME:-/opt/actools}"
case "${1:-help}" in
  doctor)
    # shellcheck source=/dev/null
    source "${INSTALL_DIR}/cli/commands/doctor.sh"
    run_doctor "$@"
    ;;
esac
FIX
  cat > "$dir/cli/commands/doctor.sh" <<'FIX'
#!/usr/bin/env bash
source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true
run_doctor() { db_exec_root -e "SELECT 1;"; }
FIX
}

@test "non-vacuous: an injected db_exec_root definition on a live command file FAILS the check" {
  local fix="$BATS_TEST_TMPDIR/fixture-cmdfile"
  _make_fixture_tree "$fix"
  cat >> "$fix/cli/commands/doctor.sh" <<'FIX'
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}
FIX
  # Self-check: the doctoring took (else the arm proves nothing).
  grep -qE '^db_exec_root\(\)' "$fix/cli/commands/doctor.sh"

  run _assert_cli_db_authority "$fix"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cli/commands/doctor.sh"*"db_exec_root() defined"* ]]
}

@test "non-vacuous: an injected definition on cli/actools itself FAILS the check" {
  local fix="$BATS_TEST_TMPDIR/fixture-entrypoint"
  _make_fixture_tree "$fix"
  printf '%s\n' 'wait_db() { :; }' >> "$fix/cli/actools"
  grep -qE '^wait_db\(\)' "$fix/cli/actools"

  run _assert_cli_db_authority "$fix"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cli/actools"*"wait_db() defined"* ]]
}

@test "non-vacuous: a missing live source target FAILS the check (wrong wiring is loud)" {
  local fix="$BATS_TEST_TMPDIR/fixture-missing"
  _make_fixture_tree "$fix"
  rm "$fix/cli/commands/doctor.sh"

  run _assert_cli_db_authority "$fix"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing on disk"* ]]
}

# ---------------------------------------------------------------------------
# Dead-twin exclusion: the eight dead cli/commands files are NOT on the live
# CLI path (cli/actools sources none of them — every command is inline), so
# their on-disk DB-fn copies cannot trip this guard. Green pre-P0-O (the
# twins still exist and several still define DB fns) and post-P0-O (deleted;
# the existence check below skips absent files).
# ---------------------------------------------------------------------------

@test "the eight dead twins are excluded by construction (guard green pre-P0-O)" {
  build_live_cli_set "$REPO"
  local twin f
  for twin in "${DEAD_TWINS[@]}"; do
    [[ -f "$REPO/$twin" ]] || continue   # post-P0-O: deleted, nothing to exclude
    for f in "${LIVE_CLI_SET[@]}"; do
      [[ "$f" == "$twin" ]] && {
        echo "Dead twin appeared on the live CLI path: $twin"
        echo "Wiring a dead twin is P0-O-forbidden scope; if it was wired"
        echo "deliberately, it must first lose its DB-fn copies (the oracle"
        echo "above will also be failing on them)."
        return 1
      }
    done
  done
  true
}
