#!/usr/bin/env bats
# =============================================================================
# tests/guards/wait_db_security_guard_test.bats — P0-M guard
# (wait_db readiness probe: defaults-extra-file YES, argv password NEVER)
#
# Locks the SECURE shape of the wait_db() readiness probe. Before the P0-M
# hardening, the probe (v9.2-fix4) ran
#   docker compose exec -T db mariadb -uroot -p"${_wp}" -e "<write-check>"
# — the DB ROOT password on argv inside the container, visible to every local
# user via ps (the Entry-017 known risk, wait_db:510). The hardened live form
# (modules/db/core.sh) writes [client]/user/password into a umask-077 temp
# file INSIDE the container — fed over stdin by the printf BUILTIN, so no
# host process carries it on argv either — and runs
# `mariadb --defaults-extra-file="$t"`, mirroring the backup-cron pattern.
# This guard exists so the argv form can never come back:
#
#   arm 1: the live wait_db SOURCE MUST carry the secure shape
#          (`--defaults-extra-file=` + `umask 077`)
#   arm 2: the live wait_db SOURCE MUST NOT carry any argv-password form
#          (no `-p"…"` / `-p'…'` / `-p$…` / `--password=`)
#   arm 3 (non-vacuity, permanent): a doctored copy of the live wait_db that
#          re-introduces the retired argv-password probe MUST FAIL the same
#          shape oracle — the guard demonstrably bites on the exact form
#          being purged (the arm self-checks that the doctoring took)
#   arm 4 (behavioral): the live wait_db, run against the P0-M mock docker,
#          puts the root password on NO host argv — it travels only on the
#          container client's stdin (the defaults file) — and still issues
#          the unchanged write-check probe
#
# The function text is located with the P0-M loader machinery (the live
# module post-extraction; the inline block if wait_db ever moved back), so
# the guard always checks the bytes the installer would run.
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$REPO/tests/core/extract_inline.bash"

  # Locate the live wait_db the same way the P0-M contract loader does.
  if [[ -f "$REPO/modules/db/core.sh" ]] \
     && grep -qE '^wait_db\(\)' "$REPO/modules/db/core.sh"; then
    WAIT_DB_HOME="$REPO/modules/db/core.sh"
  else
    WAIT_DB_HOME="$REPO/actools.sh"
  fi
  WAIT_DB_TEXT="$BATS_TEST_TMPDIR/wait_db.live"
  extract_inline_fn wait_db "$WAIT_DB_HOME" > "$WAIT_DB_TEXT"
}

# ---------------------------------------------------------------------------
# _assert_wait_db_secure_shape <file-with-wait_db-text>
# The single shape oracle every arm uses (including the non-vacuity arm,
# which expects it to FAIL on the doctored text). Echoes the violation.
# The oracle checks EXECUTABLE text only (comment lines are stripped first):
# the in-function hardening comment legitimately DESCRIBES the retired argv
# form; the security property is that no executable line carries it.
# ---------------------------------------------------------------------------
_assert_wait_db_secure_shape() {
  local f="$1"
  [[ -s "$f" ]] || { echo "shape check: wait_db text missing/empty: $f"; return 1; }
  local code="${f}.code"
  grep -vE '^[[:space:]]*#' "$f" > "$code" || true
  [[ -s "$code" ]] || { echo "shape check: no executable text in: $f"; return 1; }

  # MUST: the secure defaults-extra-file probe with the umask-077 temp file.
  grep -qF -- '--defaults-extra-file=' "$code" || {
    echo "INSECURE SHAPE: '--defaults-extra-file=' missing from wait_db."
    echo "The secure form (umask-077 temp defaults file inside the container,"
    echo "fed over stdin by the printf builtin) is authoritative — see the"
    echo "backup-cron pattern (modules/backup/cron.sh)."
    return 1
  }
  grep -qF 'umask 077' "$code" || {
    echo "INSECURE SHAPE: 'umask 077' missing from wait_db — the in-container"
    echo "defaults file would be readable by other container users."
    return 1
  }

  # MUST NOT: any argv-password form. Catches the retired -p"${_wp}" probe
  # plus the -p'…' / -p$VAR / --password= variants.
  if grep -nE '(^|[[:space:]])-p["'\''$]|--password=' "$code"; then
    echo "INSECURE SHAPE: argv-password form found in wait_db (lines above)."
    echo "A password on argv is visible to every local user via ps. The"
    echo "pre-P0-M probe (actools.sh:510, v9.2-fix4) used exactly this form;"
    echo "it must never return."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Arms 1 + 2: the live wait_db source is secure
# ---------------------------------------------------------------------------

@test "wait_db source uses the umask-077 --defaults-extra-file probe (secure shape)" {
  # Executable text only — a comment must not vacuously satisfy the MUSTs.
  grep -vE '^[[:space:]]*#' "$WAIT_DB_TEXT" > "$BATS_TEST_TMPDIR/wait_db.code"
  grep -qF -- '--defaults-extra-file=' "$BATS_TEST_TMPDIR/wait_db.code"
  grep -qF 'umask 077' "$BATS_TEST_TMPDIR/wait_db.code"
}

@test "wait_db source passes no DB password on argv (full shape check)" {
  _assert_wait_db_secure_shape "$WAIT_DB_TEXT"
}

# ---------------------------------------------------------------------------
# Arm 3: non-vacuity — the guard BITES on the retired argv-password probe.
# A copy of the LIVE wait_db is doctored back to the pre-P0-M invocation
# (mariadb -uroot -p"${_wp}") and the same oracle must fail it.
# ---------------------------------------------------------------------------

@test "non-vacuous: an argv-password wait_db FAILS the shape check" {
  local doctored="$BATS_TEST_TMPDIR/wait_db.doctored"
  awk '
    /^  until printf / {
      indrop = 1
      print "  until docker compose exec -T db mariadb -uroot -p\"${_wp}\" \\"
      print "    -e \"CREATE TABLE IF NOT EXISTS mysql.actools_write_check (id INT); DROP TABLE IF EXISTS mysql.actools_write_check;\" \\"
      print "    &>/dev/null 2>&1; do"
    }
    indrop && /&>\/dev\/null 2>&1; do$/ { indrop = 0; next }
    indrop { next }
    { print }
  ' "$WAIT_DB_TEXT" > "$doctored"

  # Self-check: the doctoring took — the argv probe is present, the secure
  # pipeline is gone, and the result is still valid bash.
  grep -qF -- '-p"${_wp}"' "$doctored"
  ! grep -qF -- '--defaults-extra-file=' "$doctored"
  bash -n "$doctored"

  # The same oracle must FAIL the doctored text.
  run _assert_wait_db_secure_shape "$doctored"
  [ "$status" -ne 0 ]
  [[ "$output" == *"INSECURE SHAPE"* ]]
}

# ---------------------------------------------------------------------------
# Arm 4: behavioral — run the live wait_db against the mock docker; the
# password is on NO host argv and travels only on the client's stdin.
# ---------------------------------------------------------------------------

@test "behavioral: live wait_db keeps the root password off every argv (stdin-only) and still issues the write-check" {
  # shellcheck source=/dev/null
  source "$REPO/tests/db/db_layer_loader.bash"
  # shellcheck source=/dev/null
  source "$REPO/tests/db/mock_docker.bash"
  load_db_layer "$REPO"
  install_mock_docker "$BATS_TEST_TMPDIR/mock"

  log()   { :; }
  error() { echo "ERROR: $*" >&2; exit 1; }
  sleep() { :; }
  INSTALL_DIR="$BATS_TEST_TMPDIR/install"; mkdir -p "$INSTALL_DIR"
  DB_ROOT_PASS="GUARD_ROOT_SENTINEL"

  wait_db </dev/null
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 1 ]
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  local a
  for a in "${MOCK_ARGV[@]}"; do
    [[ "$a" != *GUARD_ROOT_SENTINEL* ]]
    [[ "$a" != --password=* ]]
  done
  grep -qF 'password=GUARD_ROOT_SENTINEL' "$MOCK_DOCKER_DIR/stdin.1"
  grep -qF 'CREATE TABLE IF NOT EXISTS mysql.actools_write_check' <(printf '%s' "${MOCK_ARGV[*]}")
}
