#!/usr/bin/env bats
# =============================================================================
# tests/cli/doctor_db_authority_test.bats — P0-N focused authority test
# (the live doctor command resolves db_exec_root to modules/db/core.sh)
#
# P0-N deleted doctor.sh's local db_exec_root copy (byte-identical to the
# P0-M authority at the time) and pointed the file at the module:
#   source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true
# at the exact top-level spot the local def occupied. This suite pins the
# convergence from the RESOLUTION side (the guard in tests/guards/ pins it
# from the definition side):
#
#   shape  : no local db_exec_root definition remains; the authority source
#            line is present (best-effort — doctor.sh stays sourceable in a
#            minimal sandbox, its pre-P0-N contract)
#   inert  : sourcing doctor.sh runs nothing and prints nothing (pure defs;
#            the module is pure defs too)
#   resolve: with INSTALL_DIR at the repo, sourcing doctor.sh defines
#            db_exec_root AT SOURCE TIME (the old local-def timing) and its
#            body is byte-equal to the canonical core.sh body — and the
#            non-vacuity twin: in a sandbox WITHOUT the module, db_exec_root
#            does NOT come out defined, so the definition provably arrives
#            via ${INSTALL_DIR}/modules/db/core.sh (a typo'd path goes red
#            here, which is what makes the `|| true` safe)
#   oracle : the resolved db_exec_root, run under the P0-M mock docker,
#            issues the exact canonical container command (the same argv pin
#            as tests/db/db_contract_test.bats)
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

load doctor_loader

DB_LAYER_FUNCTIONS=(
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
# Shape: the local def is gone; the authority source line is present.
# ---------------------------------------------------------------------------

@test "doctor.sh carries no local db_exec_root definition (the P0-N deletion holds)" {
  run grep -nE '^db_exec_root\(\)' "$REPO/cli/commands/doctor.sh"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "doctor.sh sources the P0-M authority (modules/db/core.sh)" {
  grep -qE 'source[[:space:]]+"\$\{INSTALL_DIR\}/modules/db/core\.sh"' \
    "$REPO/cli/commands/doctor.sh"
}

# ---------------------------------------------------------------------------
# Inert: sourcing doctor.sh executes nothing.
# ---------------------------------------------------------------------------

@test "sourcing doctor.sh is inert — rc 0, no output (pure defs + inert module source)" {
  run bash -uc "INSTALL_DIR='$REPO'
    source '$REPO/cli/commands/doctor.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Resolution: db_exec_root is defined at source time and IS the canonical one.
# ---------------------------------------------------------------------------

@test "after sourcing doctor.sh, db_exec_root is defined and its body matches core.sh (byte-equal declare -f)" {
  load_doctor "$REPO"
  declare -F db_exec_root >/dev/null

  local canonical resolved
  canonical="$(env -i bash --noprofile --norc -uc \
    "source '$REPO/modules/db/core.sh'; declare -f db_exec_root")"
  resolved="$(declare -f db_exec_root)"
  [ -n "$canonical" ]
  [ "$resolved" = "$canonical" ]
}

@test "all six DB-layer functions arrive from the module (five inert extras included)" {
  load_doctor "$REPO"
  local fn
  for fn in "${DB_LAYER_FUNCTIONS[@]}"; do
    declare -F "$fn" >/dev/null || {
      echo "${fn}() not defined after sourcing doctor.sh with INSTALL_DIR=$REPO"
      return 1
    }
  done
}

@test "non-vacuous: without the module on disk, sourcing doctor.sh defines NO db_exec_root (the definition provably comes from \${INSTALL_DIR}/modules/db/core.sh)" {
  # Minimal sandbox: doctor.sh present, modules/ absent — the pre-P0-N
  # sourceability contract, and the proof the best-effort source is what
  # provides the function (a typo'd module path would also land here and
  # fail the defined-arm above).
  local sandbox="$BATS_TEST_TMPDIR/minimal"
  mkdir -p "$sandbox/cli/commands"
  cp "$REPO/cli/commands/doctor.sh" "$sandbox/cli/commands/doctor.sh"

  load_doctor "$sandbox"          # must still succeed (sourceable, run_doctor defined)
  run declare -F db_exec_root
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Oracle: the resolved function issues the canonical container command
# (the P0-M mock-docker pin, mirrored from tests/db/db_contract_test.bats).
# ---------------------------------------------------------------------------

@test "oracle: the resolved db_exec_root issues the canonical command under the P0-M mock docker" {
  # shellcheck source=/dev/null
  source "$REPO/tests/db/mock_docker.bash"
  install_mock_docker "$BATS_TEST_TMPDIR/mock"

  load_doctor "$REPO"
  db_exec_root -e "SELECT 1;" </dev/null

  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 1 ]
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  [ "${MOCK_ARGV[0]}" = "exec" ]
  [ "${MOCK_ARGV[1]}" = "-i" ]
  [ "${MOCK_ARGV[2]}" = "actools_db" ]
  [ "${MOCK_ARGV[3]}" = "sh" ]
  [ "${MOCK_ARGV[4]}" = "-c" ]
  [ "${MOCK_ARGV[5]}" = 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' ]
  [ "${MOCK_ARGV[6]}" = "_" ]
  [ "${MOCK_ARGV[7]}" = "-e" ]
  [ "${MOCK_ARGV[8]}" = "SELECT 1;" ]
  [ "${#MOCK_ARGV[@]}" -eq 9 ]
}
