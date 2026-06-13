#!/usr/bin/env bats
# =============================================================================
# tests/guards/cli_db_authority_guard_test.bats — P0-N guard, tightened @ P0-O
# (the six DB functions are defined ONLY in modules/db/core.sh)
#
# FAILS when any of the six canonical DB-layer names
#   db_exec_root db_exec_root_stdin db_dump_container setup_backup_db_user
#   wait_db check_db_creds
# is DEFINED (`^name()`) on a CLI file. P0-N converged the one live dual-truth
# left after P0-M — cli/commands/doctor.sh carried its own (then byte-identical)
# db_exec_root copy, so a future fix to the module would silently not reach
# `doctor`. This guard exists so that copy — or any new one — can never come
# back on a CLI file.
#
# TWO complementary scopes, each with its own oracle and non-vacuity arm:
#
#   (1) LIVE CLI PATH — _assert_cli_db_authority (P0-N, retained):
#       * cli/actools (the CLI entrypoint, installed by copy — P0-F), PLUS
#       * every `source "${INSTALL_DIR}/cli/commands/<f>.sh"` target parsed
#         out of cli/actools (today: doctor.sh). One level — the live CLI path
#         is what cli/actools itself wires in. This arm covers cli/actools,
#         which the repo-wide arm (cli/commands-only) does not see.
#
#   (2) REPO-WIDE CLI — _assert_repo_wide_cli_db_authority (P0-O, new):
#       * EVERY regular file in cli/commands/ (find -maxdepth 1 -type f),
#         not just the ones cli/actools sources. After the P0-O deletion only
#         doctor.sh + doctor_deep.sh remain, neither defines a DB fn → green.
#         Strictly stronger than the live-path scope for cli/commands: a DB-fn
#         copy on ANY future command file is caught the moment it lands, before
#         anything wires it in. No allow/deny list needed.
#
# P0-O RELEASE NOTE — this is an INTENTIONAL edit to the P0-N guard:
#   * The eight dead-twin cli/commands files (backup, ci_generate,
#     cost_optimize, health, restore, storage, update, worker) are DELETED in
#     P0-O — three carried inert byte-identical DB-fn copies. The old
#     DEAD_TWINS array and the "excluded by construction" arm that named them
#     are removed (nothing left to exclude); the exclusion logic is replaced
#     by the stronger repo-wide-CLI arm (2) above.
#
# Excluded by construction (NOT scanned):
#   * modules/db/core.sh — the P0-M AUTHORITY. It is not a cli/commands file
#     and neither oracle recurses into source lines of CLI files, so
#     doctor.sh's `source .../modules/db/core.sh` cannot drag the authority
#     into its own ban. (A sanity arm below pins that the authority still
#     defines all six.)
#
# Non-vacuous: each oracle has a permanent fixture arm that injects a DB-fn
# definition into a doctored tree and asserts the SAME oracle fails it —
# (1) on a live command file and on cli/actools itself; (2) on a rogue
# cli/commands file the live path would never source.
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
# _assert_repo_wide_cli_db_authority <repo_root>  (P0-O)
# The repo-wide-CLI oracle: scans EVERY regular file in cli/commands/ (one
# level, find -maxdepth 1 -type f — not just the files cli/actools sources)
# and fails, echoing each violation, if any defines one of the six canonical
# DB names. After the P0-O twin deletion only doctor.sh + doctor_deep.sh
# remain. Used by the main repo-wide arm (expects PASS) and its non-vacuity
# arm (expects FAIL on a rogue command file).
# ---------------------------------------------------------------------------
_assert_repo_wide_cli_db_authority() {
  local repo="$1" dir="$1/cli/commands" f fn hits
  local -a violations=()
  [[ -d "$dir" ]] || {
    echo "cli/commands/ missing on disk: $dir"
    echo "(the repo-wide CLI scan needs the directory — wrong wiring, not a"
    echo "guard exemption)"
    return 1
  }
  while IFS= read -r f; do
    for fn in "${CLI_DB_FUNCTIONS[@]}"; do
      hits="$(grep -nE "^${fn}\(\)" "$f" || true)"
      [[ -n "$hits" ]] && violations+=("cli/commands/$(basename "$f"):${hits%%:*}: ${fn}() defined")
    done
  done < <(find "$dir" -maxdepth 1 -type f | sort)

  if (( ${#violations[@]} > 0 )); then
    echo "DB-layer function DEFINED on a cli/commands file (repo-wide CLI scan):"
    printf '  %s\n' "${violations[@]}"
    echo ""
    echo "The six DB functions have exactly ONE authority: modules/db/core.sh"
    echo "(P0-M). No cli/commands file may define them — P0-O deleted the dead"
    echo "twins that once did; a CLI command must source the module, never copy."
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
# Repo-wide-CLI arm (P0-O): no file in cli/commands/ defines any of the six,
# not just the files cli/actools sources. After the P0-O twin deletion only
# doctor.sh + doctor_deep.sh remain — neither defines a DB fn. This replaces
# the P0-N dead-twin "excluded by construction" arm: with the twins gone there
# is nothing to exclude, and banning the six names on EVERY command file is
# the stronger, list-free invariant.
# ---------------------------------------------------------------------------

@test "no DB-layer function is defined on ANY cli/commands file (repo-wide CLI, authority: modules/db/core.sh)" {
  _assert_repo_wide_cli_db_authority "$REPO"
}

# ---------------------------------------------------------------------------
# Non-vacuity arm for the repo-wide oracle: a rogue cli/commands file that the
# live CLI path would never source (cli/actools sources only doctor.sh) still
# trips the repo-wide scan. Proves the arm above is not vacuously green just
# because today's two survivors happen to be clean.
# ---------------------------------------------------------------------------

@test "non-vacuous: an injected db_exec_root definition on a rogue cli/commands file FAILS the repo-wide check" {
  local fix="$BATS_TEST_TMPDIR/fixture-repowide"
  mkdir -p "$fix/cli/commands"
  # A clean survivor (mirrors the real doctor.sh: sources the module, no copy).
  cat > "$fix/cli/commands/doctor.sh" <<'FIX'
#!/usr/bin/env bash
source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true
run_doctor() { db_exec_root -e "SELECT 1;"; }
FIX
  # A rogue command file nothing wires in, carrying a DB-fn copy.
  cat > "$fix/cli/commands/rogue.sh" <<'FIX'
#!/usr/bin/env bash
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}
FIX
  # Self-check: the doctoring took (else the arm proves nothing).
  grep -qE '^db_exec_root\(\)' "$fix/cli/commands/rogue.sh"

  run _assert_repo_wide_cli_db_authority "$fix"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cli/commands/rogue.sh"*"db_exec_root() defined"* ]]
}
