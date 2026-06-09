#!/usr/bin/env bats
# =============================================================================
# tests/installer/cli_authority_test.bats
# P0-F — CLI Authority Consolidation tests
#
# Guarantees the post-P0-F invariant: there is ONE canonical CLI source
# (cli/actools), the installer installs it by copying that file VERBATIM, the
# duplicate generator heredoc is gone, secrets are handled safely, and the
# command behaviors the matrix said to preserve are still present.
#
# These tests run rootless and execute no docker/systemctl/privileged command.
#
# Run:
#   bats tests/installer/cli_authority_test.bats
# =============================================================================

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CLI="${REPO_DIR}/cli/actools"
    ACTOOLS_SH="${REPO_DIR}/actools.sh"
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_TMP:-}"
}

# Extract setup_cli() verbatim from the live actools.sh (header line through its
# first closing brace at column 0). No hardcoded line numbers, so this keeps
# working if the function moves.
_extract_setup_cli() {
    awk '/^setup_cli\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$ACTOOLS_SH"
}

# ---------------------------------------------------------------------------
# (a) Canonical CLI is syntactically valid bash
# ---------------------------------------------------------------------------
@test "cli/actools parses (bash -n)" {
    bash -n "$CLI"
}

# ---------------------------------------------------------------------------
# (b) The installer installs the CLI by copying cli/actools VERBATIM.
#     We run setup_cli() rootless with its two root-only host write targets
#     (/usr/local/bin/actools and /etc/environment) redirected to temp paths,
#     then assert the installed file is byte-for-byte identical to cli/actools.
#     This is the core "single source of truth" guarantee.
# ---------------------------------------------------------------------------
@test "installed CLI is a byte-for-byte copy of canonical cli/actools" {
    local cli_out="${TEST_TMP}/actools-installed"
    local env_out="${TEST_TMP}/etc-environment.throwaway"

    (
        export INSTALL_DIR="$REPO_DIR"
        log() { :; }
        eval "$(_extract_setup_cli \
                | sed -e "s#/usr/local/bin/actools#${cli_out}#g" \
                      -e "s#/etc/environment#${env_out}#g")"
        setup_cli
    )

    [[ -f "$cli_out" ]] || { echo "setup_cli() did not install the CLI to ${cli_out}"; return 1; }

    # diff is empty (exit 0) only if the installed file equals the canonical one.
    run diff "$CLI" "$cli_out"
    [ "$status" -eq 0 ] || { echo "Installed CLI differs from cli/actools:"; echo "$output"; return 1; }
}

# ---------------------------------------------------------------------------
# (b2) setup_cli() also persists ACTOOLS_HOME (so the copied CLI can resolve
#      INSTALL_DIR at runtime instead of self-locating to /usr/local).
# ---------------------------------------------------------------------------
@test "setup_cli persists ACTOOLS_HOME for the installed CLI" {
    local cli_out="${TEST_TMP}/actools-installed"
    local env_out="${TEST_TMP}/etc-environment.throwaway"

    (
        export INSTALL_DIR="$REPO_DIR"
        log() { :; }
        eval "$(_extract_setup_cli \
                | sed -e "s#/usr/local/bin/actools#${cli_out}#g" \
                      -e "s#/etc/environment#${env_out}#g")"
        setup_cli
    )

    grep -q "ACTOOLS_HOME=${REPO_DIR}" "$env_out"
}

# ---------------------------------------------------------------------------
# (c) The duplicate CLI generator is gone: setup_cli() must NOT contain a
#     heredoc that re-emits a CLI, and the only command path is the copy.
# ---------------------------------------------------------------------------
@test "setup_cli installs by copy, with no CLI-emitting heredoc" {
    local body
    body="$(_extract_setup_cli)"

    # No heredoc that writes the CLI file.
    echo "$body" | grep -q 'cat > /usr/local/bin/actools' && {
        echo "setup_cli still contains a 'cat > /usr/local/bin/actools' heredoc generator"
        return 1
    }
    echo "$body" | grep -qE '<<\s*HELPER' && {
        echo "setup_cli still contains a HELPER heredoc"
        return 1
    }

    # The install-by-copy command is present.
    echo "$body" | grep -qE 'install .*"\$\{INSTALL_DIR\}/cli/actools" .*/usr/local/bin/actools'
}

# ---------------------------------------------------------------------------
# (d) Secret safety — static analysis of the canonical CLI.
#     DB credentials must never appear in any process argument list.
# ---------------------------------------------------------------------------
@test "cli/actools never passes a DB password on the command line" {
    # -p"<var>" / -p<var> / --password=<var> are all forbidden (visible in argv/ps).
    run grep -nE '(-p"?\$|--password=)' "$CLI"
    [ "$status" -ne 0 ] || { echo "Found password-in-argv pattern(s):"; echo "$output"; return 1; }
}

@test "cli/actools uses safe secret mechanisms (defaults-file + MYSQL_PWD)" {
    # Snapshot path: temp defaults file (password fed via stdin into the container).
    grep -q 'defaults-extra-file' "$CLI"
    # Root DB ops: password supplied via the db container's own env var, never argv.
    grep -q 'MYSQL_PWD="\$MARIADB_ROOT_PASSWORD"' "$CLI"
}

@test "cli/actools snapshot writes its defaults file with a tight umask" {
    # The temp mariadb-dump credentials file must be created with umask 077.
    grep -Eq 'umask 077;.*mktemp.*\.cnf' "$CLI"
}

# ---------------------------------------------------------------------------
# (e) Preserved behaviors (parity matrix) — present in the canonical CLI.
# ---------------------------------------------------------------------------
@test "backup command still delegates to the daily cron script" {
    grep -Eq '^\s*backup\)\s*/etc/cron\.daily/actools-backup' "$CLI"
}

@test "restore keeps its confirmation prompt and checksum verification" {
    grep -q 'OVERWRITE actools_' "$CLI"          # interactive confirm retained
    grep -q 'sha256sum -c "\$BACKUP_FILE.sha256"' "$CLI"
}

@test "restore-test keeps checksum gate and writes the .restore-test-last marker" {
    grep -q 'sha256sum -c "\$LATEST.sha256"' "$CLI"
    # Marker consumed by cli/commands/doctor.sh — must not regress.
    grep -q 'backups/.restore-test-last' "$CLI"
}

@test "doctor.sh still consumes the .restore-test-last marker (consumer intact)" {
    grep -q 'restore-test-last' "${REPO_DIR}/cli/commands/doctor.sh"
}

# ---------------------------------------------------------------------------
# (f) Help smoke — the canonical CLI's help runs and lists ported commands.
#     ACTOOLS_HOME is pinned to the repo so INSTALL_DIR resolution is
#     deterministic and independent of any installed host state.
# ---------------------------------------------------------------------------
@test "help (basic) runs and lists common commands" {
    run env ACTOOLS_HOME="$REPO_DIR" bash "$CLI" help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Actools Drupal Community"
    echo "$output" | grep -q "doctor"
}

@test "help advanced runs and includes the ported 'audit' command" {
    run env ACTOOLS_HOME="$REPO_DIR" bash "$CLI" help advanced
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "audit"
    echo "$output" | grep -q "tunnel"
}

@test "audit command is wired to the audit module" {
    grep -Eq '^\s*audit\)' "$CLI"
    grep -q 'modules/audit/audit.sh' "$CLI"
}
