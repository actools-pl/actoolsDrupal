# Release note — P0-D · Install-Stage Dispatcher Skeleton

Branch: `phase0/P0-D-install-stage-dispatcher`
Phase: P0-D — Install-Stage Dispatcher Skeleton
Status: pending Review Gate
Commit SHA: (recorded by operator at apply time)

## Summary

The default `fresh` install now runs through an **install-stage dispatcher**
instead of a hardcoded sequence of function calls. `actools.sh` `main()` sources
the community profile and iterates `PROFILE_INSTALL_STAGES=(host stack db drupal
worker)`, calling `actools::dispatch::run_install_stage` for each stage. Each
stage resolves (via `actools::dispatch::resolve_install_stage`) to a community
base handler in `installer/dispatch.sh`.

This is a **seam-only, behaviour-preserving** change. It establishes the
profile-driven, append-only extension point for install stages (the mechanism
that makes the LOCKED "community-plus *appends* `plus_*`" decision enforceable)
without moving any host/stack logic into modules — that decomposition is P0-G.

## What changed

- `installer/dispatch.sh` (append-only): `resolve_install_stage`,
  `run_install_stage`, and base handlers
  `actools::install::stage_{host,stack,db,drupal,worker}`.
- `actools.sh` `main()` (fresh mode only): hardcoded `setup_stack` + per-env
  `install_env` block replaced with the profile-driven stage loop. Trailing
  `setup_backup_cron` / `setup_cli` / `tls_check` unchanged.
- `tests/installer/dispatch_stages_test.bats` (new, 12 tests).
- Docs: ledger Entry 009, runtime authority map, CHANGELOG, this release note,
  and the test report.

### Stage → handler mapping (this phase)

| Stage  | Handler                          | Behaviour |
|---|---|---|
| host   | `actools::install::stage_host`   | no-op (folded into `setup_stack` until P0-G) |
| stack  | `actools::install::stage_stack`  | `setup_stack` unchanged |
| db     | `actools::install::stage_db`     | no-op (folded into the `install_env` loop until P0-G) |
| drupal | `actools::install::stage_drupal` | per-env `install_env` loop, verbatim |
| worker | `actools::install::stage_worker` | no-op (folded into `setup_stack` until P0-G) |

## Operator impact

**None.** The community install performs the same operations in the same order,
with the same parallel/sequential and low-RAM-downgrade behaviour and the same
trailing steps. Generated files are byte-identical (golden drift 6/6).

## Verification

- `bats tests/generated/golden_drift_test.bats` → 6/6 (before and after).
- `bats tests/installer/dispatch_stages_test.bats` → 12/12.
- `bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats` → 88/88.
- `bash -n` on `actools.sh`, `cli/actools`, and all `installer/core/modules/cli`
  shell files → clean.
- `setup_stack` (569–1028) and `setup_cli` (1247–1528) line ranges re-verified
  unchanged; the golden harness `_assert_fn_range` still holds.

## Rollback

Revert commit <sha>. No data migration is expected. The change is confined to
`installer/dispatch.sh` (append-only) and `actools.sh` `main()`; reverting
restores the prior hardcoded `setup_stack` + `install_env` sequence with no
effect on generated files, state, or installed environments.
