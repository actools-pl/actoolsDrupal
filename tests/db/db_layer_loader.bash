#!/usr/bin/env bash
# =============================================================================
# tests/db/db_layer_loader.bash — P0-M live-DB-layer loader.
#
# Loads the SIX live DB-layer functions (db_exec_root, db_exec_root_stdin,
# db_dump_container, setup_backup_db_user, wait_db, check_db_creds) from
# wherever they currently live:
#
#   * modules/db/core.sh — the live module (post-P0-M extraction), sourced
#                          directly (functions only, inert under `set -u`);
#   * actools.sh         — the inline v14 blocks (pre-extraction), extracted
#                          one function at a time with the P0-K brace-counting
#                          primitive (tests/core/extract_inline.bash) and
#                          eval'd into the test shell.
#
# The SAME loader — and therefore the SAME contract assertions in
# tests/db/db_contract_test.bats — runs against both locations. Keeping the
# contracts green across the move is the faithfulness proof: the
# capture_backup_cron.sh pattern from P0-L, applied to a STATEFUL layer where
# there is no rendered output to golden-capture, so the pinned artifact is the
# set of commands and SQL the functions issue against a mock `docker`.
#
# load_db_layer <repo_root>
#   Defines the six functions in the calling shell and sets DB_LAYER_ORIGIN to
#   "module" or "inline". Fails loudly (rc 1) if any function cannot be found.
# =============================================================================

DB_LAYER_FUNCTIONS=(
  db_exec_root
  db_exec_root_stdin
  db_dump_container
  setup_backup_db_user
  wait_db
  check_db_creds
)

load_db_layer() {
  local repo="$1" fn body
  local module="$repo/modules/db/core.sh"

  # The P0-K extraction primitive (brace counting; heredoc-safe for these
  # bodies — verified in the P0-M test report).
  # shellcheck source=/dev/null
  source "$repo/tests/core/extract_inline.bash"

  if [[ -f "$module" ]] && grep -qE '^db_exec_root\(\)' "$module"; then
    DB_LAYER_ORIGIN="module"
    # The live module: function definitions only, no top-level variable reads
    # or assignments — safe to source under `set -u`.
    # shellcheck source=/dev/null
    source "$module"
  else
    DB_LAYER_ORIGIN="inline"
    for fn in "${DB_LAYER_FUNCTIONS[@]}"; do
      body="$(extract_inline_fn "$fn" "$repo/actools.sh")" \
        || { echo "load_db_layer: cannot extract ${fn}() from actools.sh" >&2; return 1; }
      eval "$body"
    done
  fi

  for fn in "${DB_LAYER_FUNCTIONS[@]}"; do
    declare -F "$fn" >/dev/null \
      || { echo "load_db_layer: ${fn}() not defined after load (origin: ${DB_LAYER_ORIGIN})" >&2; return 1; }
  done
}
