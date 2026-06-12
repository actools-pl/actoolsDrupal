#!/usr/bin/env bats
# =============================================================================
# tests/guards/cron_security_shape_guard_test.bats — P0-L guard
# (cron security shape: defaults-extra-file YES, argv password NEVER)
#
# Locks the SECURE shape of the daily backup cron. The live generator
# (setup_backup_cron — inline in actools.sh before P0-L, modules/backup/cron.sh
# after) writes [mariadb-dump]/user/password into a umask-077 temp file inside
# the DB container and runs `mariadb-dump --defaults-extra-file="$t"`; the
# password reaches the dump client via that file (fed over stdin), NEVER on
# argv, and is read from .actools-state.json at cron RUNTIME (no secret in the
# script). The retired v9.2 orphan twin (deleted at P0-L) used the INSECURE shape —
# `-ubackup -p"${BACKUP_PASS}"` — which exposes the password to every local
# user via `ps`. This guard exists so that shape can never come back:
#
#   arm 1: the RENDERED cron MUST contain `mariadb-dump --defaults-extra-file=`
#   arm 2: the RENDERED cron MUST NOT pass a password on argv
#          (no `-p"…"` / `-p'…'` / `-p$…` / `--password=` form)
#   arm 3 (non-vacuity, permanent): a doctored copy of the live generator that
#          re-introduces the orphan's argv-password invocation is rendered
#          through the SAME pipeline and MUST FAIL the same shape assertions —
#          the guard demonstrably bites on the exact form being purged.
#   arm 4: the generator SOURCE itself carries the secure heredoc and no
#          argv-password text (bites at the source even before render).
#
# Rendering goes through tests/helpers/capture_backup_cron.sh (the P0-L golden
# capture helper), so the guard always checks the bytes the installer would
# write to /etc/cron.daily/actools-backup.
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CRON_HELPER="${REPO}/tests/helpers/capture_backup_cron.sh"
  RENDER_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "${RENDER_TMP:-}"
}

# ---------------------------------------------------------------------------
# _assert_secure_shape <rendered-cron-file>
# The single shape oracle every arm uses (including the non-vacuity arm, which
# expects it to FAIL on the doctored render). Echoes the violation on failure.
# ---------------------------------------------------------------------------
_assert_secure_shape() {
  local f="$1"
  [[ -f "$f" ]] || { echo "shape check: file missing: $f"; return 1; }

  # MUST: the secure defaults-extra-file invocation.
  grep -qF 'mariadb-dump --defaults-extra-file=' "$f" || {
    echo "INSECURE SHAPE: 'mariadb-dump --defaults-extra-file=' missing from the generated cron."
    echo "The secure form (umask-077 temp defaults file inside the container) is authoritative."
    return 1
  }

  # MUST NOT: any argv-password form. Catches the orphan's -p"${BACKUP_PASS}"
  # plus the -p'…' / -p$VAR / --password= variants.
  if grep -nE '(^|[[:space:]])-p["'\''$]|--password=' "$f"; then
    echo "INSECURE SHAPE: argv-password form found in the generated cron (lines above)."
    echo "A password on argv is visible to every local user via ps. The retired"
    echo "orphan (deleted at P0-L) used exactly this form; it must never return."
    return 1
  fi

  # MUST: the password is fetched from state at cron runtime and fed to the
  # defaults file via stdin — not baked into the script at install time.
  grep -qF '.backup_user_pass // empty' "$f" || {
    echo "INSECURE SHAPE: the cron no longer reads backup_user_pass from"
    echo ".actools-state.json at runtime — the password path changed."
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 1 + 2: the live render is secure
# ---------------------------------------------------------------------------

@test "generated backup cron uses mariadb-dump --defaults-extra-file= (secure shape)" {
  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF 'mariadb-dump --defaults-extra-file=' "${RENDER_TMP}/live-cron"
}

@test "generated backup cron passes no DB password on argv (full shape check)" {
  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  _assert_secure_shape "${RENDER_TMP}/live-cron"
}

# ---------------------------------------------------------------------------
# Arm 3: non-vacuity — the guard BITES on the orphan's argv-password form.
# A copy of the LIVE generator is doctored to re-introduce the retired
# orphan's invocation (-ubackup -p"$BK"), rendered through the same
# pipeline, and the same oracle must fail it.
# ---------------------------------------------------------------------------

@test "non-vacuous: an argv-password cron FAILS the shape check" {
  # Locate the live generator the same way the helper does.
  local gen
  if [[ -f "${REPO}/modules/backup/cron.sh" ]] \
     && grep -qE '^setup_backup_cron\(\)' "${REPO}/modules/backup/cron.sh"; then
    gen="${REPO}/modules/backup/cron.sh"
  else
    gen="${REPO}/actools.sh"
  fi

  # Doctor a COPY: replace the secure container-side defaults-file pipeline
  # (the `printf '[mariadb-dump]' … | docker exec … --defaults-extra-file …
  # | gzip` block) with the orphan's argv-password invocation. The doctored
  # text stays a valid generator so the render pipeline itself succeeds —
  # only the SHAPE of its output is insecure.
  local doctored="${RENDER_TMP}/doctored-generator.sh"
  awk '
    /printf / && /\[mariadb-dump\]/ {
      indrop = 1
      print "  docker exec actools_db mariadb-dump \\"
      print "    --single-transaction --quick \\"
      print "    -ubackup -p\"\\$BK\" \"\\$DB\" \\"
      print "    | gzip > \"\\$DUMPFILE\""
      next
    }
    indrop { if (/\| gzip > /) { indrop = 0 }; next }
    { print }
  ' "$gen" > "$doctored"

  # Sanity (scoped to the FUNCTION text — the doctored file may be a full
  # actools.sh copy whose unrelated db_exec_root block legitimately uses
  # --defaults-extra-file): the doctored generator must still define the
  # function, must now carry the insecure form, and must have lost the secure
  # form — otherwise this arm itself is vacuous.
  source "${REPO}/tests/core/extract_inline.bash"
  local doctored_fn
  doctored_fn="$(extract_inline_fn setup_backup_cron "$doctored")"
  grep -qF -- '-ubackup -p"' <<<"$doctored_fn"
  ! grep -qF 'mariadb-dump --defaults-extra-file=' <<<"$doctored_fn"

  # Render the doctored generator through the SAME pipeline.
  run bash "$CRON_HELPER" render-from "$doctored" "${RENDER_TMP}/insecure-cron"
  [ "$status" -eq 0 ] || { echo "doctored render failed: $output"; return 1; }

  # The oracle MUST reject it.
  run _assert_secure_shape "${RENDER_TMP}/insecure-cron"
  [ "$status" -ne 0 ] || {
    echo "VACUOUS GUARD: the argv-password cron PASSED the shape check."
    return 1
  }
  [[ "$output" == *"INSECURE SHAPE"* ]] || {
    echo "Shape check failed for an unexpected reason (not the argv-password arm):"
    echo "$output"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 4: the generator SOURCE is secure (bites pre-render too)
# ---------------------------------------------------------------------------

@test "live setup_backup_cron source carries the secure heredoc and no argv-password text" {
  local gen
  if [[ -f "${REPO}/modules/backup/cron.sh" ]] \
     && grep -qE '^setup_backup_cron\(\)' "${REPO}/modules/backup/cron.sh"; then
    gen="${REPO}/modules/backup/cron.sh"
  else
    gen="${REPO}/actools.sh"
  fi

  # The function text (P0-K brace-counting primitive — heredoc-safe).
  source "${REPO}/tests/core/extract_inline.bash"
  local fn_text
  fn_text="$(extract_inline_fn setup_backup_cron "$gen")"

  grep -qF 'mariadb-dump --defaults-extra-file=' <<<"$fn_text"
  grep -qF 'umask 077' <<<"$fn_text"
  if grep -nE '(^|[[:space:]])-p["'\''$]|--password=' <<<"$fn_text"; then
    echo "argv-password text found in the live setup_backup_cron source (${gen})."
    return 1
  fi
}
