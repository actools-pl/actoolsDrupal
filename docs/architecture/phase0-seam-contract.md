# Phase 0 Seam Contract

## Status

Target contract for Phase 0 seam hardening. This is not a community-plus feature implementation document.

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

