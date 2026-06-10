# Release note — P0-I · Fake-Profile End-to-End + CI Hardening

Branch: `phase0/P0-I-fake-profile-e2e`
Phase: P0-I — Fake-profile end-to-end + CI hardening
Ledger: Entry 014

## Summary

P0-I adds the end-to-end test the acceptance criteria require — a **loadable**
fake downstream profile that drives **every dispatch point** — and closes the two
CI gaps the runtime-authority-map flagged as P0-I scope (`actools.sh` had never
been shellchecked; `e2e.yml`'s install was never driven through a non-default
profile).

The e2e is a **hermetic harness for the dispatch SEAMS** — which is what Phase 0
hardened, not the Drupal install. It loads the real `profiles/test.profile`, sets
`ACTOOLS_PROFILE=test`, and drives every dispatch point through the real
`installer/dispatch.sh` + `installer/profile.sh` + the real surfaces, asserting a
marker per seam. The full-install e2e already exists for `community`. A "VM-live"
fake-profile install would force exactly the two things Phase 0 scoped out —
routing the install spine through the selected profile (deferred) and a full
Drupal install driven by stub handlers (which cannot produce a working site) — so
hermetic is the right shape of "e2e" here, and is **why `actools.sh` is not
touched** (the flag-don't-edit guardrail is honoured by the hermetic
interpretation, not bypassed by it).

This phase **adds tests and CI**; it does **not** change the seam or any runtime
behaviour. `installer/dispatch.sh`, `installer/profile.sh`, the surfaces, and
`actools.sh` are **byte-identical**. The `community` profile remains
**byte-identical**: golden drift is **6/6** with no fixture modified, and the
behaviour suites are unchanged.

## Scope decision (recorded for review)

The coding window surfaced and resolved a real tension between the phase spec
(§S2: "add the fake-downstream-profile e2e to `e2e.yml`") and the reconciliation
note (§S2-vs-prompt). Resolution, approved by the Conductor:

> Go with the **hermetic** harness, and put it in **both** places via **one
> artifact**. The seams are what Phase 0 hardened, so a harness that sources the
> real `dispatch.sh` + `profile.sh`, loads the real `profiles/test.profile`,
> drives every dispatch point under `ACTOOLS_PROFILE=test`, and asserts every
> marker **is** the end-to-end test for the seams. Add the hermetic job to
> `e2e.yml` (honouring §S2 and keeping the conceptual home right) **and** let the
> same bats file ride the `lint.yml` suite as the fast PR merge gate — two
> different guarantees (the suite gate and the e2e-workflow coverage), not
> wasteful duplication. To avoid drift, the assertions live in exactly one file,
> invoked from both workflows. The `actools.sh` guardrail stays — going hermetic
> is precisely why it does not need to be touched.

## Scope — what changed, what did not

New (4 files):

- `profiles/test.profile` — loadable, test-only seam-exercise profile. Inherits
  the community base via `source` and **appends** with `+=` (passes the
  append-only stage guard); declares one extra in every profile array; turns on
  both governance flags. Ships no real features; `community`'s live install never
  selects it (selection is deferred — `main()` sources `community.profile`
  directly), so it is inert for community operators.
- `tests/test_p0i_fake_profile_e2e.bats` (13 tests) — the single e2e artifact.
- `tests/fixtures/profiles/test/stage_handlers.sh` — install-stage marker stubs.
- `tests/fixtures/profiles/test/commands/seam_feature.sh` — a generic
  feature-handler Tier-1 override.

Extended (guarded marker writes; sentinels + exit codes preserved):
`tests/fixtures/profiles/test/manifest.sh`, `.../commands/doctor_deep.sh`,
`.../plus_preflight_check.sh`, `.../plus_handoff_section.sh`,
`.../plus_doctor_check.sh`. The marker write is **guarded by `ACTOOLS_MARKER_DIR`**
(no-op when unset; at call time only), so the D-0/P0-H suites that source these
stubs are unaffected.

Changed — CI (2 files):

- `.github/workflows/lint.yml` — bats job now runs the **full recursive suite**
  (`bats --print-output-on-failure -r tests/`), and the shellcheck job adds
  `actools.sh` with `--exclude=SC2034,SC2015,SC2164,SC1091` (documented).
- `.github/workflows/e2e.yml` — the install step's **tee exit-masking is fixed**
  (`pipefail` + `if !` guard; `install.log` artifact preserved), and a new
  hermetic **`fake-profile-e2e`** job runs the single e2e artifact (no VM, no
  secrets, runs on every push, log uploaded on completion).

Changed — test (1 file):

- `tests/test_d0_dispatch.bats` — the §4.4 sibling-scope audit is **preserved**;
  a companion **resolver-bypass audit** (LOCKED §10 Risk 2) is added (49 tests).

Not changed (verified byte-identical): `actools.sh`, `installer/dispatch.sh`,
`installer/profile.sh`, `installer/preflight.sh`, `installer/handoff.sh`,
`installer/init.sh`, `installer/output.sh`, `cli/commands/doctor.sh`,
`cli/commands/doctor_deep.sh`, and all six golden fixtures. `profiles/README.md`
is left unchanged (out of the allowed scope; `test.profile` is documented in the
test report and ledger).

## Generated-file status (generated-file contract)

No generated file is touched. `my.cnf`, `Dockerfile.{caddy,php,worker}`,
`Caddyfile`, and `docker-compose.yml` are byte-identical — golden drift **6/6**.
The CLI (`cli/actools`) is untouched; `cli_authority_test.bats` is unchanged.

## What CI now gates (that it did not before)

- The **fake-profile dispatch e2e** — on every PR (via the lint suite) and on
  every push to `main` (via the `e2e.yml` hermetic job).
- **`actools.sh` shellcheck** — the largest live file, previously unlinted.
- The **golden community-drift** gate, the **append-only stage** guard, the
  **resolver-bypass** audit, and the **`actools.sh` exec-bit** standing guard —
  all now run in the PR bats suite (previously only a 6-file subset ran in CI).
- A **failed VM install** in `e2e.yml` now fails the job (previously masked by
  `tee`).

## Verification

```bash
bats tests/test_p0i_fake_profile_e2e.bats     # 13/13 (new)
bats tests/test_d0_dispatch.bats              # 49/49
bats tests/generated/golden_drift_test.bats   # 6/6   (community byte-identical)
bats -r tests/                                # 158/158

bash -n actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh   # clean
```

Result: **158/158** across the tree (144 baseline + 13 e2e + 1 resolver-bypass
audit); community drift **6/6**; `shellcheck actools.sh` clean with the
documented exclusions; no runtime or generated-file change.

## Rollback

Revert the P0-I change set. It is confined to: one loadable test profile
(`profiles/test.profile`), test-only fixtures (`tests/fixtures/profiles/test/*`),
the e2e suite (`tests/test_p0i_fake_profile_e2e.bats`), one test edit
(`tests/test_d0_dispatch.bats`), two CI workflows (`.github/workflows/lint.yml`,
`.github/workflows/e2e.yml`), and docs. **No golden fixture and no shipped
non-test runtime code (including `actools.sh`) was modified.**

Reverting restores: the 6-file CI bats subset, the unlinted `actools.sh`, the
tee-masked install step in `e2e.yml`, and the single (non-extended) §4.4 audit;
and it removes the loadable `test.profile`, the fake-profile e2e, and the
hermetic `fake-profile-e2e` job.

Operational notes for a rollback:

- **No data migration and no container impact.** No generated artifact changed,
  so a revert has no effect on `my.cnf`, the Dockerfiles, the `Caddyfile`,
  `docker-compose.yml`, or container state.
- **`community` deployments are unaffected either way.** Behaviour is
  byte-identical before and after P0-I for the community profile (no runtime
  change at all), so a revert changes nothing observable for community operators;
  it only removes the new test coverage and CI gates.
- A partial rollback is safe and granular: e.g. reverting only the `e2e.yml` job
  or only the `actools.sh` shellcheck line leaves the rest intact, since the
  pieces are independent.
