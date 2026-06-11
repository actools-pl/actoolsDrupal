#!/usr/bin/env bats
# =============================================================================
# tests/guards/duplicate_function_guard_test.bats — P0-K guard 2 (duplicates)
#
# FAILS when a risky stateless-core function is multiply-defined on the live
# install path — i.e. defined in actools.sh AND in a module that actools.sh
# sources. That is exactly the "wrong wiring" the P0-J closure review rejected
# (PHASE0_LEDGER Entry 015): sourcing a stale core/*.sh twin while the inline
# v14 copy still exists lets load order silently decide the winner — e.g.
# flipping ENABLE_S3_STORAGE's default off (orphan core/validate.sh `:-false`
# vs live `:-true`).
#
# Risky names (the P0-K stateless-core set):
#   validate_env rand_pass gen_if_empty init_state set_state get_state
#   is_installed mark_installed get_db_pass get_backup_pass
#
# Semantics:
#  * A name must be defined EXACTLY ONCE across the live source-closure of
#    actools.sh. Count 2+ = a wired twin / forgotten inline deletion.
#    Count 0 = the function vanished from the live path entirely.
#  * Files on disk but NOT sourced (orphans) cannot collide at runtime and do
#    not trip this guard; the moment one is wired, CI fails. (The unconditional
#    actools.sh+core twin ban is added once the P0-K extraction retires the
#    stale twins — see the P0-K release note.)
#
# Non-vacuous: deliberately adding `source "${INSTALL_DIR}/core/validate.sh"`
# to actools.sh while the inline validate_env still exists makes this guard
# fail — demonstrated in the P0-K test report.
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

load live_closure

RISKY_FUNCTIONS=(
  validate_env
  rand_pass
  gen_if_empty
  init_state
  set_state
  get_state
  is_installed
  mark_installed
  get_db_pass
  get_backup_pass
)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  build_live_closure "$REPO"
}

@test "each risky core function is defined exactly once on the live install path" {
  local fn line count where
  local -a violations=()

  for fn in "${RISKY_FUNCTIONS[@]}"; do
    line="$(count_live_defs "$fn")"
    count="${line%% *}"
    where="${line#* }"
    if [[ "$count" -ne 1 ]]; then
      violations+=("$fn: defined ${count}x on the live path [${where}]")
    fi
  done

  if (( ${#violations[@]} > 0 )); then
    echo "Risky core functions must be defined exactly once on the live install path:"
    printf '  %s\n' "${violations[@]}"
    echo ""
    echo "Count >1 = a wired twin (wrong wiring) or an inline copy that was not"
    echo "deleted on extraction. Count 0 = the function fell off the live path."
    return 1
  fi
}

@test "no risky core function is defined in both actools.sh and a sourced core module" {
  # The named regression: an orphan core/*.sh twin gets wired (sourced) while
  # the inline definition still exists. Redundant with exactly-once above, but
  # stated explicitly so the failure message names the exact mistake.
  local fn f n_inline n_mod
  local -a violations=()

  for fn in "${RISKY_FUNCTIONS[@]}"; do
    n_inline=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(\)" "$REPO/actools.sh" 2>/dev/null || true)
    (( n_inline > 0 )) || continue
    for f in "${CLOSURE[@]}"; do
      [[ "$f" == core/*.sh ]] || continue
      n_mod=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(\)" "$REPO/$f" 2>/dev/null || true)
      (( n_mod > 0 )) && violations+=("$fn: inline in actools.sh AND in sourced $f")
    done
  done

  if (( ${#violations[@]} > 0 )); then
    echo "Inline + sourced-core dual definition detected (wrong wiring):"
    printf '  %s\n' "${violations[@]}"
    return 1
  fi
}

@test "twin ban: no risky core function is defined in both actools.sh and any core module" {
  # Hardened arm, enabled by the final P0-K extraction (validate): with the
  # four stateless-core units extracted and the stale v9.2 twins retired, a
  # risky name must never again appear in BOTH actools.sh and core/*.sh —
  # sourced or not. (Before P0-K completed, the unsourced stale twins made
  # this unsatisfiable; the exactly-once closure arm covered the runtime
  # hazard. This arm now also bans dormant orphan twins from ever returning.)
  local fn f n_inline n_core
  local -a violations=()

  for fn in "${RISKY_FUNCTIONS[@]}"; do
    n_inline=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(\)" "$REPO/actools.sh" 2>/dev/null || true)
    (( n_inline > 0 )) || continue
    for f in "$REPO"/core/*.sh; do
      [[ -f "$f" ]] || continue
      n_core=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(\)" "$f" 2>/dev/null || true)
      (( n_core > 0 )) && violations+=("$fn: inline in actools.sh AND in ${f#"$REPO"/}")
    done
  done

  if (( ${#violations[@]} > 0 )); then
    echo "Twin definition detected (inline copy not deleted, or orphan twin reintroduced):"
    printf '  %s\n' "${violations[@]}"
    return 1
  fi
}
