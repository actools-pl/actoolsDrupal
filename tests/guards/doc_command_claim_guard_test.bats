#!/usr/bin/env bats
# =============================================================================
# doc_command_claim_guard_test.bats — DOC-CLAIM-vs-CLI guard (Phase D2)
#
# Makes doc-truth self-enforcing. Until now a doc could silently advertise — in a
# runnable code-block example — a command that the real CLI does not register
# (hallucinated, removed, or renamed), defended only by manual DOC-CHECK passes.
# This guard parses the REAL dispatch in `cli/actools` and fails CI if any doc
# presents an `actools <cmd>` invocation, inside a fenced code block, whose <cmd>
# is neither registered nor on an explicit "not-registered" allowlist.
#
# THREE DERIVATIONS, all computed at run time (NONE hardcoded):
#   (a) REGISTERED — the top-level arms of the `case "${1:-help}" in` dispatch in
#       cli/actools (the source of truth). The set TRACKS the code: add an arm and
#       the registered set grows; remove one and it shrinks. 29 commands today.
#   (b) ALLOWLIST  — the not-registered table in
#       docs/architecture/runtime-authority-map.md, between the
#       <!-- CMD-ALLOWLIST:BEGIN/END --> markers. 13 commands today.
#   (c) REFERENCED — every `actools <cmd>` invocation inside a FENCED code block
#       across docs/*.md + top-level README.md (comment lines skipped; optional
#       `$ ` prompt and `sudo [-u user]` stripped). Prose mentions are out of
#       scope by design.
#
# SCOPE: the guard scans docs/ + README.md ONLY. It deliberately does NOT scan
# tests/ (so it can never read its own `nonexistent` fixture) nor .github/.
#
# DERIVATION NOTES (declared, see HANDOFF-D2):
#   * The SPEC §3.1(a) reference awk drops only `*`; the real dispatch's terminal
#     arm is `help|*)`, so the bare reference also emits `help` (→ 30). `help` is
#     the help/fallback arm, not an advertised command and not in the canonical
#     29, so this guard drops BOTH `*` and `help`. Dropping `help` is safe for the
#     main check: no doc code block invokes `actools help`.
#
# UPDATE RULE:
#   * A new real command → it registers in cli/actools; the guard tracks it
#     automatically (no edit here).
#   * A new not-yet-registered command a doc must show → add a row to the
#     CMD-ALLOWLIST table in runtime-authority-map.md with a TRUTHFUL backing
#     path, and bump EXPECTED_ALLOWLIST below (the parser-sanity manifest, test 2).
#   * Non-vacuity demos (tests 4 and 5) are recorded verbatim in HANDOFF-D2.
# =============================================================================

REPO=""
setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# The canonical not-registered manifest (parser-sanity expectation for test 2).
# This list is updated in lockstep with the CMD-ALLOWLIST table — same discipline
# as the file-inventory guard's manifest. It is NOT the source the guard checks
# docs against (that is the parsed table, derived live below).
EXPECTED_ALLOWLIST=(
  ai branch cdn ci content cost-optimize dr-test failover gdpr
  immortalize resurrect tenant worker
)

# --- (a) REGISTERED: top-level dispatch arms of cli/actools -------------------
# Reads ONLY the `case "${1:-help}" in` dispatch (not the arg-parse `case "$1"`
# at the top, not the nested `case "${STORAGE_PROVIDER:-aws}"` / `case "${2:-...}"`
# sub-cases — the 2-space arm anchor excludes the deeper-indented sub-arms).
_registered() {
  awk '
    /case "\$\{1:-help\}" in/ { f=1; next }
    f && /^esac/ { exit }
    f && /^  [a-z][a-z0-9_-]*(\|[a-z0-9_*-]+)*\)/ {
      arm=$0; sub(/\).*/,"",arm); sub(/^[[:space:]]+/,"",arm)
      n=split(arm,p,/\|/)
      for(i=1;i<=n;i++) if(p[i]!="*" && p[i]!="help") print p[i]
    }
  ' "$REPO/cli/actools" | sort -u
}

# --- (b) ALLOWLIST: the not-registered table in runtime-authority-map.md -------
# Keyed on the load-bearing CMD-ALLOWLIST markers; first column only; the header
# row and the `---` separator are skipped. Marker-driven, so it is fence-agnostic.
# Optional arg = an alternate source file (used to force-empty in test 5).
_allowlist() {
  local src="${1:-$REPO/docs/architecture/runtime-authority-map.md}"
  awk '
    /<!-- CMD-ALLOWLIST:BEGIN -->/ { f=1; next }
    /<!-- CMD-ALLOWLIST:END -->/   { f=0; next }
    f && /^[[:space:]]*\|/ {
      n=split($0,c,/\|/); cmd=c[2]; gsub(/[`[:space:]]/,"",cmd)
      if (cmd=="" || cmd=="command" || cmd ~ /^-+$/) next
      print cmd
    }
  ' "$src" | sort -u
}

# --- (c) REFERENCED: actools invocations in fenced code blocks ----------------
# Surface = docs/*.md + README.md (+ an optional extra dir for non-vacuity). The
# whole find|while|awk runs in a `cd "$REPO"` subshell so doc paths stay relative
# in diagnostics and resolve regardless of the test's cwd. awk runs per file, so
# the in-block state starts fresh for each file (no cross-file bleed).
_referenced() {
  local extra_dir="${1:-}"
  (
    cd "$REPO" || exit 1
    {
      find docs -name '*.md' -type f
      [ -f README.md ] && echo README.md
      [ -n "$extra_dir" ] && find "$extra_dir" -name '*.md' -type f
    } | while IFS= read -r f; do
      awk '
        /^[[:space:]]*(```|~~~)/ { inb=!inb; next }
        inb && /^[[:space:]]*#/ { next }
        inb {
          l=$0
          sub(/^[[:space:]]*\$?[[:space:]]*/,"",l)
          sub(/^sudo[[:space:]]+(-u[[:space:]]+[^[:space:]]+[[:space:]]+)?/,"",l)
          if (l ~ /^actools(-dev|-real)?[[:space:]]+[a-z]/) {
            sub(/^actools(-dev|-real)?[[:space:]]+/,"",l)
            split(l,a,/[[:space:]]+/); print FILENAME":"FNR":"a[1]
          }
        }
      ' "$f"
    done
  )
}

# --- the core check: REFERENCED invocations outside REGISTERED ∪ ALLOWLIST -----
# args: $1 = allowlist source file (pass /dev/null to force-empty); $2 = extra dir.
# prints each offending "file:line:cmd"; empty output == clean.
_violations() {
  local allow_src="$1" extra_dir="${2:-}"
  local known ref line cmd
  known="$(mktemp)"; ref="$(mktemp)"
  { _registered; _allowlist "$allow_src"; } | sort -u > "$known"
  _referenced "$extra_dir" > "$ref"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    cmd="${line##*:}"
    grep -qxF "$cmd" "$known" || printf '%s\n' "$line"
  done < "$ref"
  rm -f "$known" "$ref"
}

# =============================================================================

@test "REGISTERED is derived live from the cli/actools dispatch (29 commands)" {
  local count anchor
  count="$(_registered | grep -c . || true)"
  if [[ "$count" -ne 29 ]]; then
    echo "Expected 29 registered commands derived from the dispatch, got $count:"
    _registered
    return 1
  fi
  # proves it reads the dispatch: real top-level commands are present...
  for anchor in status audit worker-run migrate tunnel; do
    if ! _registered | grep -qx "$anchor"; then
      echo "anchor command '$anchor' missing from derived REGISTERED set"; return 1
    fi
  done
  # ...and the nested sub-case arms (storage providers) and the fallback are NOT,
  # which would appear if the parser slurped past the top-level dispatch.
  for nope in backblaze wasabi custom help; do
    if _registered | grep -qx "$nope"; then
      echo "'$nope' leaked into REGISTERED — parser read past the top-level dispatch"
      return 1
    fi
  done
}

@test "ALLOWLIST parses to the 13 not-registered commands, none of them registered" {
  local exp got reg overlap
  exp="$(mktemp)"; got="$(mktemp)"; reg="$(mktemp)"
  printf '%s\n' "${EXPECTED_ALLOWLIST[@]}" | sort -u > "$exp"
  _allowlist > "$got"
  _registered > "$reg"
  if ! diff -u "$exp" "$got" >/dev/null; then
    echo "Parsed CMD-ALLOWLIST drifted from the manifest. diff (expected vs parsed):"
    diff -u "$exp" "$got" || true
    echo "If the allowlist table changed intentionally, update EXPECTED_ALLOWLIST."
    rm -f "$exp" "$got" "$reg"; return 1
  fi
  # no allowlist entry may actually be registered (that would be a stale/bogus row)
  overlap="$(comm -12 "$reg" "$got")"
  rm -f "$exp" "$got" "$reg"
  if [[ -n "$overlap" ]]; then
    echo "Allowlist entries that are ACTUALLY registered (remove them from the table):"
    printf '  %s\n' $overlap
    return 1
  fi
}

@test "every code-block actools invocation in docs/+README is registered or allowlisted" {
  local offenders
  offenders="$(_violations "$REPO/docs/architecture/runtime-authority-map.md" "")"
  if [[ -n "$offenders" ]]; then
    echo "Doc code-block invocations of UNREGISTERED, non-allowlisted commands:"
    printf '%s\n' "$offenders"
    echo "---"
    echo "Either the command was removed/renamed/hallucinated (fix the doc), or it is"
    echo "a real not-yet-registered command (add a truthfully-backed row to the"
    echo "CMD-ALLOWLIST table in docs/architecture/runtime-authority-map.md)."
    return 1
  fi
}

@test "non-vacuity #1: a fenced 'actools nonexistent' example trips the guard" {
  local scratch offenders
  scratch="$(mktemp -d)"
  # a fenced code block containing the bogus invocation (kept under /tmp, never
  # under docs/ or tests/, so only this test's surface sees it)
  printf '%s\n' '```bash' 'actools nonexistent' '```' > "$scratch/bogus.md"
  offenders="$(_violations "$REPO/docs/architecture/runtime-authority-map.md" "$scratch")"
  rm -rf "$scratch"
  if ! printf '%s\n' "$offenders" | grep -q ':nonexistent$'; then
    echo "Guard did NOT flag the injected 'actools nonexistent' — it is vacuous."
    echo "offenders were:"; printf '%s\n' "$offenders"
    return 1
  fi
}

@test "non-vacuity #2: emptying the allowlist makes the 13 not-registered commands fail" {
  local offenders nope
  offenders="$(_violations /dev/null "")"
  if [[ -z "$offenders" ]]; then
    echo "With the allowlist emptied, the not-registered doc commands should ALL be"
    echo "flagged — but nothing was. The allowlist is not actually load-bearing."
    return 1
  fi
  # representative experimental seeds must now surface as offenders
  for nope in immortalize gdpr resurrect; do
    if ! printf '%s\n' "$offenders" | grep -q ":${nope}\$"; then
      echo "expected '$nope' to be flagged once the allowlist is emptied; it was not"
      printf '%s\n' "$offenders"
      return 1
    fi
  done
}
