# Handoff — P0-I · Fake-Profile End-to-End + CI Hardening

## Repository state

Branch: `phase0/P0-I-fake-profile-e2e`
Commit SHA: baseline `44aeed3` (post-P0-H export of `e4db126`); the P0-I change
set is applied on top (operator records the merge SHA at apply time).
Working tree clean? no — the P0-I change set is the deliverable to apply/commit.
Zip/package name if applicable: P0-I output (this change set + docs)

## Task completed

Added the **fake-profile end-to-end** test (acceptance #8/#9; LOCKED §11
build-trigger #1) and closed the two P0-I CI gaps. The e2e is a **hermetic
harness for the dispatch seams** — it loads the **real, loadable**
`profiles/test.profile`, sets `ACTOOLS_PROFILE=test`, and drives **every dispatch
point** through the real `installer/dispatch.sh` + `installer/profile.sh` + the
real surfaces, asserting a uniquely-named marker per seam. The same single bats
file is invoked from **both** workflows (the `lint.yml` suite as the fast PR merge
gate, and a dedicated hermetic job in `e2e.yml` honouring §S2). CI now runs the
**full** bats suite, **shellchecks `actools.sh`**, **fixes the `e2e.yml` `tee`
exit-masking**, and the §4.4 audit gains a **resolver-bypass** companion. **No
runtime change; `actools.sh` not edited; `community` byte-identical.**

## Files changed

- `profiles/test.profile` — **new.** Loadable test-only seam profile; inherits the
  community base via `source` and **appends** with `+=` (passes the append-only
  guard); one extra in every profile array; both governance flags on. Inert for
  community operators (never selected by the live install).
- `tests/test_p0i_fake_profile_e2e.bats` — **new** (13 tests). The single e2e
  artifact (integration test asserting all 10 handler markers; granular per-seam
  tests; failure paths; exec-bit guard; community-routes-through-NONE).
- `tests/fixtures/profiles/test/stage_handlers.sh` — **new.** Install-stage marker
  stubs (`test_host`…`test_worker`, `test_seam`).
- `tests/fixtures/profiles/test/commands/seam_feature.sh` — **new.** Generic
  feature-handler Tier-1 override.
- `tests/fixtures/profiles/test/manifest.sh`,
  `tests/fixtures/profiles/test/commands/doctor_deep.sh`,
  `tests/fixtures/profiles/test/plus_preflight_check.sh`,
  `tests/fixtures/profiles/test/plus_handoff_section.sh`,
  `tests/fixtures/profiles/test/plus_doctor_check.sh` — **extended** with
  `ACTOOLS_MARKER_DIR`-guarded marker writes (no-op when unset; call time only).
- `.github/workflows/lint.yml` — bats job → `bats --print-output-on-failure -r
  tests/`; shellcheck job → `actools.sh` with `--exclude=SC2034,SC2015,SC2164,SC1091`.
- `.github/workflows/e2e.yml` — install-step `tee` exit-masking fixed; new
  hermetic `fake-profile-e2e` job invoking the single e2e artifact.
- `tests/test_d0_dispatch.bats` — §4.4 sibling-scope audit preserved; companion
  **resolver-bypass audit** added (48 → 49 tests).
- Docs: `docs/tests/P0-I-fake-profile-e2e.md`,
  `docs/releases/P0-I-fake-profile-e2e.md`, `docs/CHANGELOG.md`,
  `docs/runbooks/PHASE0_LEDGER.md` (Entry 014),
  `docs/architecture/runtime-authority-map.md`, this handoff.

## Files not changed but relevant

- `actools.sh` — **byte-identical** (flag-don't-edit; hermetic e2e needs no edit).
  Now shellchecked in CI with documented idiom exclusions.
- `installer/dispatch.sh`, `installer/profile.sh`, `installer/preflight.sh`,
  `installer/handoff.sh`, `installer/init.sh`, `installer/output.sh`,
  `cli/commands/doctor.sh`, `cli/commands/doctor_deep.sh` — byte-identical.
- All six golden fixtures, `profiles/community.profile` — unchanged (drift 6/6).
- `profiles/README.md` — left unchanged (out of allowed scope); `test.profile`
  documented in the test report + ledger instead.

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none (P0-I adds a behavioural init test only; `init.sh` byte-identical) |
| Profile loading | none to the loader; a loadable `test.profile` is **added** to `profiles/` (test-only, never selected by the live install) |
| Install stages | none (`dispatch.sh` byte-identical; the test profile's stages route to test stubs only in the harness) |
| CLI | none (`cli/actools` untouched) |
| Generated files | none (drift 6/6) |
| Preflight | none (`preflight.sh` byte-identical) |
| Doctor | none (`doctor.sh` byte-identical) |
| Handoff | none (`handoff.sh` byte-identical) |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | unchanged |
| Caddyfile | unchanged |
| my.cnf | unchanged |
| Dockerfiles | unchanged |
| CLI | not touched |

## Tests run

```bash
bats tests/test_p0i_fake_profile_e2e.bats     # 13/13 (new)
bats tests/test_d0_dispatch.bats              # 49/49 (48 + resolver-bypass audit)
bats tests/generated/golden_drift_test.bats   # 6/6   (community byte-identical)
bats -r tests/                                # 158/158 (whole tree)

bash -n actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh   # clean
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/lint.yml')); yaml.safe_load(open('.github/workflows/e2e.yml'))"  # valid YAML
```

## Test result

PASS — **158/158** across the tree (144 baseline + 13 e2e + 1 resolver-bypass
audit); new e2e green; community golden drift **6/6**; `shellcheck actools.sh`
clean with documented exclusions; both workflows valid YAML.

## Docs updated

`docs/tests/P0-I-fake-profile-e2e.md` (the dispatch-point→marker→assertion table +
what CI now gates), `docs/architecture/runtime-authority-map.md` (resolver-bypass
+ CI-gap bullets updated; test-surface count 144→158; P0-I answer added).

## Changelog / release notes updated

`docs/CHANGELOG.md` (new P0-I [Unreleased] section) and
`docs/releases/P0-I-fake-profile-e2e.md` (release note with `## Rollback`).

## Ledger entry

Entry number: **014** (`docs/runbooks/PHASE0_LEDGER.md`). Includes the recorded
**scope decision** (hermetic, one artifact, both workflows) for the Conductor to
ratify alongside the verdict.

## Known risks

- The e2e is hermetic by design (seams, not a live install). Live full-install is
  covered for `community` by the `fresh-install` job; a fake-profile *VM* install
  is out of scope (would need the deferred install-spine selection + stub handlers
  that cannot build a working site).
- Shipping `profiles/test.profile` is mitigated: test-only, never selected by the
  community install, and the only scanner of `profiles/*.profile` (the append-only
  guard) passes it (`+=`).

## Blockers

None.

## Exact next allowed task

Phase 0 **closure review** (LOCKED §11): confirm green CI on the P0-I PR (the
build-trigger #1 conditions — merged PRs, green CI, fake-downstream-profile e2e —
are now implemented pending review), then proceed to the closure decision and the
community-plus Phase-1 unblock evaluation.

## Explicitly forbidden scope for next task

No real community-plus feature work (stubs only); no runtime behaviour change; do
**not** edit `actools.sh` (flag instead); no new `modules/plus_*` live code; do
not modify any golden fixture or `community.profile`.

## Review Gate notes

- **Completeness bar:** the dispatch-point→marker→assertion table in the test
  report enumerates every live dispatch point; the integration test asserts all
  **ten** handler markers in one run, and granular tests pinpoint a broken seam.
  Init + governance are proved behaviourally (no handler to mark).
- **Scope decision to ratify (Entry 014 / release note):** hermetic harness, one
  artifact, invoked from both workflows; `actools.sh` untouched because hermetic.
- **Cross-model (Opus) review** is pending; this window did not self-approve.
