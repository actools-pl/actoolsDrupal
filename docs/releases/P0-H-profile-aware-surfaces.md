# Release note — P0-H · Profile-Aware init, preflight, doctor, and handoff

Branch: `phase0/P0-H-profile-aware-surfaces`
Phase: P0-H — Profile-aware init, preflight, doctor, and handoff
Ledger: Entry 013

## Summary

P0-H wires the three remaining operator surfaces — `doctor`, `preflight`, and
`handoff` — through the resolver primitives that P0-E built, so a non-default
profile can supply its own deep-doctor handler, preflight checks, and handoff
sections without any hardcoded conditionals in community code. `init` was
already made profile-aware in P0-E; P0-H confirms it with a fake-profile test
and does not modify it.

This phase **consumes** the seam; it does **not** change it. `installer/dispatch.sh`
is byte-identical. The `community` profile remains **byte-identical** in
behaviour: its resolvers short-circuit to empty, so doctor falls back to the
built-in gate, preflight runs no extras, and handoff's catch-all never fires.
Golden drift is **6/6** with no fixture modified, and the existing community
behaviour suites are unchanged.

## Scope — what changed, what did not

Changed (3 files):

- `cli/commands/doctor.sh` — `doctor --deep` resolves its handler via
  `actools::dispatch::resolve_feature_handler doctor_deep` and falls back to the
  built-in `cli/commands/doctor_deep.sh` gate. The env file and `dispatch.sh`
  are sourced at the top of `run_doctor` so the resolver is available to the
  gate.
- `installer/preflight.sh` — `PROFILE_PREFLIGHT_EXTRA` entries route through
  `actools::dispatch::resolve_profile_check "preflight"`; resolved handlers run,
  and an unknown check is a hard fail for a non-default profile.
- `installer/handoff.sh` — the silent catch-all routes non-built-in sections
  through `actools::dispatch::resolve_handoff_section`; resolved handlers render,
  and an unresolved section emits a visible, non-fatal notice.

New (3 files): `tests/fixtures/profiles/fake-surfaces.profile`,
`tests/fixtures/profiles/test/commands/doctor_deep.sh`, and
`tests/test_p0h_dispatch.bats` (9 tests).

Not changed (verified byte-identical): `actools.sh`, `installer/dispatch.sh`,
`installer/init.sh`, `installer/profile.sh`, `installer/output.sh`, and
`cli/commands/doctor_deep.sh`. `modules/audit/audit.sh` is out of scope (its
`--deep` is a mode flag, not a hardcoded source). No golden fixture was modified.

## Generated-file status (generated-file contract)

No generated file is touched. `my.cnf`, `Dockerfile.{caddy,php,worker}`,
`Caddyfile`, and `docker-compose.yml` are byte-identical — golden drift **6/6**.
The CLI (`cli/actools`) is untouched; `cli_authority_test.bats` is 14/14.

## Doctor — deep handler wired; `PROFILE_DOCTOR_EXTRA` loop deliberately deferred

The doctor surface is wired at the **deep handler** only. Per the
LOCKED-alignment §4.1 pin (which scopes doctor to replacing the hard
`source doctor_deep.sh` with `resolve_feature_handler`), and to avoid adding
unexercised scaffolding, the per-check `PROFILE_DOCTOR_EXTRA` dispatch loop is
**not** added in this phase. Recorded verbatim:

> doctor deep handler wired via `resolve_feature_handler` + baseline fallback;
> per-check `PROFILE_DOCTOR_EXTRA` dispatch loop deliberately deferred —
> `resolve_doctor_check` primitive exists and is tested, consumer loop to be
> added when a profile defines doctor extras (community-plus/Phase-1). Spec #3's
> "deep/extra" is satisfied at the deep handler; the extra loop has no consumer
> in Phase 0.

Rationale: `doctor.sh` has no extra loop today, so adding one would be creating
new structure rather than wiring existing structure (the asymmetry with
`preflight`, whose extra loop already exists). Nothing populates
`PROFILE_DOCTOR_EXTRA` in Phase 0 — community does not define it and the only
consumer would be community-plus — so a dispatch loop over an empty field would
be dead code, which is exactly the anti-pattern this effort exists to remove.
The seam for the future is already present: `resolve_doctor_check` exists in
`dispatch.sh` and is tested at the resolver level
(`tests/test_d0_dispatch.bats`); only the consumer loop is deferred.

## Handoff — resolved renders, unresolved is a visible notice (asymmetry with preflight)

`preflight` and `handoff` resolve extras the same way but treat an **unresolved**
item differently, by design:

- **preflight** is a readiness gate. A check a profile declares but cannot run is
  a safety-relevant gap, so an unresolved extra is a **hard FAILURE**
  (`print_fail` + `print_fix`, and it counts toward the non-zero exit).
- **handoff** is a post-install **display** surface (a summary panel). An
  unresolved section is not a safety condition, so it is reported with a
  **visible, non-fatal notice** and the summary continues. `run_handoff` keeps
  its success contract (it does not gain a failure return code).

Neither contract (`cli-authority-contract.md`, `phase0-seam-contract.md`) makes
an unresolved handoff section fatal, and the prompt scoped handoff to "fail/skip
per the contract" (vs preflight's explicit "fail"). The asymmetry is therefore a
deliberate, documented choice, not an inconsistency.

## Profile preflight-extra handler convention

A profile that supplies a preflight-extra handler is expected to **print its own
OK/WARN/FAIL status line** and **return non-zero to register a failure** (the
surface treats a non-zero return as a failure and increments the failure count).
This mirrors how the built-in inline checks behave.

## Verification

```bash
export PATH="$PWD/../bats-core-1.11.0/bin:$PATH"

bats tests/test_p0h_dispatch.bats            # 9/9 (new)
bats tests/installer/doctor_test.bats        # 5/5  (unchanged)
bats tests/installer/preflight_test.bats     # 6/6  (unchanged)
bats tests/installer/init_profile_test.bats  # 10/10 (unchanged)
bats tests/test_d0_dispatch.bats             # 48/48 (unchanged)
bats tests/generated/golden_drift_test.bats  # 6/6  (community byte-identical)
bats -r tests/                               # 144/144

bash -n actools.sh
for f in $(find installer cli core modules -name '*.sh'); do bash -n "$f"; done
shellcheck installer/preflight.sh installer/handoff.sh installer/init.sh \
           cli/commands/doctor.sh installer/dispatch.sh
```

Result: **144/144** across the tree. shellcheck reports only pre-existing
info-level `SC2012` (`ls -t` on untouched lines in `doctor.sh` and `handoff.sh`)
and a pre-existing `SC2034` in the unedited `init.sh`; no new findings in the
edited regions.

## Rollback

Revert the P0-H change set. It is confined to three surface files
(`cli/commands/doctor.sh`, `installer/preflight.sh`, `installer/handoff.sh`),
three new test-only files (`tests/fixtures/profiles/fake-surfaces.profile`,
`tests/fixtures/profiles/test/commands/doctor_deep.sh`,
`tests/test_p0h_dispatch.bats`), and docs. **No golden fixture and no shipped
non-test code outside the three surfaces was modified.**

Reverting restores the hard `source doctor_deep.sh` in the doctor deep gate, the
`print_skip` for preflight extras, and the silent `*)` in handoff.

Operational notes for a rollback:

- **No data migration and no container impact.** No generated artifact changed,
  so a revert has no effect on `my.cnf`, the Dockerfiles, the `Caddyfile`,
  `docker-compose.yml`, or container state.
- **`community` deployments are unaffected either way.** Behaviour is
  byte-identical before and after P0-H for the community profile (the resolvers
  short-circuit to empty), so a revert changes nothing observable for community
  operators; it only removes the seam consumption that a future non-default
  profile would rely on.
- The deferred `PROFILE_DOCTOR_EXTRA` loop is unaffected by a rollback (it was
  never added).
