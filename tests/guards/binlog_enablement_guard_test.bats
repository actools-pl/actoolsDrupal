#!/usr/bin/env bats
# =============================================================================
# tests/guards/binlog_enablement_guard_test.bats — E3a guard
# (binlog enablement: the gated PITR-foundation wiring in compose.sh)
#
# Pins the binary-logging FOUNDATION that E3a folds into the canonical db service,
# gated by the new ENABLE_PITR flag (default off). With ENABLE_PITR=true the
# generated docker-compose.yml must (i) mount the standalone 99-binlog.cnf into the
# db service at /etc/mysql/mariadb.conf.d/99-binlog.cnf, (ii) mount the dedicated
# mariadb_binlogs named volume at /var/log/mysql (so binlogs survive container
# recreation), and (iii) declare mariadb_binlogs in the top-level volumes: section.
# With ENABLE_PITR off (false OR unset) NONE of the three may appear — the default
# compose output stays byte-identical to today's (pinned separately by golden_drift).
#
# This guard reads the bytes the installer would write by sourcing the SAME
# canonical modules/stack/compose.sh generator the golden-capture harness uses and
# calling generate_compose() directly against a deterministic environment.
#
# Discipline mirrors tests/guards/backup_format_contract_guard_test.bats:
#   - the wiring is DERIVED by rendering the real generator, not transcribed;
#   - the off-rendering (ENABLE_PITR off) assertion is NON-VACUOUS: arm 6 doctors
#     an OFF-TREE copy of compose.sh so the binlog block renders UNCONDITIONALLY and
#     proves that the off assertion then bites (the wiring leaks into the PITR=off
#     render) — i.e. an ungated block cannot pass arms 4/5;
#   - non-vacuity runs on an OFF-TREE scratch copy — the repo is never modified.
#
# dash/bats-safe: no process substitution; the generator renders into a mktemp dir;
# all scratch copies live under a mktemp dir torn down in teardown().
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  COMPOSE_SH="${REPO}/modules/stack/compose.sh"
  BINLOG_CNF="${REPO}/modules/backup/99-binlog.cnf"
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "${WORK:-}"
}

# ---------------------------------------------------------------------------
# _render_compose <compose.sh path> <out file> <pitr>
# Source the given compose generator and render docker-compose.yml into a fresh
# temp INSTALL_DIR against a fixed, deterministic environment, then copy the
# result to <out file>. <pitr> is "true"/"false" (exported as ENABLE_PITR) or the
# literal "UNSET" (ENABLE_PITR left unexported, so the generator's :-false default
# governs). Echoes nothing; rc!=0 on render failure.
# ---------------------------------------------------------------------------
_render_compose() {
  local gen="$1" out="$2" pitr="$3"
  local dir
  dir="$(mktemp -d "${WORK}/render.XXXXXX")" || return 1
  (
    set -e
    export INSTALL_DIR="$dir"
    export MARIADB_VERSION="11.4"
    export DB_ROOT_PASS="TEST_DB_ROOT_PASS_FIXED"
    export PHP_MEMORY_LIMIT="512m"
    export WORKER_MEMORY_LIMIT="2g"
    export DB_MEMORY_LIMIT="2g"
    export REDIS_MEMORY_LIMIT="256m"
    export ENABLE_REDIS="true"
    export ENABLE_S3_STORAGE="false"
    export ENABLE_CADVISOR="false"
    export ENVIRONMENT_MODE="production-isolated"
    if [ "$pitr" != "UNSET" ]; then
      export ENABLE_PITR="$pitr"
    fi
    # shellcheck source=/dev/null
    . "$gen"
    generate_compose
  ) || return 1
  [ -f "${dir}/docker-compose.yml" ] || return 1
  cp "${dir}/docker-compose.yml" "$out"
}

# _top_level_volumes_block <compose file>  — print the top-level volumes: block
# (from the `volumes:` line at column 0 up to the `services:` line).
_top_level_volumes_block() {
  awk '/^volumes:/{f=1} f{print} f&&/^services:/{exit}' "$1"
}

# _db_volumes_block <compose file> — print the db service volumes: list (from the
# db service's `    volumes:` line down to its next sibling key).
_db_volumes_block() {
  awk '/^  db:/{d=1} d&&/^    volumes:/{v=1; print; next} v&&/^    [a-z]/{exit} v{print}' "$1"
}

# ---------------------------------------------------------------------------
# Arm 1 — PITR on: the db service mounts the standalone 99-binlog.cnf config.
# ---------------------------------------------------------------------------
@test "PITR on: db service mounts 99-binlog.cnf at /etc/mysql/mariadb.conf.d/99-binlog.cnf" {
  run _render_compose "$COMPOSE_SH" "${WORK}/on.yml" true
  [ "$status" -eq 0 ] || { echo "render failed: $output"; return 1; }

  _db_volumes_block "${WORK}/on.yml" | grep -qF './99-binlog.cnf:/etc/mysql/mariadb.conf.d/99-binlog.cnf:ro' || {
    echo "PITR on: db service does not mount 99-binlog.cnf into mariadb.conf.d."
    echo "--- db volumes ---"; _db_volumes_block "${WORK}/on.yml"; return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 2 — PITR on: the db service mounts the dedicated mariadb_binlogs volume.
# ---------------------------------------------------------------------------
@test "PITR on: db service mounts mariadb_binlogs:/var/log/mysql" {
  run _render_compose "$COMPOSE_SH" "${WORK}/on.yml" true
  [ "$status" -eq 0 ] || { echo "render failed: $output"; return 1; }

  _db_volumes_block "${WORK}/on.yml" | grep -qF 'mariadb_binlogs:/var/log/mysql' || {
    echo "PITR on: db service does not mount mariadb_binlogs at /var/log/mysql."
    echo "--- db volumes ---"; _db_volumes_block "${WORK}/on.yml"; return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 3 — PITR on: the top-level volumes: section declares mariadb_binlogs.
# ---------------------------------------------------------------------------
@test "PITR on: top-level volumes declares mariadb_binlogs" {
  run _render_compose "$COMPOSE_SH" "${WORK}/on.yml" true
  [ "$status" -eq 0 ] || { echo "render failed: $output"; return 1; }

  _top_level_volumes_block "${WORK}/on.yml" | grep -qE '^[[:space:]]+mariadb_binlogs:' || {
    echo "PITR on: top-level volumes: does not declare the mariadb_binlogs named volume."
    echo "--- top-level volumes ---"; _top_level_volumes_block "${WORK}/on.yml"; return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 4 — PITR off (ENABLE_PITR=false): NONE of the binlog wiring renders.
# (The off-rendering must be clean — byte-identity is pinned by golden_drift.)
# ---------------------------------------------------------------------------
@test "PITR off (false): none of the binlog wiring renders" {
  run _render_compose "$COMPOSE_SH" "${WORK}/off.yml" false
  [ "$status" -eq 0 ] || { echo "render failed: $output"; return 1; }

  if grep -qE 'mariadb_binlogs|99-binlog\.cnf' "${WORK}/off.yml"; then
    echo "PITR off: binlog wiring leaked into the OFF render."
    grep -nE 'mariadb_binlogs|99-binlog\.cnf' "${WORK}/off.yml"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Arm 5 — PITR unset (ENABLE_PITR not set): NONE of the binlog wiring renders.
# ---------------------------------------------------------------------------
@test "PITR unset: none of the binlog wiring renders" {
  run _render_compose "$COMPOSE_SH" "${WORK}/unset.yml" UNSET
  [ "$status" -eq 0 ] || { echo "render failed: $output"; return 1; }

  if grep -qE 'mariadb_binlogs|99-binlog\.cnf' "${WORK}/unset.yml"; then
    echo "PITR unset: binlog wiring leaked into the default render."
    grep -nE 'mariadb_binlogs|99-binlog\.cnf' "${WORK}/unset.yml"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Arm 6 — Non-vacuity: an UNGATED binlog block is caught by the PITR=off arm.
# Doctor an OFF-TREE copy of compose.sh so the gate is always-true (the block
# renders unconditionally), render it with ENABLE_PITR=false, and assert the
# binlog wiring now LEAKS into the off render — i.e. arms 4/5 are non-vacuous
# (an unconditional block cannot pass them). The repo is never touched.
# ---------------------------------------------------------------------------
@test "non-vacuous: an unconditionally-rendered binlog block leaks into the PITR=off render" {
  local doctored="${WORK}/compose-ungated.sh"
  cp "$COMPOSE_SH" "$doctored"
  # Make every `"${PITR_ON}" == "true"` gate always-true by neutralizing PITR_ON.
  sed -i 's/\${PITR_ON}/true/g' "$doctored"

  # Sanity (else this arm is vacuous): the doctor must have removed the gate token.
  if grep -qF '${PITR_ON}' "$doctored"; then
    echo "VACUOUS: the gate doctor did not neutralize \${PITR_ON}."
    return 1
  fi

  run _render_compose "$doctored" "${WORK}/ungated-off.yml" false
  [ "$status" -eq 0 ] || { echo "doctored render failed: $output"; return 1; }

  # The ungated block must now leak the binlog wiring even with ENABLE_PITR=false,
  # proving the PITR=off arms would FAIL against an unconditional block.
  grep -qF 'mariadb_binlogs:/var/log/mysql' "${WORK}/ungated-off.yml" || {
    echo "VACUOUS GUARD: an ungated compose still produced a clean off render."
    return 1
  }
  grep -qF './99-binlog.cnf:/etc/mysql/mariadb.conf.d/99-binlog.cnf:ro' "${WORK}/ungated-off.yml" || {
    echo "VACUOUS GUARD: an ungated compose did not emit the 99-binlog.cnf mount."
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 7 — Config shape: 99-binlog.cnf carries the PITR-required settings, so a
# future weakening of the binlog config trips this guard.
# ---------------------------------------------------------------------------
@test "config shape: 99-binlog.cnf carries log_bin, binlog_format=ROW, server_id, sync_binlog=1" {
  [ -f "$BINLOG_CNF" ] || { echo "99-binlog.cnf missing at $BINLOG_CNF"; return 1; }

  grep -qE '^log_bin[[:space:]]*=' "$BINLOG_CNF" || {
    echo "config: 99-binlog.cnf does not set log_bin."; return 1; }
  grep -qE '^binlog_format[[:space:]]*=[[:space:]]*ROW' "$BINLOG_CNF" || {
    echo "config: 99-binlog.cnf does not set binlog_format = ROW."; return 1; }
  grep -qE '^server_id[[:space:]]*=' "$BINLOG_CNF" || {
    echo "config: 99-binlog.cnf does not set server_id."; return 1; }
  grep -qE '^sync_binlog[[:space:]]*=[[:space:]]*1' "$BINLOG_CNF" || {
    echo "config: 99-binlog.cnf does not set sync_binlog = 1."; return 1; }
}
