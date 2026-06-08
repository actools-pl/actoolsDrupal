# P0-D Install-Stage Dispatcher — Test Report

> **Status:** Passing — dispatcher wired, behaviour preserved, golden net green.
> Phase: P0-D — Install-Stage Dispatcher Skeleton
> Produced by: Coding Window (Opus)
> Date: 2026-06-08

---

## Summary

P0-D routes the default `fresh` install through an install-stage dispatcher
(`actools::dispatch::resolve_install_stage` + `actools::dispatch::run_install_stage`
in `installer/dispatch.sh`) by iterating `PROFILE_INSTALL_STAGES`. This report
records the tests added for the dispatcher and the regression/golden evidence
that behaviour and generated output are unchanged.

The defining property: **community installs see zero behaviour change and zero
generated-file change.** The golden drift suite is the arbiter and stays 6/6.

---

## Tests added

New file: `tests/installer/dispatch_stages_test.bats` — 12 tests in three blocks.

### Block 1 — Default stage order (dry/traced harness)
1. dispatcher drives stages in exact order `host stack db drupal worker`
   (community) — stage handlers are stubbed with recorders; asserts the loop
   order and that exactly five stages run.
2. `run_install_stage` passes the stage name through to its handler.

### Block 2a — Behaviour preservation (real handlers)
3. real handlers: `stack`→`setup_stack` once, `drupal`→`install_env` per env, in
   legacy order (sequential). `setup_stack`/`install_env`/`warn`/`log`/`free` are
   stubbed; asserts the emitted sequence is exactly `setup_stack`,
   `install_env:prod`, `install_env:stage` (host/db/worker contribute nothing).
4. real handlers: `drupal` handler preserves the low-RAM downgrade
   (`PARALLEL_INSTALL=true` + RAM < 6000MB → sequential + the "forcing sequential
   install" warning; no "Parallel install" line).

### Block 2b — Append-only stage guard (alignment §4.5 part 1)
5. community `PROFILE_INSTALL_STAGES` is exactly `(host stack db drupal worker)`.
6. append-only guard: no profile REPLACES a community stage — scans
   `profiles/*.profile`, skips `community.profile`, flags any bare
   `PROFILE_INSTALL_STAGES=(` reassignment (vs the allowed `+=`). Mirrors the
   offenders-collection shape of the sibling-scope audit in
   `tests/test_d0_dispatch.bats`.
7. append-only guard: `community.profile` defines the base list via exactly one
   bare assignment and does not also append to itself.

### Block 3 — Resolver correctness
8. `resolve_install_stage` returns `actools::install::stage_<stage>` for each
   community stage.
9. `resolve_install_stage` defaults to the community base handler when
   `ACTOOLS_PROFILE` is unset.
10. `resolve_install_stage` on an unknown profile WARNs to stderr and falls back
    to the community base handler (documented fail-soft asymmetry).
11. `run_install_stage` fails loudly when a stage resolves to an undefined
    handler (uses the `test` profile → `test_stack`, which is not defined for
    install stages) — never silently skips an install step.
12. `resolve_install_stage` returns `plus_<stage>` under `community-plus`
    (forward-looking append scaffolding; not exercised on the live path in P0-D).

---

## Commands run and results

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# Baseline (before any change)
bats tests/generated/golden_drift_test.bats                                  # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats     # 76/76

# Syntax (all shell)
bash -n actools.sh                                                           # OK
bash -n cli/actools                                                          # OK
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n  # all OK

# After changes
bats tests/generated/golden_drift_test.bats                                  # 6/6 (byte-identical)
bats tests/installer/dispatch_stages_test.bats                               # 12/12 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats     # 88/88 (76 + 12)
```

Overall across golden + regression + new: **94/94 PASS.**

---

## Behaviour-preservation evidence

| Check | Result |
|---|---|
| Golden drift before change | 6/6 |
| Golden drift after change | 6/6 (byte-identical; no generator touched) |
| Stage order = `host stack db drupal worker` | asserted (test 1) |
| `stack` → `setup_stack` exactly once | asserted (test 3) |
| `drupal` → per-env `install_env` loop, legacy order | asserted (test 3) |
| Low-RAM downgrade preserved in handler | asserted (test 4) |
| `setup_stack` range 569–1028 unchanged | re-verified; `_assert_fn_range` holds |
| `setup_cli` range 1247–1528 unchanged | re-verified; `_assert_fn_range` holds |
| Existing 76-test regression | 76/76, unchanged |

---

## Limitations

- The stage-order and behaviour tests stub `setup_stack`/`install_env` (and the
  RAM probe via a `free` shim); they verify the dispatcher's call sequence and
  the handler wiring, not a live container build. End-to-end install coverage
  remains the e2e workflow's responsibility.
- The `db` vs `drupal` split is cosmetic in P0-D: DB creation runs inside the
  `drupal` handler's `install_env` loop and the `db` handler is a no-op. This is
  a flagged judgment call; the real split is P0-G. Both arrangements keep the
  golden net and the stage-order test green.
- The `community-plus`/`test` resolver branches are forward-looking scaffolding
  and are not exercised on the live install path in this phase.

---

## Cross-references

- Ledger: `docs/runbooks/PHASE0_LEDGER.md` — Entry 009.
- Authority map: `docs/architecture/runtime-authority-map.md` — install-stage
  orchestration + resolver-layer rows.
- Release note: `docs/releases/P0-D-install-stage-dispatcher.md`.
- Golden net (the gate): `docs/tests/P0-C-golden-behavior-capture.md`,
  `tests/generated/golden_drift_test.bats`.
- Handoff: `docs/runbooks/HANDOFF-P0-D.md`.
