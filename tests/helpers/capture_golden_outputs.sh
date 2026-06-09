#!/usr/bin/env bash
# =============================================================================
# tests/helpers/capture_golden_outputs.sh
# P0-C — Golden Behavior Capture helper
#
# Renders every generated STACK file for each environment variant WITHOUT
# executing docker build, apt-get, chown, systemctl, ufw, or any other
# privileged/side-effect command.  The REAL actools.sh heredoc text is never
# copied here; setup_stack() is extracted from the live actools.sh via sed and
# eval'd so fixtures stay byte-for-byte identical to what the generator
# actually produces.
#
# P0-F: the CLI is no longer a generated file. setup_cli() installs the CLI by
# copying the canonical cli/actools verbatim, so there is no CLI fixture to
# capture here. CLI integrity (installed == cli/actools) and secret-safety are
# verified directly by tests/installer/cli_authority_test.bats.
#
# Usage:
#   bash tests/helpers/capture_golden_outputs.sh [all|<variant>] [<dest-dir>]
#
#   all           — capture all 5 variants (default)
#   <variant>     — one of: default  redis-off  s3-on  cadvisor-on  all-in-one
#   <dest-dir>    — destination root (default: tests/fixtures/golden/)
#
# Variant matrix:
#   default      ENABLE_REDIS=true  S3=false  CADVISOR=false  MODE=production-isolated
#   redis-off    ENABLE_REDIS=false S3=false  CADVISOR=false  MODE=production-isolated
#   s3-on        ENABLE_REDIS=true  S3=true   CADVISOR=false  MODE=production-isolated
#   cadvisor-on  ENABLE_REDIS=true  S3=false  CADVISOR=true   MODE=production-isolated
#   all-in-one   ENABLE_REDIS=true  S3=false  CADVISOR=false  MODE=all-in-one
#
# CAPTURE-ONLY: this script makes NO change to actools.sh or any runtime file.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ACTOOLS_SH="${REPO_ROOT}/actools.sh"

[[ -f "$ACTOOLS_SH" ]] || { echo "[P0-C] ERROR: actools.sh not found at $ACTOOLS_SH" >&2; exit 1; }

ARG_VARIANT="${1:-all}"
ARG_DEST="${2:-${REPO_ROOT}/tests/fixtures/golden}"

# ── Fixed deterministic constants ─────────────────────────────────────────────
readonly FIXED_DOMAIN="golden.example.com"
readonly FIXED_EMAIL="golden@example.com"
readonly FIXED_DB_ROOT_PASS="TEST_DB_ROOT_PASS_FIXED"
readonly FIXED_DRUPAL_ADMIN_PASS="TEST_DRUPAL_ADMIN_PASS_FIXED"
readonly FIXED_BACKUP_PASS="TEST_BACKUP_PASS_FIXED"

# ── Line ranges in actools.sh (verified against current source) ──────────────
# setup_stack starts at line 431, closes at line 877
# setup_cli   starts at line 1096, closes at line 1111
#
# P0-G: the host block was extracted to modules/host/* and the stack generators
# are being extracted to modules/stack/* one file at a time. setup_stack is now
# a (shrinking) orchestrator that DELEGATES each extracted file to a module
# function, so this harness sources those modules (see PHASE 1 below) and still
# sed-extracts + eval's setup_stack for the not-yet-extracted inline generators.
# SS_*/SC_* are re-pinned after each extraction; when the last generator moves
# out, the harness switches to calling the module generators directly and drops
# the SS_* eval range — see docs/releases/P0-G-extract-host-stack.md.
#
# P0-F: setup_cli() no longer renders a CLI — it installs the CLI by copying
# the canonical cli/actools verbatim. The SC_START..SC_END range below is kept
# ONLY so _assert_fn_range() still pins setup_cli()'s location and fails loudly
# if a future edit moves it (drift guard). The range is no longer sed-extracted
# to generate a CLI fixture; the CLI is validated directly by
# tests/installer/cli_authority_test.bats (installed == cli/actools).
readonly SS_START=431  SS_END=877
readonly SC_START=1096 SC_END=1111

# ── Variant specs: name|REDIS|S3|CADVISOR|ENV_MODE ───────────────────────────
declare -a ALL_VARIANT_SPECS=(
  "default|true|false|false|production-isolated"
  "redis-off|false|false|false|production-isolated"
  "s3-on|true|true|false|production-isolated"
  "cadvisor-on|true|false|true|production-isolated"
  "all-in-one|true|false|false|all-in-one"
)

# ── Utilities ─────────────────────────────────────────────────────────────────
_log() { echo "[P0-C] $*"; }
_err() { echo "[P0-C] ERROR: $*" >&2; exit 1; }

# Validate that function fn_name starts at start_line and closes at end_line.
# Prevents silent wrong-capture if actools.sh line numbers drift after a commit.
_assert_fn_range() {
  local fn_name="$1" start="$2" end="$3"
  local actual_start
  actual_start=$(grep -n "^${fn_name}()" "$ACTOOLS_SH" | head -1 | cut -d: -f1)
  if [[ "$actual_start" != "$start" ]]; then
    _err "${fn_name}() found at line ${actual_start:-NOT_FOUND}, expected ${start}." \
         "Update ${fn_name^^}_START in this script to match, then re-run."
  fi
  local closing
  closing=$(sed -n "${end}p" "$ACTOOLS_SH")
  if [[ "$closing" != "}" ]]; then
    _err "${fn_name}() closing brace expected at line ${end}, got: '${closing}'." \
         "Update ${fn_name^^}_END in this script, then re-run."
  fi
  _log "  ${fn_name}(): lines ${start}-${end} verified ✓"
}

# =============================================================================
# capture_variant  <spec>  <dest_root>
# =============================================================================
capture_variant() {
  local spec="$1"
  local dest_root="$2"

  # Parse the pipe-delimited spec
  local VNAME REDIS S3 CADVISOR ENV_MODE
  IFS='|' read -r VNAME REDIS S3 CADVISOR ENV_MODE <<<"$spec"

  local ENVIRONMENTS
  [[ "$ENV_MODE" == "all-in-one" ]] && ENVIRONMENTS="dev,stg,prod" || ENVIRONMENTS="prod"

  # S3 credentials: non-empty fixed values when S3 is on
  local AWS_KEY="" AWS_SECRET="" S3_BUCKET_VAL=""
  if [[ "$S3" == "true" ]]; then
    AWS_KEY="TEST_AWS_ACCESS_KEY_FIXED"
    AWS_SECRET="TEST_AWS_SECRET_KEY_FIXED"
    S3_BUCKET_VAL="test-golden-bucket"
  fi

  local fixture_dir="${dest_root}/${VNAME}"
  mkdir -p "$fixture_dir"

  _log "Capturing variant: ${VNAME}"

  # Temp dir for setup_stack file output
  local tmp_install
  tmp_install=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp_install}'" RETURN

  # Fixed state file (provides stable backup_user_pass — no jq writes needed)
  local state_file="${tmp_install}/.actools-state.json"
  printf '{"envs":{},"db_passes":{"prod":"%s"},"backup_user_pass":"%s"}\n' \
    "$FIXED_DB_ROOT_PASS" "$FIXED_BACKUP_PASS" > "$state_file"

  # ===========================================================================
  # PHASE 1 — generate stack files via setup_stack()
  # Runs in a subshell so exported env + bash function shims are fully isolated.
  # ===========================================================================
  (
    # Full deterministic environment
    export INSTALL_DIR="$tmp_install"
    export STATE_FILE="$state_file"
    export BASE_DOMAIN="$FIXED_DOMAIN"
    export DRUPAL_ADMIN_EMAIL="$FIXED_EMAIL"
    export DB_ROOT_PASS="$FIXED_DB_ROOT_PASS"
    export DRUPAL_ADMIN_PASS="$FIXED_DRUPAL_ADMIN_PASS"
    export REAL_USER="root"

    # Versions + resource limits (defaults from actools.env.example)
    export DRUPAL_VERSION="11"
    export PHP_VERSION="8.3"
    export MARIADB_VERSION="11.4"
    export PHP_MEMORY_LIMIT="512m"
    export WORKER_MEMORY_LIMIT="2g"
    export DB_MEMORY_LIMIT="2g"
    export REDIS_MEMORY_LIMIT="256m"
    export INNODB_BUFFER_POOL="1G"
    export INNODB_LOG_FILE_SIZE="256M"
    export MARIADB_MAX_CONNECTIONS="100"
    export PHP_UPLOAD_MAX="256m"
    export PHP_MAX_EXEC="300"
    export COMPOSER_PROCESS_TIMEOUT="600"
    export PHP_OPCACHE_ENABLE="1"
    export PHP_OPCACHE_MEMORY="256"
    export PHP_OPCACHE_MAX_FILES="20000"
    export PHP_OPCACHE_VALIDATE_TIMESTAMPS="1"

    # XeLaTeX + S3
    export XELATEX_MODE="local"
    export XELATEX_ENDPOINT=""
    export STORAGE_PROVIDER="aws"
    export AWS_REGION="us-east-1"
    export AWS_ACCESS_KEY_ID="$AWS_KEY"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET"
    export S3_BUCKET="$S3_BUCKET_VAL"
    export S3_ENDPOINT_URL=""
    export ASSET_CDN_HOST=""

    # Variant toggles
    export ENABLE_REDIS="$REDIS"
    export ENABLE_S3_STORAGE="$S3"
    export ENABLE_CADVISOR="$CADVISOR"
    export ENVIRONMENT_MODE="$ENV_MODE"
    export ENVIRONMENTS="$ENVIRONMENTS"

    # ── No-op shims: bash functions shadow system commands ──────────────────
    # docker: covers both 'docker build' and 'docker compose ...' calls
    docker()               { return 0; }
    # chown: actools uses chown -R but with '|| true' — just silently succeed
    chown()                { return 0; }
    # Logging stubs (suppress noise; change to echo if debugging)
    section()              { return 0; }
    log()                  { return 0; }
    warn()                 { return 0; }
    error()                { echo "[capture_shim_error] $*" >&2; exit 1; }
    # setup_backup_db_user calls wait_db (docker exec) — fully skip
    setup_backup_db_user() { return 0; }

    # get_backup_pass: read fixed value from state file via jq
    get_state() { jq -r "$1" "${STATE_FILE}" 2>/dev/null || echo "null"; }
    get_backup_pass() {
      local _p
      _p=$(jq -r '.backup_user_pass // empty' "${STATE_FILE}" 2>/dev/null || true)
      echo "${_p:-${FIXED_BACKUP_PASS}}"
    }

    # ── Source extracted stack-generator modules (P0-G) ────────────────────
    # setup_stack now delegates each extracted generated file to a module
    # function, so those functions must be defined in this subshell before
    # setup_stack runs. This list grows as each file moves out of setup_stack.
    # shellcheck disable=SC2043  # one item now; this list grows per extracted file
    for _sm in mycnf; do
      # shellcheck source=/dev/null
      source "${REPO_ROOT}/modules/stack/${_sm}.sh" \
        || _err "capture: cannot source modules/stack/${_sm}.sh"
    done
    unset _sm

    # ── Define setup_stack from the live actools.sh (not a copy) ───────────
    # sed extracts lines SS_START..SS_END; eval defines the function in this
    # subshell; heredocs inside execute only when setup_stack() is called.
    eval "$(sed -n "${SS_START},${SS_END}p" "${ACTOOLS_SH}")"

    setup_stack

  ) || _err "setup_stack() failed for variant '${VNAME}' — see error above"

  _log "  setup_stack done for '${VNAME}'"

  # ===========================================================================
  # PHASE 2 — copy generated stack files to fixture directory
  # (P0-F: the former PHASE-2 CLI render is gone — the CLI is installed by
  #  copying cli/actools verbatim, so it is not a captured fixture.)
  # ===========================================================================
  local -a STACK_FILES=(my.cnf Dockerfile.caddy Dockerfile.php Dockerfile.worker
                        Caddyfile docker-compose.yml)
  for f in "${STACK_FILES[@]}"; do
    [[ -f "${tmp_install}/${f}" ]] \
      || _err "Expected file missing after setup_stack: ${tmp_install}/${f}"
    cp "${tmp_install}/${f}" "${fixture_dir}/${f}"
  done

  # ===========================================================================
  # PHASE 3 — record SHA256 manifest
  # ===========================================================================
  (
    cd "$fixture_dir"
    sha256sum my.cnf Dockerfile.caddy Dockerfile.php Dockerfile.worker \
              Caddyfile docker-compose.yml > SHA256SUMS
  )

  _log "  Variant '${VNAME}' captured → ${fixture_dir}"
  _log "  SHA256SUMS: $(wc -l < "${fixture_dir}/SHA256SUMS") entries"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  _log "P0-C Golden Behavior Capture"
  _log "Repo root  : ${REPO_ROOT}"
  _log "Dest root  : ${ARG_DEST}"
  _log "actools.sh : $(wc -l < "$ACTOOLS_SH") lines"
  _log ""

  # Validate function line ranges before any work — catches actools.sh drift
  _log "Validating function line ranges in actools.sh..."
  _assert_fn_range "setup_stack" "$SS_START" "$SS_END"
  _assert_fn_range "setup_cli"   "$SC_START" "$SC_END"
  _log ""

  mkdir -p "$ARG_DEST"

  # Build list of variants to run
  local -a to_run=()
  if [[ "$ARG_VARIANT" == "all" ]]; then
    to_run=("${ALL_VARIANT_SPECS[@]}")
  else
    local found=false
    for spec in "${ALL_VARIANT_SPECS[@]}"; do
      local vn
      IFS='|' read -r vn _ _ _ _ <<<"$spec"
      if [[ "$vn" == "$ARG_VARIANT" ]]; then
        to_run=("$spec")
        found=true
        break
      fi
    done
    $found || _err "Unknown variant '${ARG_VARIANT}'. Valid names: all default redis-off s3-on cadvisor-on all-in-one"
  fi

  for spec in "${to_run[@]}"; do
    capture_variant "$spec" "$ARG_DEST"
    _log ""
  done

  _log "All captures complete."
  _log "Fixture directory contents:"
  ls -la "$ARG_DEST"
}

main "$@"
