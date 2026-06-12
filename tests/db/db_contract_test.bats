#!/usr/bin/env bats
# =============================================================================
# tests/db/db_contract_test.bats — P0-M contract/mock tests for the live
# DB layer (db_exec_root / db_exec_root_stdin / db_dump_container /
# setup_backup_db_user / wait_db / check_db_creds).
#
# The layer is STATEFUL (it execs against a live MariaDB container), so there
# is no output to golden-capture. Behavior is pinned instead by interposing a
# mock `docker` on PATH (tests/db/mock_docker.bash) and asserting the exact
# COMMANDS and SQL each function issues:
#
#   db_exec_root         -> docker exec -i actools_db sh -c '<MYSQL_PWD body>'
#                           — root client inside the container, password from
#                           container env, NEVER on the host argv
#   db_exec_root_stdin   -> same shape, "$1" = target database, SQL on stdin
#   db_dump_container    -> the backup-user dump via a umask-077
#                           --defaults-extra-file temp file inside the
#                           container; password travels on stdin, not argv
#   setup_backup_db_user -> wait_db first, then the exact backup-user
#                           CREATE USER / GRANT / FLUSH PRIVILEGES SQL
#   wait_db              -> polls the mysql.actools_write_check readiness
#                           probe until the DB answers; bounded at 50 tries
#                           (error() after 150s-equivalent)
#   check_db_creds       -> the SELECT 1 credential probe through db_exec_root
#
# The loader (tests/db/db_layer_loader.bash) auto-locates the live layer —
# inline in actools.sh before the P0-M extraction, modules/db/core.sh after —
# so the SAME assertions running green across the move is the faithfulness
# proof (the P0-L capture_backup_cron.sh pattern).
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

load db_layer_loader
load mock_docker

# The readiness probe SQL wait_db issues (the v9.2-fix4 write-check — pinned
# verbatim; "poll until the DB answers" is THIS statement, not a SELECT).
WRITE_CHECK_SQL='CREATE TABLE IF NOT EXISTS mysql.actools_write_check (id INT); DROP TABLE IF EXISTS mysql.actools_write_check;'

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  load_db_layer "$REPO"

  install_mock_docker "$BATS_TEST_TMPDIR/mock"

  # Collaborator stubs (core/bootstrap.sh shapes), defined AFTER loading so
  # they win. error() must terminate like the live one — wait_db's give-up
  # bound and check_db_creds' failure path rely on it.
  LOGFILE="$BATS_TEST_TMPDIR/log"; : > "$LOGFILE"
  log()     { echo "LOG: $*"     >> "$LOGFILE"; }
  warn()    { echo "WARN: $*"    >> "$LOGFILE"; }
  section() { echo "SECTION: $*" >> "$LOGFILE"; }
  error()   { echo "ERROR: $*"   >> "$LOGFILE"; echo "ERROR: $*" >&2; exit 1; }

  # sleep is stubbed so wait_db's 50-try bound runs instantly; attempts are
  # counted by the docker stub, naps recorded here.
  SLEEPFILE="$BATS_TEST_TMPDIR/sleeps"; : > "$SLEEPFILE"
  sleep() { echo "sleep $*" >> "$SLEEPFILE"; }

  # Globals the layer reads.
  INSTALL_DIR="$BATS_TEST_TMPDIR/install"; mkdir -p "$INSTALL_DIR"
  DB_ROOT_PASS="TEST_ROOT_PASS_SENTINEL"
}

# ---------------------------------------------------------------------------
# Loader sanity
# ---------------------------------------------------------------------------

@test "loader: the six DB functions load from exactly one live origin" {
  [ -n "$DB_LAYER_ORIGIN" ]
  local fn
  for fn in "${DB_LAYER_FUNCTIONS[@]}"; do
    declare -F "$fn" >/dev/null
  done
  if [[ -f "$REPO/modules/db/core.sh" ]] \
     && grep -qE '^db_exec_root\(\)' "$REPO/modules/db/core.sh"; then
    [ "$DB_LAYER_ORIGIN" = "module" ]
  else
    [ "$DB_LAYER_ORIGIN" = "inline" ]
  fi
}

# ---------------------------------------------------------------------------
# db_exec_root — root client inside the container, password from container env
# ---------------------------------------------------------------------------

@test "db_exec_root: invokes docker exec -i actools_db sh -c mariadb as root with the query" {
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

@test "db_exec_root: no password material on the host argv (container env only)" {
  DB_ROOT_PASS="SUPERSECRET_ROOT"
  db_exec_root -e "SELECT 1;" </dev/null
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  local a
  for a in "${MOCK_ARGV[@]}"; do
    [[ "$a" != *SUPERSECRET_ROOT* ]]
    [[ "$a" != --password=* ]]
  done
}

@test "db_exec_root: stdin (heredoc SQL) reaches the container client" {
  db_exec_root <<SQL
SELECT 42;
SQL
  [ "$(cat "$MOCK_DOCKER_DIR/stdin.1")" = "SELECT 42;" ]
}

# ---------------------------------------------------------------------------
# db_exec_root_stdin — piped SQL against a positional database
# ---------------------------------------------------------------------------

@test "db_exec_root_stdin: pipes stdin into root mariadb against the positional database" {
  printf 'DROP TABLE x;\n' | db_exec_root_stdin actools_prod
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 1 ]
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  [ "${MOCK_ARGV[0]}" = "exec" ]
  [ "${MOCK_ARGV[1]}" = "-i" ]
  [ "${MOCK_ARGV[2]}" = "actools_db" ]
  [ "${MOCK_ARGV[3]}" = "sh" ]
  [ "${MOCK_ARGV[4]}" = "-c" ]
  [ "${MOCK_ARGV[5]}" = 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$1"' ]
  [ "${MOCK_ARGV[6]}" = "_" ]
  [ "${MOCK_ARGV[7]}" = "actools_prod" ]
  [ "${#MOCK_ARGV[@]}" -eq 8 ]
  [ "$(cat "$MOCK_DOCKER_DIR/stdin.1")" = "DROP TABLE x;" ]
}

# ---------------------------------------------------------------------------
# db_dump_container — least-privilege dump, password via stdin defaults file
# ---------------------------------------------------------------------------

@test "db_dump_container: runs the dump via a umask-077 --defaults-extra-file inside the container" {
  db_dump_container "BKP_SENTINEL" --single-transaction --quick actools_prod
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 1 ]
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  [ "${MOCK_ARGV[0]}" = "exec" ]
  [ "${MOCK_ARGV[1]}" = "-i" ]
  [ "${MOCK_ARGV[2]}" = "actools_db" ]
  [ "${MOCK_ARGV[3]}" = "sh" ]
  [ "${MOCK_ARGV[4]}" = "-c" ]
  # The container-side body: umask-077 temp defaults file, cleaned on EXIT,
  # filled from stdin, consumed by mariadb-dump.
  [[ "${MOCK_ARGV[5]}" == *'umask 077'* ]]
  [[ "${MOCK_ARGV[5]}" == *'mktemp /tmp/actools-dump.XXXXXX.cnf'* ]]
  [[ "${MOCK_ARGV[5]}" == *'trap "rm -f \"$tmp\"" EXIT'* ]]
  [[ "${MOCK_ARGV[5]}" == *'cat > "$tmp"'* ]]
  [[ "${MOCK_ARGV[5]}" == *'mariadb-dump --defaults-extra-file="$tmp" "$@"'* ]]
  # Dump args pass through after the placeholder $0.
  [ "${MOCK_ARGV[6]}" = "_" ]
  [ "${MOCK_ARGV[7]}" = "--single-transaction" ]
  [ "${MOCK_ARGV[8]}" = "--quick" ]
  [ "${MOCK_ARGV[9]}" = "actools_prod" ]
  [ "${#MOCK_ARGV[@]}" -eq 10 ]
  # The defaults-file content arrives on stdin.
  diff "$MOCK_DOCKER_DIR/stdin.1" - <<'CNF'
[mariadb-dump]
user=backup
password=BKP_SENTINEL
CNF
}

@test "db_dump_container: backup password travels on stdin, never on argv" {
  db_dump_container "BKP_SENTINEL" actools_prod
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  local a
  for a in "${MOCK_ARGV[@]}"; do
    [[ "$a" != *BKP_SENTINEL* ]]
    [[ "$a" != --password=* ]]
  done
  grep -qF 'password=BKP_SENTINEL' "$MOCK_DOCKER_DIR/stdin.1"
}

# ---------------------------------------------------------------------------
# setup_backup_db_user — exact backup-user SQL, readiness first
# ---------------------------------------------------------------------------

@test "setup_backup_db_user: waits for the DB, then issues the exact backup-user SQL" {
  local order="$BATS_TEST_TMPDIR/order"; : > "$order"
  # Unit isolation: wait_db's polling is pinned by its own contracts below;
  # here only the call ORDER and the SQL fed to db_exec_root are asserted.
  wait_db()      { echo "wait_db" >> "$order"; }
  db_exec_root() { echo "db_exec_root" >> "$order"; cat > "$BATS_TEST_TMPDIR/sql"; }

  setup_backup_db_user "BKP_SENTINEL"

  diff "$order" - <<'ORDER'
wait_db
db_exec_root
ORDER
  # The exact least-privilege grant — SELECT, LOCK TABLES, SHOW VIEW only.
  diff "$BATS_TEST_TMPDIR/sql" - <<'SQL'
CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY 'BKP_SENTINEL';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* TO 'backup'@'%';
FLUSH PRIVILEGES;
SQL
  grep -qF "LOG: DB backup user created." "$LOGFILE"
}

@test "setup_backup_db_user: end-to-end through db_exec_root — SQL on the container client stdin, password never on argv" {
  wait_db() { :; }  # isolate readiness; pinned by the wait_db contracts
  setup_backup_db_user "BKP_SENTINEL"
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 1 ]
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  [ "${MOCK_ARGV[5]}" = 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' ]
  grep -qF "CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY 'BKP_SENTINEL';" "$MOCK_DOCKER_DIR/stdin.1"
  grep -qF "GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* TO 'backup'@'%';" "$MOCK_DOCKER_DIR/stdin.1"
  grep -qF "FLUSH PRIVILEGES;" "$MOCK_DOCKER_DIR/stdin.1"
  local a
  for a in "${MOCK_ARGV[@]}"; do
    [[ "$a" != *BKP_SENTINEL* ]]
  done
}

# ---------------------------------------------------------------------------
# wait_db — the readiness poll: shape, bounds, outcome
# ---------------------------------------------------------------------------
# _assert_wait_db_probe_shape pins the probe's COMMAND SHAPE in ONE place so
# the P0-M hardening commit updates exactly this oracle (argv-password form ->
# secure --defaults-extra-file form) together with the security test, while
# the polling OUTCOME assertions below stay untouched.
# ---------------------------------------------------------------------------

_assert_wait_db_probe_shape() {
  local n="$1"
  mock_docker_argv "$MOCK_DOCKER_DIR" "$n"
  [ "${MOCK_ARGV[0]}" = "compose" ]
  [ "${MOCK_ARGV[1]}" = "exec" ]
  [ "${MOCK_ARGV[2]}" = "-T" ]
  [ "${MOCK_ARGV[3]}" = "db" ]
  [ "${MOCK_ARGV[4]}" = "mariadb" ]
  [ "${MOCK_ARGV[5]}" = "-uroot" ]
  [ "${MOCK_ARGV[6]}" = "-p${DB_ROOT_PASS}" ]
  [ "${MOCK_ARGV[7]}" = "-e" ]
  [ "${MOCK_ARGV[8]}" = "$WRITE_CHECK_SQL" ]
  [ "${#MOCK_ARGV[@]}" -eq 9 ]
}

@test "wait_db: polls the write-check until the DB answers, then returns 0" {
  export MOCK_DOCKER_FAIL_FIRST=3
  wait_db </dev/null
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 4 ]
  local n
  for n in 1 2 3 4; do
    _assert_wait_db_probe_shape "$n"
  done
  # One 3s nap after each of the three failed probes; none after success.
  [ "$(grep -c '^sleep 3$' "$SLEEPFILE")" -eq 3 ]
  grep -qF "LOG: Waiting for MariaDB (write-check)..." "$LOGFILE"
  grep -qF "LOG: MariaDB ready." "$LOGFILE"
}

@test "wait_db: gives up via error() after 50 failed probes (bounded)" {
  export MOCK_DOCKER_RC=1
  run wait_db </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"MariaDB did not become ready within 150s."* ]]
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 50 ]
}

# ---------------------------------------------------------------------------
# check_db_creds — the credential probe
# ---------------------------------------------------------------------------

@test "check_db_creds: probes root auth with SELECT 1 through db_exec_root" {
  check_db_creds </dev/null
  [ "$(mock_docker_calls "$MOCK_DOCKER_DIR")" -eq 1 ]
  mock_docker_argv "$MOCK_DOCKER_DIR" 1
  [ "${MOCK_ARGV[5]}" = 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' ]
  [ "${MOCK_ARGV[7]}" = "-e" ]
  [ "${MOCK_ARGV[8]}" = "SELECT 1;" ]
  grep -qF "LOG: DB credentials verified." "$LOGFILE"
}

@test "check_db_creds: fails via error() when root auth is rejected" {
  export MOCK_DOCKER_RC=1
  run check_db_creds </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot authenticate to MariaDB with current DB_ROOT_PASS."* ]]
}
