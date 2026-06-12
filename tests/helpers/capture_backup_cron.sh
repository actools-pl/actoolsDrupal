#!/usr/bin/env bash
# =============================================================================
# tests/helpers/capture_backup_cron.sh
# P0-L — Backup-cron golden capture / render helper
#
# Renders the daily backup cron exactly as the LIVE setup_backup_cron generator
# writes it to /etc/cron.daily/actools-backup, WITHOUT touching /etc and
# WITHOUT executing docker, chmod-on-/etc, or any other privileged side effect.
#
# The REAL generator text is never copied here. The helper locates the live
# definition of setup_backup_cron() —
#
#     modules/backup/cron.sh   when the module defines it (post-extraction), or
#     actools.sh               while the generator is still inline (pre-P0-L)
#
# — extracts it verbatim with the P0-K brace-counting primitive
# (tests/core/extract_inline.bash::extract_inline_fn), and renders it under a
# deterministic fixed environment. Because the SAME renderer runs against the
# pre-extraction inline block and the post-extraction module, a byte-identical
# fixture across the move IS the faithfulness proof for the extraction.
#
# Output-target interposition (the one mechanical substitution):
#   The generator's heredoc writes to the absolute path
#   /etc/cron.daily/actools-backup, which a non-root CI runner cannot write.
#   The helper first PINS the real target — it fails loudly unless the
#   function text contains the exact lines
#       cat > /etc/cron.daily/actools-backup <<BACKUP
#       chmod +x /etc/cron.daily/actools-backup
#   — and only then substitutes that absolute path with a sandbox path in its
#   IN-MEMORY copy before eval. The substitution changes WHERE the file lands,
#   never WHAT is in it: the heredoc body and every render-time expansion are
#   untouched, so the captured bytes are exactly what the installer writes to
#   /etc/cron.daily/actools-backup. No repo file is modified.
#
# Secret-safety of the fixture: the generated cron holds NO secret. The backup
# password is read from .actools-state.json at cron RUNTIME (the jq line in
# the script); the generator's local backup_pass never reaches the heredoc.
# The fixture is therefore safe to commit — and the P0-L security-shape guard
# (tests/guards/cron_security_shape_guard_test.bats) asserts both that and the
# secure --defaults-extra-file invocation.
#
# Usage:
#   bash tests/helpers/capture_backup_cron.sh capture [<dest-dir>]
#       Render and store the golden fixture (actools-backup + SHA256SUMS).
#       Default dest: tests/fixtures/golden/backup-cron
#   bash tests/helpers/capture_backup_cron.sh render <out-file>
#       Render the cron from the live generator to <out-file> (drift test +
#       security guard entry point).
#   bash tests/helpers/capture_backup_cron.sh render-from <generator-file> <out-file>
#       Render from an arbitrary file defining setup_backup_cron(). Used by
#       the security guard's non-vacuity arm to push a DOCTORED COPY of the
#       generator through this same pipeline and prove the guard bites.
#
# Fixed deterministic inputs (the cron embeds these at render time):
#   INSTALL_DIR=/opt/actools-golden   ENVIRONMENTS=prod
#   ENABLE_S3_STORAGE=true (the v14 default :-true, made explicit)
#   S3_BUCKET=""  S3_ENDPOINT_URL=""  STORAGE_PROVIDER=aws
#   BACKUP_RETENTION_DAYS=7  RCLONE_REMOTE=""
#
# CAPTURE-ONLY: this script makes NO change to actools.sh or any runtime file.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The P0-K verbatim-extraction primitive (brace-counting; heredoc-safe — the
# cron heredoc's braces are balanced, verified against the raw line range).
# shellcheck source=/dev/null
source "${REPO_ROOT}/tests/core/extract_inline.bash"

# ── Fixed deterministic constants ────────────────────────────────────────────
readonly FIXED_INSTALL_DIR="/opt/actools-golden"
readonly FIXED_ENVIRONMENTS="prod"
readonly FIXED_BACKUP_PASS="TEST_BACKUP_PASS_FIXED"
readonly CRON_TARGET="/etc/cron.daily/actools-backup"
readonly DEFAULT_DEST="${REPO_ROOT}/tests/fixtures/golden/backup-cron"

_log() { echo "[P0-L] $*"; }
_err() { echo "[P0-L] ERROR: $*" >&2; exit 1; }

# ── locate_generator: echo the file that LIVE-defines setup_backup_cron ─────
# Post-extraction: modules/backup/cron.sh (the live module).
# Pre-extraction:  actools.sh (the inline block).
# Defined in BOTH → hard fail: that is the dual-definition regression P0-K's
# duplicate-function guard exists for; the capture must not paper over it.
locate_generator() {
  local in_module=false in_inline=false
  local module="${REPO_ROOT}/modules/backup/cron.sh"
  if [[ -f "$module" ]] && grep -qE '^setup_backup_cron\(\)' "$module"; then
    in_module=true
  fi
  if grep -qE '^setup_backup_cron\(\)' "${REPO_ROOT}/actools.sh"; then
    in_inline=true
  fi
  if $in_module && $in_inline; then
    _err "setup_backup_cron() is defined in BOTH modules/backup/cron.sh and actools.sh — dual definition; fix the tree before capturing."
  fi
  if $in_module; then echo "$module"; return 0; fi
  if $in_inline; then echo "${REPO_ROOT}/actools.sh"; return 0; fi
  _err "setup_backup_cron() not found in modules/backup/cron.sh or actools.sh."
}

# ── render_cron <generator-file> <out-file> ──────────────────────────────────
# Extract setup_backup_cron() verbatim from <generator-file>, pin its real
# install target, substitute ONLY that target with <out-file>, and execute the
# generator under the fixed deterministic environment in an isolated subshell.
render_cron() {
  local gen_file="$1" out_file="$2"
  local fn_text

  fn_text="$(extract_inline_fn setup_backup_cron "$gen_file")" \
    || _err "cannot extract setup_backup_cron() from ${gen_file}"

  # Pin the real install target before any substitution. If a future edit
  # moves or renames the target, fail loudly here instead of silently
  # capturing the wrong artifact.
  grep -qF "cat > ${CRON_TARGET} <<BACKUP" <<<"$fn_text" \
    || _err "pin failed: 'cat > ${CRON_TARGET} <<BACKUP' not found in setup_backup_cron() (${gen_file}). The install target moved — update this helper's CRON_TARGET pin deliberately."
  grep -qF "chmod +x ${CRON_TARGET}" <<<"$fn_text" \
    || _err "pin failed: 'chmod +x ${CRON_TARGET}' not found in setup_backup_cron() (${gen_file})."

  # The one mechanical substitution: redirect the OUTPUT LOCATION to the
  # sandbox. The heredoc body — the generated bytes — is untouched.
  local rendered_fn
  rendered_fn="${fn_text//${CRON_TARGET}/${out_file}}"

  # Isolated execution: fixed env + no-op shims for the generator's
  # collaborators (section/log are cosmetic; get_backup_pass feeds a local
  # that never reaches the heredoc — the cron reads the pass from state at
  # runtime). chmod runs for real against the sandbox file (harmless).
  (
    export INSTALL_DIR="$FIXED_INSTALL_DIR"
    export ENVIRONMENTS="$FIXED_ENVIRONMENTS"
    export ENABLE_S3_STORAGE="true"
    export S3_BUCKET=""
    export S3_ENDPOINT_URL=""
    export STORAGE_PROVIDER="aws"
    export BACKUP_RETENTION_DAYS="7"
    export RCLONE_REMOTE=""

    # shellcheck disable=SC2317  # shims are invoked indirectly by the eval'd generator
    section()         { return 0; }
    # shellcheck disable=SC2317
    log()             { return 0; }
    # shellcheck disable=SC2317
    warn()            { return 0; }
    # shellcheck disable=SC2317
    error()           { echo "[capture_shim_error] $*" >&2; exit 1; }
    # shellcheck disable=SC2317
    get_backup_pass() { echo "$FIXED_BACKUP_PASS"; }

    eval "$rendered_fn"
    setup_backup_cron
  ) || _err "render failed for generator ${gen_file} — see error above"

  [[ -f "$out_file" ]] || _err "render produced no file at ${out_file}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  local mode="${1:-capture}"
  case "$mode" in
    capture)
      local dest="${2:-$DEFAULT_DEST}"
      local gen
      gen="$(locate_generator)"
      _log "Backup-cron golden capture"
      _log "Generator : ${gen#"$REPO_ROOT"/}"
      _log "Dest      : ${dest}"
      mkdir -p "$dest"
      render_cron "$gen" "${dest}/actools-backup"
      ( cd "$dest" && sha256sum actools-backup > SHA256SUMS )
      _log "Fixture captured → ${dest}/actools-backup"
      _log "SHA256SUMS: $(cat "${dest}/SHA256SUMS")"
      ;;
    render)
      local out="${2:-}"
      [[ -n "$out" ]] || _err "usage: $0 render <out-file>"
      local gen
      gen="$(locate_generator)"
      render_cron "$gen" "$out"
      ;;
    render-from)
      local gen_file="${2:-}" out="${3:-}"
      [[ -n "$gen_file" && -n "$out" ]] || _err "usage: $0 render-from <generator-file> <out-file>"
      [[ -f "$gen_file" ]] || _err "generator file not found: ${gen_file}"
      render_cron "$gen_file" "$out"
      ;;
    *)
      _err "unknown mode '${mode}'. Valid: capture [<dest>], render <out>, render-from <gen> <out>"
      ;;
  esac
}

main "$@"
