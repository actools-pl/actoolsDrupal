#!/usr/bin/env bats
# =============================================================================
# tests/guards/orphan_inventory_guard_test.bats — Phase C1 guard
#
# PINS THE LIVE-MODULE SET. Fails when the set of modules/<name>/ directories
# reached by the live install path stops matching the canonical set recorded
# below (and mirrored in docs/architecture/runtime-authority-map.md). Two drift
# directions are caught:
#   - an UNDOCUMENTED NEW live module — e.g. someone sources modules/ai/… on
#     the live path → the derived set grows → this guard fails;
#   - a DOCUMENTED-LIVE module that STOPS being sourced → the derived set
#     shrinks → this guard fails.
#
# This is the capture/guard-BEFORE-the-change for Track C: C2 (delete the
# dead-twin orphans) and C3 (quarantine the 4.5-seed orphans) are safe only
# because this guard freezes which modules are actually live. C1 makes NO code
# change and NO behaviour change — it adds this guard plus the human-readable
# "Standalone modules" inventory in the runtime authority map.
#
# CANONICAL SET ↔ DOC. The expected live-module set is the ONE literal list
# below (EXPECTED_LIVE_MODULES). It mirrors the "Standalone modules" section of
# docs/architecture/runtime-authority-map.md. ANY phase that changes the
# live-module set MUST update BOTH: this literal list AND that doc section.
#
# DERIVED, NOT HARDCODED. The *actual* live-module set is derived from the
# tree (see derive_live_modules): the modules/<name>/ dirs reached by the
# source-closure of actools.sh (the CLOSURE array from live_closure.bash),
# UNIONed with modules/<name> references found in the live entry points
# (actools.sh, installer/, cli/actools). The union is required because some
# live modules are reached without a ${INSTALL_DIR} source line from actools.sh
# — e.g. audit, copied in and invoked from cli/actools — and because the closure engine
# skips a source target whose file does not exist on disk, while a text grep
# of the entry points still sees a freshly-wired reference.
#
# NON-VACUOUS. A closure-sanity test (mirroring live_authority_guard_test.bats)
# pins the closure engine so this guard cannot pass vacuously if the engine
# silently returns nothing. The equality test itself is demonstrably
# non-vacuous: injecting a modules/ai/… source line into a live-path file
# (e.g. actools.sh) makes the derived set include `ai`, so the equality
# assertion FAILS; reverting the injection makes it pass. (Inject→fail→
# revert→pass is captured in HANDOFF-C1.md.)
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

load live_closure

# --- The canonical live-module set (THE one literal list; mirrors the
# --- "Standalone modules" section of runtime-authority-map.md). Update BOTH
# --- this list and that doc section in any phase that changes the live set.
EXPECTED_LIVE_MODULES=(audit backup db drupal host stack)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  build_live_closure "$REPO"
}

# derive_live_modules — echo the sorted, newline-separated set of
# modules/<name> directories reached by the live path. Derived from the tree;
# never hardcoded. Result is always a subset of the actual modules/* dirs.
derive_live_modules() {
  local m

  # The actual module directories (so the derived set stays a subset of them).
  local -a dirs=()
  while IFS= read -r m; do
    [[ -n "$m" ]] && dirs+=("$m")
  done < <(find "$REPO/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

  # Set A — modules reached by the source-closure of actools.sh.
  local set_a
  set_a="$(printf '%s\n' "${CLOSURE[@]}" \
             | sed -n -E 's#^modules/([^/]+)/.*#\1#p' | sort -u)"

  # Set B — modules referenced in the live entry points (actools.sh,
  # installer/, cli/actools), intersected with the real module dirs.
  local refs set_b=""
  refs="$(grep -rhoE 'modules/[A-Za-z0-9_]+' \
            "$REPO/actools.sh" "$REPO/installer" "$REPO/cli/actools" 2>/dev/null \
            | sed -E 's#^modules/##' | sort -u)"
  for m in "${dirs[@]}"; do
    if printf '%s\n' "$refs" | grep -qxF "$m"; then
      set_b+="$m"$'\n'
    fi
  done

  # Union A ∪ B, sorted, blanks dropped.
  printf '%s\n%s\n' "$set_a" "$set_b" | sed '/^$/d' | sort -u
}

@test "closure sanity (orphan-inventory): the builder resolves the known live install path" {
  # The guard is only as good as its closure engine. Pin the engine to the
  # known shape of the live path so silent breakage fails loudly here instead
  # of letting the live-set check pass vacuously.
  (( ${#CLOSURE[@]} >= 15 )) || {
    echo "Live closure suspiciously small (${#CLOSURE[@]} files):"
    printf '  %s\n' "${CLOSURE[@]}"
    return 1
  }
  local must
  for must in \
    "actools.sh" \
    "installer/dispatch.sh" \
    "modules/drupal/provision.sh" \
    "modules/host/swap.sh" \
    "modules/stack/compose.sh" \
    "modules/backup/cron.sh" \
    "modules/db/core.sh"
  do
    in_closure "$must" || {
      echo "Expected live-path file missing from closure: $must"
      printf 'Closure was:\n'; printf '  %s\n' "${CLOSURE[@]}"
      return 1
    }
  done
}

@test "the derived live-module set equals the canonical set (audit backup db drupal host stack)" {
  local derived expected
  derived="$(derive_live_modules)"
  expected="$(printf '%s\n' "${EXPECTED_LIVE_MODULES[@]}" | sort)"

  # Derived must be non-empty (belt-and-suspenders with closure-sanity above).
  [[ -n "$derived" ]] || {
    echo "Derived live-module set is EMPTY — the derivation found no live"
    echo "module. Either the closure engine or the entry-point grep broke."
    return 1
  }

  if [[ "$derived" != "$expected" ]]; then
    echo "Live-module set drift — the modules reached by the live path no"
    echo "longer match the canonical set pinned in this guard and in"
    echo "docs/architecture/runtime-authority-map.md (Standalone modules)."
    echo
    echo "Expected (canonical):"; printf '  %s\n' $expected
    echo "Derived  (actual)   :"; printf '  %s\n' $derived
    echo
    echo "Symmetric difference (lines unique to one side):"
    diff <(printf '%s\n' $expected) <(printf '%s\n' $derived) || true
    echo
    echo "If this change is intentional, update BOTH:"
    echo "  - EXPECTED_LIVE_MODULES in this guard, AND"
    echo "  - the 'Standalone modules' section of runtime-authority-map.md."
    return 1
  fi
}
