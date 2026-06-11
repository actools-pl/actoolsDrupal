#!/usr/bin/env bats
# =============================================================================
# tests/guards/live_authority_guard_test.bats — P0-K guard 1 (live authority)
#
# FAILS when a file declares itself live/authoritative — the "LIVE AUTHORITY"
# header marker established at P0-G — but is NOT sourced on the live install
# path (the transitive source-closure of actools.sh).
#
# This is the anti-regression guard for the failure mode the P0-J closure
# review documented (PHASE0_LEDGER Entry 015): files that LOOK authoritative
# (the stale core/*.sh v9.2 twins) while the inline v14 code is what actually
# runs. A file may carry the authority marker only if the live path reaches it.
#
# Marker scope scanned: actools.sh, core/, installer/, modules/, profiles/,
# cron/ — the install-side tree. cli/ is the operator-CLI surface (installed
# by copy, P0-F), not the install path; tests/ and docs/ are not runtime.
#
# Non-vacuous: adding the marker to an unsourced file (e.g. an orphan core
# module) makes this guard fail — demonstrated in the P0-K test report.
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

load live_closure

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  build_live_closure "$REPO"
}

@test "closure sanity: the builder resolves the known live install path" {
  # The guard is only as good as its closure engine. Pin the engine to the
  # known shape of the live path so silent breakage fails loudly here instead
  # of letting the authority check pass vacuously.
  (( ${#CLOSURE[@]} >= 15 )) || {
    echo "Live closure suspiciously small (${#CLOSURE[@]} files):"
    printf '  %s\n' "${CLOSURE[@]}"
    return 1
  }
  local must
  for must in \
    "actools.sh" \
    "installer/dispatch.sh" \
    "installer/profile.sh" \
    "modules/drupal/provision.sh" \
    "modules/host/swap.sh" \
    "modules/stack/compose.sh" \
    "profiles/community.profile"
  do
    in_closure "$must" || {
      echo "Expected live-path file missing from closure: $must"
      printf 'Closure was:\n'; printf '  %s\n' "${CLOSURE[@]}"
      return 1
    }
  done
}

@test "every file declaring LIVE AUTHORITY is sourced on the live install path" {
  local -a marked=() violations=()
  local f rel

  while IFS= read -r f; do
    marked+=("$f")
  done < <(grep -rl 'LIVE AUTHORITY' \
             "$REPO/actools.sh" \
             "$REPO/core" "$REPO/installer" "$REPO/modules" \
             "$REPO/profiles" "$REPO/cron" 2>/dev/null | sort)

  # The marker convention exists since P0-G — an empty scan means the
  # convention was silently dropped, which this guard must also catch.
  (( ${#marked[@]} >= 1 )) || {
    echo "No 'LIVE AUTHORITY' markers found anywhere in the install-side tree."
    echo "The P0-G marker convention appears to have been removed."
    return 1
  }

  for f in "${marked[@]}"; do
    rel="${f#"$REPO"/}"
    in_closure "$rel" || violations+=("$rel")
  done

  if (( ${#violations[@]} > 0 )); then
    echo "LIVE AUTHORITY declared but NOT on the live install path:"
    printf '  %s\n' "${violations[@]}"
    echo ""
    echo "Either wire the file into the live path (source it from a live file)"
    echo "or remove its authority claim. A file must not look authoritative"
    echo "while being an orphan — that is the Phase-0 regression this guard exists for."
    return 1
  fi
}
