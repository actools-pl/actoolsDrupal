# P0-I Fake-Profile End-to-End + CI Hardening — Test Report

Branch: `phase0/P0-I-fake-profile-e2e`
Phase: P0-I — Fake-profile end-to-end + CI hardening
Ledger: Entry 014

## Summary

P0-I delivers the end-to-end test the acceptance criteria call for — "e2e
exercises **default + a stub test profile**" and "fake profile exercises
**every dispatch point**" — and closes the two outstanding CI gaps the
runtime-authority-map flagged as P0-I scope (`actools.sh` never shellchecked;
`e2e.yml` install never driven through a non-default profile).

The e2e is a **hermetic harness for the dispatch SEAMS**, which is what Phase 0
hardened — not the Drupal install. It loads the **real** `profiles/test.profile`
(new this phase, loadable, not only a bats fixture), sets `ACTOOLS_PROFILE=test`,
and drives **every dispatch point** through the **real** `installer/dispatch.sh`
+ `installer/profile.sh` + the real surfaces, asserting a uniquely-named marker
per seam. The full-install e2e already exists for `community` (`e2e.yml`'s
`fresh-install`); a "VM-live" fake-profile install would force exactly the two
things Phase 0 deliberately scoped out — routing the install spine through the
selected profile (deferred), and a full Drupal install driven by stub handlers
(which cannot produce a working site) — so hermetic is the correct shape of
"e2e" here, and is why **`actools.sh` is not touched**.

This phase **adds tests and CI**; it does **not** change any runtime behaviour.
`installer/dispatch.sh`, `installer/profile.sh`, the surfaces, and `actools.sh`
are byte-identical. The `community` profile remains byte-identical: golden drift
is **6/6** with no fixture modified, and the existing behaviour suites are
unchanged. The marker writes in the reused fixture stubs are **guarded by
`ACTOOLS_MARKER_DIR`** (a no-op when unset, and at call time only), so the D-0
and P0-H suites that source those stubs are unaffected.

## Scope — what changed, what did not

New (4 files):

- `profiles/test.profile` — the loadable test-only seam-exercise profile. It
  inherits the community base via `source "${INSTALL_DIR}/profiles/community.profile"`
  and **appends** with `+=` (so it passes the append-only stage guard), declares
  one extra in every profile array, and turns on both governance flags. It ships
  no real features; every handler it routes to is a marker stub. `community`'s
  live install never selects it (selection is deferred; `main()` sources
  `community.profile` directly), so shipping it is inert for community operators.
- `tests/test_p0i_fake_profile_e2e.bats` (13 tests) — the **single e2e
  artifact**, invoked from both workflows (see "CI" below).
- `tests/fixtures/profiles/test/stage_handlers.sh` — `test_host`…`test_worker`
  + `test_seam` install-stage marker stubs.
- `tests/fixtures/profiles/test/commands/seam_feature.sh` — a generic
  feature-handler Tier-1 override (proves `resolve_feature_handler` resolves an
  arbitrary feature, not just `doctor_deep`).

Extended (guarded marker writes added; sentinels + exit codes preserved):
`tests/fixtures/profiles/test/manifest.sh`,
`tests/fixtures/profiles/test/commands/doctor_deep.sh`,
`tests/fixtures/profiles/test/plus_preflight_check.sh`,
`tests/fixtures/profiles/test/plus_handoff_section.sh`,
`tests/fixtures/profiles/test/plus_doctor_check.sh`.

CI (2 files): `.github/workflows/lint.yml` (bats job → full recursive suite;
shellcheck job → `actools.sh` added with documented exclusions) and
`.github/workflows/e2e.yml` (tee exit-masking fixed on the install step; new
hermetic `fake-profile-e2e` job).

Test (1 file): `tests/test_d0_dispatch.bats` — the §4.4 sibling-scope audit is
**preserved** and a companion **resolver-bypass audit** is added (now 49 tests).

Not changed (verified byte-identical): `actools.sh`, `installer/dispatch.sh`,
`installer/profile.sh`, `installer/preflight.sh`, `installer/handoff.sh`,
`installer/init.sh`, `installer/output.sh`, `cli/commands/doctor.sh`,
`cli/commands/doctor_deep.sh`, and all six golden fixtures.

## The dispatch-point → marker → assertion map (completeness bar)

Every live dispatch point under `ACTOOLS_PROFILE=test`, the marker it writes, and
where it is asserted. This is the exhaustive contract the e2e proves.

| Dispatch point | Path through the seam | Handler | Marker | Asserted in |
|---|---|---|---|---|
| install stage `host` (inherited) | `run_install_stage` → `resolve_install_stage` → `test_host` | `stage_handlers.sh` | `stage_host.marker` | integration + `install-stage` tests |
| install stage `stack` (inherited) | … → `test_stack` | `stage_handlers.sh` | `stage_stack.marker` | integration |
| install stage `db` (inherited) | … → `test_db` | `stage_handlers.sh` | `stage_db.marker` | integration |
| install stage `drupal` (inherited) | … → `test_drupal` | `stage_handlers.sh` | `stage_drupal.marker` | integration |
| install stage `worker` (inherited) | … → `test_worker` | `stage_handlers.sh` | `stage_worker.marker` | integration |
| **install stage `seam` (APPENDED)** | … → `test_seam` | `stage_handlers.sh` | `stage_seam.marker` | integration + append-only test |
| feature handler (generic) | `resolve_feature_handler seam_feature` (Tier-1) → source → `run_seam_feature` | `commands/seam_feature.sh` | `feature_seam.marker` | integration + feature-handler test |
| doctor deep handler | `doctor --deep` → `resolve_feature_handler doctor_deep` (Tier-1) → `run_doctor_deep` | `commands/doctor_deep.sh` | `doctor_deep.marker` (+ exit 7 + sentinel) | integration + doctor test |
| preflight extra (resolved) | `run_preflight` → `resolve_profile_check "preflight"` → `test_preflight_check` | `plus_preflight_check.sh` | `preflight_check.marker` | integration + preflight test |
| preflight extra (unknown `missing`) | `run_preflight` → declared, no handler → **hard FAIL (exit 1)** | — | **no marker** (failure path) | preflight test |
| handoff section | `run_handoff` → `*)` → `resolve_handoff_section` → `test_handoff_section` | `plus_handoff_section.sh` | `handoff_section.marker` | integration + handoff test |
| init field + governance | `run_init --profile test` — **behavioural** (init dispatches no handler) | — | **no marker**: success → exit 0 + `ACTOOLS_PROFILE=test` persisted + extra/identity **not** persisted; missing actor/ticket → exit 1 | init test + failure-path test |

Deliberately **not** a dispatch point: the per-check `PROFILE_DOCTOR_EXTRA` loop
(deferred at P0-H Entry 013 — `resolve_doctor_check` exists and is tested at the
resolver level, but no Phase-0 profile defines doctor extras). `test.profile`
keeps `PROFILE_DOCTOR_EXTRA=()`; doctor's live dispatch point is the deep handler
above. `plus_doctor_check.sh` is retained for the resolver-token tests and its
marker is intentionally **not** part of this map (no live consumer).

## Failure paths proved

- Unknown profile → `run_init --profile definitely-not-a-profile` → **exit 3**,
  `actools.env` not written.
- Governance-requiring profile without identity → `run_init --profile test`
  (no `--actor-id`/`--change-ticket`) → **exit 1**, `actools.env` not written.
- Preflight extra declared with no handler (`missing`) → **hard FAIL (exit 1)**,
  no marker, `print_skip` explicitly absent.

## Tests added — `tests/test_p0i_fake_profile_e2e.bats` (13)

1. **the integration test** — drives the stage loop + the generic feature
   resolver + preflight + handoff + `doctor --deep` in one run, then asserts all
   **ten** handler markers (the completeness bar). On a missing marker it dumps
   the marker directory for the CI log.
2. install-stage: every stage resolves to `test_<stage>` and fires.
3. install-stage **append-only**: base stages still present (`host stack db
   drupal worker seam`) and `seam` reaches `test_seam`.
4. feature-handler: `resolve_feature_handler` resolves a generic feature to the
   Tier-1 override path and running it writes the marker.
5. preflight: resolved extra runs (marker) and the unknown extra **hard-fails**
   (exit 1; no `SKIP`).
6. doctor `--deep`: Tier-1 override resolved + run (marker, sentinel, **exit 7**);
   the built-in "not available in this edition" gate is suppressed.
7. handoff: profile section resolves through `*)` to its handler (marker).
8. init: test profile succeeds with governance flags; `ACTOOLS_PROFILE=test`
   persisted; the extra field and the identity values are **not** persisted.
9. failure path: unknown profile → exit 3, nothing persisted.
10. failure path: test profile missing actor/ticket → exit 1, nothing persisted.
11. **community routes through NONE of the P0-I markers** — the `test_*`
    handlers are defined in-shell (so a wrong resolution *would* write a marker,
    making the check bite), the surfaces are driven under `community`, and the
    marker directory must end empty.
12. `profiles/test.profile` is pure data — sourced via the loader contract
    (`INSTALL_DIR` set, as the real loader guarantees) it produces no output and
    creates no files. (The clean-subshell negative control in
    `test_d0_dispatch.bats` proves this harness shape bites.)
13. **exec-bit standing guard** — `actools.sh` is `-x`, and (inside a git work
    tree) its committed index mode is `100755`. This is the P0-G regression
    guard; it rides the suite, so it now gates every PR.

### Why `test.profile` is sourced with `INSTALL_DIR` in test 12

`test.profile` is append-only, which requires inheriting the base via
`source "${INSTALL_DIR}/profiles/community.profile"` (the documented downstream
pattern). That source needs `INSTALL_DIR`, which the profile loader always sets.
The self-contained governance fixtures (`fake-actor`/`fake-ticket`) do **not**
inherit, which is why they pass the no-`INSTALL_DIR` clean-subshell check; an
inheriting profile is verified the way it is actually loaded. No existing test
sources `profiles/*.profile` without `INSTALL_DIR`, so adding `test.profile` to
`profiles/` is safe; only the append-only guard scans `profiles/*.profile`, and
`+=` passes it.

## CI hardening

### Suite-in-CI (the fast PR merge gate) — `lint.yml`

The bats job ran 6 files; it now runs `bats --print-output-on-failure -r tests/`
— the **full recursive suite** (158 tests), auto-discovering future phase
suites. This makes the fake-profile e2e, the golden community-drift gate, the
append-only stage guard, and the resolver-bypass + exec-bit guards all gate on
every PR. Because the e2e is a **suite member**, the lint gate and the `e2e.yml`
job invoke the **same single artifact** — no divergent copies of the assertions.

### `actools.sh` shellcheck — `lint.yml`

`actools.sh` (the operator entry point, 871 lines, never previously linted) is
added with `--exclude=SC2034,SC2015,SC2164,SC1091`. The bare finding set
(default severity) is exactly seven, all established sibling idioms: one SC2034
(a `set -a`/indirect-use var that looks unused), five SC2015 (the `A && B || C`
log-or-continue idiom), one SC1091 (a dynamic `source` path the linter cannot
follow). These match the exclusions used across the existing shellcheck lines.
Per the flag-don't-edit guardrail, `actools.sh` is **not** modified to satisfy
the linter — idioms are excluded, not rewritten. (`--enable=all` would surface
optional checks like SC2250/SC2312 that the siblings do not enable; matching
sibling style means default checks + documented exclusions.)

### `e2e.yml` — tee fix + hermetic fake-profile job

- **tee exit-masking fixed.** The install step piped the installer to `tee`, so
  the step's exit status was `tee`'s (0), masking a failed install. It now uses
  `set -o pipefail` and an `if !` guard (errexit-safe in a condition) so the
  installer's own non-zero propagates; the `install.log` artifact upload is
  unchanged.
- **new `fake-profile-e2e` job** (honours spec §S2: "add the fake-downstream-
  profile e2e to `e2e.yml`"). It runs the single e2e artifact hermetically
  (`bats … tests/test_p0i_fake_profile_e2e.bats`), needs no VM and no secrets,
  runs on every push, captures a log via `tee`, and uploads it on completion
  (artifacts retained on failure). The expensive Hetzner `fresh-install` job and
  the workflow triggers are unchanged.

### Resolver-bypass audit — `test_d0_dispatch.bats`

The §4.4 sibling-scope audit is preserved; a companion test encodes LOCKED §10
Risk 2: no file other than the resolver (`installer/dispatch.sh`) may
`source`/`.` a `${INSTALL_DIR}/modules/plus_*` path. The baseline has no such
line, so it passes today and trips if a hardcoded plus-path bypass is added in
Phases 1–6.

## Community byte-identity — behaviour suites + drift

`community`'s resolvers short-circuit to empty, so no P0-I marker is ever written
on the community path (test 11), and the community behaviour suites + golden
drift are unchanged. No golden fixture was modified.

## Commands run

```bash
# Baseline (post-P0-H) and after edits:
bats tests/test_p0i_fake_profile_e2e.bats     # 13/13 (new)
bats tests/test_d0_dispatch.bats              # 49/49 (48 + resolver-bypass audit)
bats tests/generated/golden_drift_test.bats   # 6/6   (community byte-identical)
bats -r tests/                                # 158/158 (whole tree)

# Entry-point lint + syntax (no actools.sh edits):
bash -n actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh   # clean

# Loadable profile sanity:
INSTALL_DIR="$PWD" ACTOOLS_PROFILE=test bash -c 'source installer/profile.sh; profile_install_stages'
```

## Result

PASS — **158/158** across the tree (144 baseline + 13 P0-I e2e + 1 resolver-bypass
audit). New e2e green; community golden drift **6/6**; `shellcheck actools.sh`
clean with the documented exclusions; `actools.sh` and all seam/runtime code
byte-identical.

## Limitations / notes

- The e2e is **hermetic by design** (it exercises the seams, not a live Drupal
  install). The live full-install path is covered for `community` by the
  `fresh-install` job; a fake-profile *VM* install is out of scope because it
  would require the deferred install-spine profile selection and stub handlers
  that cannot build a working site.
- Markers are an internal temp-dir mechanism asserted and torn down within each
  test; the retained CI artifact on failure is the bats log (which, via the
  integration test's dump-on-failure, lists which markers fired).
- `profiles/README.md` is left unchanged (out of the allowed scope); the loadable
  `test.profile` is documented here and in the ledger entry.
