# Phase 0 Seam Contract

## Status

Target contract for Phase 0 seam hardening. This is not a community-plus feature implementation document.

### Implementation status (informative)

The target functions below are the Phase-0 goal; the live wiring lands incrementally:

- **`resolve_install_stage` / `run_install_stage`** — landed (P0-D); `main()` iterates `PROFILE_INSTALL_STAGES` through the dispatcher.
- **Install-stage handlers** — `host` and `stack` are now **driven by the dispatcher (P0-G)**: `stage_host` invokes the `modules/host/*` functions in the canonical order (`packages → age → kernel → swap → firewall → docker → logrotate`), and `stage_stack` runs `setup_stack`, which is now a thin orchestrator delegating to the `modules/stack/*` generators (`generate_mycnf`, `build_caddy_image`/`build_php_image`/`build_worker_image`, `generate_caddyfile`, `generate_compose`). The `db` and `worker` stages remain documented no-ops (DB SQL stays in `install_env`; the worker runtime stays in the compose generator). Behaviour-preserving: golden drift 6/6, fixtures unchanged.
- **`resolve_feature_handler` (3-tier) / `resolve_profile_check`** — implemented as internal primitives (P0-E); **the live surface wiring landed (P0-H)**: `resolve_feature_handler` drives `doctor --deep` (baseline fallback to the built-in gate), and `resolve_profile_check` drives `preflight` extras (unknown → hard fail for a non-default profile) and `handoff` sections (unresolved → visible non-fatal notice). `init` profile-awareness landed in P0-E and is unchanged. The per-check `PROFILE_DOCTOR_EXTRA` consumer loop is **deliberately deferred** (no Phase-0 consumer; the `resolve_doctor_check` primitive exists and is tested). `community` short-circuits to empty everywhere — byte-identical (golden drift 6/6).
- **Profile file-existence validation + governance enforcement at `init`** — landed (P0-E).

## Purpose

Phase 0 creates the seams that allow future profiles to extend behavior without hardcoded conditionals in community code.

## Required functions

### `resolve_feature_handler`

Purpose: resolve command feature handlers such as `doctor_deep`.

Target resolution order:

1. Active profile override.
2. Profile extension module.
3. Default handler.
4. Gate stub or clean failure.

### `resolve_install_stage`

Purpose: resolve install stages such as `host`, `stack`, `db`, `drupal`, `worker`, and later appended profile stages.

### `resolve_profile_check`

Purpose: resolve profile-specific checks or sections for `preflight`, `doctor`, and `handoff`.

### `run_install_stage`

Purpose: execute a resolved install stage and record result.

Target behavior:

````bash
for stage in "${PROFILE_INSTALL_STAGES[@]}"; do
  run_install_stage "$stage"
done
````

## Profile contract

Each profile file must be source-only and side-effect free.

Allowed:

````bash
PROFILE_NAME="community"
PROFILE_INSTALL_STAGES=(host stack db drupal worker)
PROFILE_INIT_FIELDS=()
PROFILE_PREFLIGHT_EXTRA=()
PROFILE_DOCTOR_EXTRA=()
PROFILE_HANDOFF_SECTIONS=()
PROFILE_REQUIRES_ACTOR=false
PROFILE_REQUIRES_CHANGE_TICKET=false
````

Forbidden:

- starting services,
- writing files,
- calling package managers,
- sourcing feature modules directly,
- modifying global state outside profile variables.

## Non-bypass rule

No Phase 1+ feature may hardcode paths like:

````bash
source "${INSTALL_DIR}/modules/plus_..."
````

All feature-specific resolution must pass through the resolver.

## Default behavior preservation

For `community`, target behavior after Phase 0 must match pre-Phase-0 behavior unless a deliberate change is documented.

## Required tests

- default profile resolves existing handlers,
- unknown profile fails before persistence,
- missing profile file fails before persistence,
- fake profile exercises init, preflight, install stage, doctor, handoff,
- resolver bypass static check passes.

