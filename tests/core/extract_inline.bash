#!/usr/bin/env bash
# =============================================================================
# tests/core/extract_inline.bash — P0-K behavior-capture loader helpers.
#
# Extracts the LIVE inline implementations from actools.sh so the behavior
# tests pin the authoritative v14 code BEFORE it is extracted into core/*.sh
# (P0-K step: "capture current behavior before moving anything").
#
# When a unit is extracted, its test file's loader is re-pointed from
# extract_inline_fn(... actools.sh) to `source core/<unit>.sh` — the
# assertions stay identical, which is what proves the move was faithful.
#
# extract_inline_fn <name> <file>
#   Prints the function definition <name>() {...} from <file>, using brace
#   counting from the definition line to its balanced close. Fails (rc 1,
#   empty output) if the function is not found — callers must check.
#
# extract_inline_writeback <file>
#   Prints the live top-level secret-writeback loop (v9.2 fix7) — the block
#   `for var in DB_ROOT_PASS DRUPAL_ADMIN_PASS; do ... done`. The loop is NOT
#   extracted to a module in P0-K (it is top-level spine code, not a
#   function); this lets the behavior tests pin it where it lives.
# =============================================================================

extract_inline_fn() {
  local fn="$1" file="$2" out
  out="$(awk -v fn="$fn" '
    !infn && $0 ~ ("^" fn "\\(\\)") { infn = 1 }
    infn {
      print
      depth += gsub(/{/, "{") - gsub(/}/, "}")
      if (depth == 0) exit
    }
  ' "$file")"
  [[ -n "$out" ]] || { echo "extract_inline_fn: ${fn}() not found in ${file}" >&2; return 1; }
  printf '%s\n' "$out"
}

extract_inline_writeback() {
  local file="$1" out
  out="$(awk '
    /^for var in DB_ROOT_PASS DRUPAL_ADMIN_PASS; do$/ { inblk = 1 }
    inblk { print }
    inblk && /^done$/ { exit }
  ' "$file")"
  [[ -n "$out" ]] || { echo "extract_inline_writeback: writeback loop not found in ${file}" >&2; return 1; }
  printf '%s\n' "$out"
}
