# P0-H Profile-Aware init, preflight, doctor, and handoff — Test Report

Branch: `phase0/P0-H-profile-aware-surfaces`
Phase: P0-H
Ledger: Entry 013
Release note: `docs/releases/P0-H-profile-aware-surfaces.md`

## Summary

P0-H routes `doctor`, `preflight`, and `handoff` through the P0-E resolvers and
confirms `init` is already profile-aware. The testing goal is two-sided: prove
that a **non-default profile** reaches its handler at every dispatch point, and
prove that the **community profile is byte-identical** (routes through none of
the new paths). Both are met. The whole tree is **144/144** (9 new), golden
drift is **6/6** with no fixture modified, and every pre-existing community
behaviour suite is unchanged.

## Test surface (before → after)

| Suite | Before | After | Δ |
|---|---|---|---|
| `tests/test_d0_dispatch.bats` | 48 | 48 | — |
| `tests/installer/init_test.bats` | 11 | 11 | — |
| `tests/installer/init_profile_test.bats` | 10 | 10 | — |
| `tests/installer/preflight_test.bats` | 6 | 6 | — |
| `tests/installer/doctor_test.bats` | 5 | 5 | — |
| `tests/installer/dispatch_stages_test.bats` | 14 | 14 | — |
| `tests/installer/cli_authority_test.bats` | 14 | 14 | — |
| `tests/core/validate_test.bats` | 11 | 11 | — |
| `tests/core/secrets_test.bats` | 10 | 10 | — |
| **`tests/test_p0h_dispatch.bats`** | — | **9** | **+9** |
| `tests/generated/golden_drift_test.bats` | 6 | 6 | — |
| **Total** | **135** | **144** | **+9** |

No existing test was modified; the community behaviour suites are byte-identical
guards and stay green untouched.

## Tests added — `tests/test_p0h_dispatch.bats` (9)

Every dispatch point named in the seam contract ("fake profile exercises init,
preflight, install stage, doctor, handoff") is covered, plus an explicit
"community routes through none" assertion at each surface:

1. **doctor — override wins.** A Tier-1 profile override
   (`profiles.d/test/commands/doctor_deep.sh`) is resolved by
   `resolve_feature_handler` and run; the sentinel appears and the override's
   exit code (7) propagates; the built-in gate notice is absent.
2. **doctor — community routes through none.** With the override physically
   present but `ACTOOLS_PROFILE=community`, the resolver short-circuits to empty
   and the built-in in-development gate runs (exit 2); the override is ignored.
3. **preflight — resolved + unknown-fails.** A non-default profile with
   `PROFILE_PREFLIGHT_EXTRA=(check missing)` dispatches `check` to its installed
   handler (sentinel `TEST_PREFLIGHT_DISPATCHED:check`) and **hard-fails**
   `missing` (no handler installed); status is 1 (failure), and `missing` is not
   a SKIP.
4. **preflight — community routes through none.** community's empty extras list
   means the loop body never runs; no "Profile check" output appears.
5. **handoff — resolved section.** A non-default profile's extra section is
   resolved by `resolve_handoff_section` and rendered by its handler (sentinel
   `TEST_HANDOFF_DISPATCHED:section`); status 0.
6. **handoff — community routes through none.** community sections all hit
   explicit arms; no dispatch sentinel and no "no handler installed" notice
   appear, and the built-in sections still render.
7. **init — fake-profile extra field.** A profile declaring an extra
   `PROFILE_INIT_FIELDS` entry initializes successfully (exit 0), writes
   `ACTOOLS_PROFILE=test`, and the extra field is **not** persisted (Phase-0
   no-op) — confirming init consumes the field list without breaking.
8. **community routes through none (resolver level).** For `community`, all four
   resolvers (`resolve_feature_handler`, `resolve_profile_check preflight`,
   `resolve_profile_check doctor`, `resolve_handoff_section`) return empty
   (`"|||"`).
9. **fixture hygiene.** `fake-surfaces.profile` sources with no stdout/stderr and
   creates no files — the "variables only" profile contract.

## Community byte-identity — behaviour suites + drift

The three community surface suites and the dispatch suite were captured on the
clean baseline and re-run after the edits, with identical pass counts:

| Suite | Baseline | After |
|---|---|---|
| `doctor_test.bats` | 5 | 5 |
| `preflight_test.bats` | 6 | 6 |
| `init_profile_test.bats` | 10 | 10 |
| `test_d0_dispatch.bats` | 48 | 48 |
| `golden_drift_test.bats` | 6 | 6 |

`golden_drift_test.bats` 6/6 (5 per-variant byte-identity checks + the
"directory contains all 5 variants" check) confirms the six generated files are
unchanged for every variant.

## Commands run

```bash
export PATH="$PWD/../bats-core-1.11.0/bin:$PATH"

# BEFORE (clean baseline) and AFTER edits — identical counts:
bats tests/installer/doctor_test.bats        # 5/5
bats tests/installer/preflight_test.bats     # 6/6
bats tests/installer/init_profile_test.bats  # 10/10
bats tests/test_d0_dispatch.bats             # 48/48
bats tests/generated/golden_drift_test.bats  # 6/6

# New suite + whole tree:
bats tests/test_p0h_dispatch.bats            # 9/9
bats -r tests/                               # 144/144

# Syntax + lint:
bash -n actools.sh
for f in $(find installer cli core modules -name '*.sh'); do bash -n "$f"; done
shellcheck installer/preflight.sh installer/handoff.sh installer/init.sh \
           cli/commands/doctor.sh installer/dispatch.sh
```

## Result

**PASS.** 144/144 across the tree (9 new); community behaviour byte-identical;
golden drift 6/6 with no fixture modified. `bash -n` clean on all shell;
shellcheck reports only pre-existing info-level `SC2012` (`ls -t` on untouched
lines) and a pre-existing `SC2034` in the unedited `init.sh` — no new findings
in the edited regions.

## Limitations / notes

- The init test asserts the surface-level outcome (init succeeds and the extra
  field is not persisted) rather than instrumenting the consumption loop, because
  Phase 0 treats profile-declared extra init fields as a no-op (collected, not
  validated or persisted). This is the honest extent of what is observable until
  a profile actually consumes extra fields (Phase 1).
- The non-default preflight test relies on the unknown-check **failure** to force
  a deterministic non-zero exit (status 1); the base system checks run for real
  in the sandbox but cannot mask a failure, so the assertion is stable. The
  resolved-handler proof is by output sentinel, independent of the noisy base
  checks.
- Profile handler functions are made visible to the surface under test by
  sourcing the stub files in the test shell before `run`; in production the
  profile/spine would supply them. Sourcing the selected profile in the install
  spine is out of P0-H scope (`actools.sh` byte-identical).
- The deferred `PROFILE_DOCTOR_EXTRA` per-check loop has **no** test here by
  design; the underlying `resolve_doctor_check` primitive is already covered in
  `tests/test_d0_dispatch.bats`.
