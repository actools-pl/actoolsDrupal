# Handoff — P0-D · Install-Stage Dispatcher Skeleton

## Repository state

Branch: `phase0/P0-D-install-stage-dispatcher`
Commit SHA: (recorded by operator at apply time)
Working tree clean? yes (after the P0-D commit)
Zip/package name if applicable: `actoolsDrupal-main` (uploaded snapshot; baseline `master` @ 2a89e11)

## Task completed

Routed the default `fresh` install through an install-stage dispatcher while
keeping behaviour and generated output byte-identical. `actools.sh` `main()`
now sources `profiles/community.profile` and iterates `PROFILE_INSTALL_STAGES`
via `actools::dispatch::run_install_stage`; the new resolver/runner pair and the
five community base handlers live in `installer/dispatch.sh`. Golden drift stays
6/6; a new 12-test bats file covers order, behaviour preservation, the
append-only stage guard, and resolver correctness.

## Files changed

- `installer/dispatch.sh` — **append-only** (after line 191, behind the existing
  `_ACTOOLS_DISPATCH_SOURCED` guard). Added:
  - `actools::dispatch::resolve_install_stage <stage>` — community →
    `actools::install::stage_<stage>`; community-plus → `plus_<stage>`; test →
    `test_<stage>`; unknown → WARN + community base handler (documented
    asymmetry: install stages must resolve to a runnable function, never empty).
  - `actools::dispatch::run_install_stage <stage>` — resolves, asserts the
    handler is defined (`declare -F`), invokes it; silent on the happy path,
    errors loudly on an undefined handler.
  - `actools::install::stage_{host,stack,db,drupal,worker}` — base handlers.
    `stack`→`setup_stack`; `drupal`→ the per-env `install_env` loop copied
    verbatim from `main()`; `host`/`db`/`worker`→ documented no-ops.
- `actools.sh` — **`main()` only** (fresh mode). Replaced the hardcoded
  `setup_stack` + per-env `install_env` block with the profile-driven stage
  loop. `setup_backup_cron` / `setup_cli` / `tls_check` left as trailing steps.
  No edits above `main()`; `setup_stack`/`setup_cli` line ranges unchanged.
- `tests/installer/dispatch_stages_test.bats` — **new**, 12 tests.
- `docs/runbooks/PHASE0_LEDGER.md` — Entry 009.
- `docs/architecture/runtime-authority-map.md` — install-stage + resolver rows,
  test-surface count (76→88), Review-question answer.
- `docs/CHANGELOG.md` — P0-D runtime-change section.
- `docs/releases/P0-D-install-stage-dispatcher.md` — release note (incl. Rollback).
- `docs/tests/P0-D-install-stage-dispatcher.md` — test report.
- `docs/runbooks/HANDOFF-P0-D.md` — this handoff.

## Files not changed but relevant

- `profiles/community.profile` — `PROFILE_INSTALL_STAGES=(host stack db drupal worker)`
  already canonical (`:28`); read, not redefined.
- `setup_stack` / `install_env` / `setup_backup_cron` / `setup_cli` / `tls_check`
  bodies — unchanged; the dispatcher calls them as-is.
- `tests/helpers/capture_golden_outputs.sh` — unchanged; `SS_*/SC_*` ranges still
  valid (guard not widened/disabled).
- All generated-file generators and `cli/*`, `modules/*`, `core/*`,
  `.github/workflows/*` — untouched.

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | `main()` now sources `community.profile` to read `PROFILE_INSTALL_STAGES`; profile **selection** by `ACTOOLS_PROFILE` is still P0-E |
| Install stages | **moved** from hardcoded `main()` sequence to the dispatcher (`run_install_stage`/`resolve_install_stage` + `actools::install::stage_*`); behaviour-preserving |
| CLI | none |
| Generated files | none (golden 6/6 unchanged) |
| Preflight | none |
| Doctor | none |
| Handoff | none |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | not touched |
| Caddyfile | not touched |
| my.cnf | not touched |
| Dockerfiles | not touched |
| CLI | not touched |

## Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# Baseline (before)
bats tests/generated/golden_drift_test.bats                                  # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats     # 76/76

# Syntax
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n  # all OK

# After
bats tests/generated/golden_drift_test.bats                                  # 6/6
bats tests/installer/dispatch_stages_test.bats                               # 12/12
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats     # 88/88
```

## Test result

PASS — golden 6/6 before and after (byte-identical generated output); 12/12 new
dispatcher tests; 88/88 regression+new; 94/94 overall. `setup_stack` (569–1028)
and `setup_cli` (1247–1528) ranges re-verified unchanged.

## Docs updated

Ledger (Entry 009), runtime authority map, CHANGELOG, release note, test report,
this handoff.

## Changelog / release notes updated

`docs/CHANGELOG.md` (P0-D section) and `docs/releases/P0-D-install-stage-dispatcher.md`
(with the required `## Rollback`).

## Ledger entry

Entry number: 009

## Known risks

- **db/drupal anchor (judgment call):** DB creation runs inside the `drupal`
  handler; the `db` handler is a no-op. Behaviour-exact now; the genuine split is
  P0-G. Trivially flippable and test-covered.
- **`PARALLEL_INSTALL` global mutation** is preserved in the `drupal` handler
  (not declared local), mirroring legacy. `ENVS`/`TOTAL_RAM`/`env` are local
  (provably neutral — every site re-derives them).
- **Profile hardcode in `main()`:** P0-D sources `community.profile` directly;
  P0-E must replace this with `ACTOOLS_PROFILE`-driven selection.
- **Line-range coupling unchanged:** future `main()`-above edits must update
  `SS_*/SC_*` in the harness in the same commit.

## Blockers

None.

## Exact next allowed task

**P0-E — Profile selection wiring.** Replace the hardcoded
`source community.profile` in `main()` with `ACTOOLS_PROFILE`-driven profile
resolution (via `actools::cli::resolve_profile`) so the stage loop runs the
selected profile's `PROFILE_INSTALL_STAGES`. Golden 6/6 must remain green; the
P0-D dispatcher seam is the foundation. (The Review Gate owns final sequencing.)

## Explicitly forbidden scope for next task

- No module extraction / host-stack decomposition (P0-G).
- No community-plus stage implementations.
- No generated-file byte change.
- No CLI-authority consolidation (P0-F).
- No widening/commenting/disabling the golden harness range guard.

## Review Gate notes

Reviewer (separate Sonnet window) should confirm: (1) golden 6/6 unchanged;
(2) only allowed files touched (`installer/dispatch.sh` append-only, `actools.sh`
`main()` only, dispatcher tests, docs); (3) the stage loop reproduces the legacy
sequence exactly (stage order + behaviour tests); (4) the db/drupal anchor
judgment call is acceptable, or direct a flip to anchor DB work under the `db`
handler instead. Decision: Approved / Needs revision / Blocked.
