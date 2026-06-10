# Handoff — P0-H · Profile-Aware init, preflight, doctor, and handoff

## Repository state

Branch: `phase0/P0-H-profile-aware-surfaces`
Commit SHA: applied from the supplied unified diff against `main` (operator records the merge SHA)
Working tree clean? yes (no `.git` in the working snapshot; delivered as full file contents + a unified diff)
Zip/package name if applicable: `actoolsDrupal-main` (extracted working snapshot)

## Task completed

Wired the three remaining operator surfaces through the P0-E resolver
primitives, and confirmed `init` is already profile-aware:

- **doctor** — `doctor --deep` resolves its handler via
  `resolve_feature_handler doctor_deep` (3-tier), with a baseline fallback to
  the built-in `cli/commands/doctor_deep.sh` gate. No hardcoded deep-handler
  path remains.
- **preflight** — `PROFILE_PREFLIGHT_EXTRA` entries route through
  `resolve_profile_check "preflight"`; a resolved+installed handler runs, and an
  unknown check is a **hard fail** for a non-default profile (was a silent skip).
- **handoff** — the silent `*)` routes non-built-in sections through
  `resolve_handoff_section`; a resolved handler renders the section, and an
  unresolved section is a **visible, non-fatal notice**.
- **init** — unchanged (profile-aware since P0-E); a new fake-profile test
  confirms an extra `PROFILE_INIT_FIELDS` entry flows through and is not
  persisted.

`community` is byte-identical (resolvers short-circuit to empty). The per-check
`PROFILE_DOCTOR_EXTRA` dispatch loop is **deliberately deferred** (see Known
risks).

## Files changed

- `cli/commands/doctor.sh` — env + `dispatch.sh` sourced at the top of
  `run_doctor`; `--deep` gate resolves via `resolve_feature_handler` with
  baseline fallback to the built-in gate; header comment updated.
- `installer/preflight.sh` — profile-extra loop routes through
  `resolve_profile_check "preflight"` (resolved runs; unknown → `print_fail` +
  `print_fix` + failure count); stale trailing comment removed.
- `installer/handoff.sh` — silent `*)` replaced with
  `resolve_handoff_section` routing (resolved renders; unresolved → visible
  notice); in-function comment updated.
- `tests/fixtures/profiles/fake-surfaces.profile` — **new** pure-data fixture
  exercising every surface's dispatch.
- `tests/fixtures/profiles/test/commands/doctor_deep.sh` — **new** Tier-1
  doctor-deep override fixture (sentinel + exit 7).
- `tests/test_p0h_dispatch.bats` — **new** 9-test phase suite.
- Docs: `docs/architecture/runtime-authority-map.md`,
  `docs/architecture/phase0-seam-contract.md`, `docs/CHANGELOG.md`,
  `docs/releases/P0-H-profile-aware-surfaces.md`,
  `docs/tests/P0-H-profile-aware-surfaces.md`,
  `docs/runbooks/PHASE0_LEDGER.md` (Entry 013), and this handoff.

## Files not changed but relevant

- `installer/dispatch.sh` — byte-identical; P0-H consumes the P0-E resolvers, it
  does not change them.
- `installer/init.sh` — byte-identical; already profile-aware (P0-E).
- `actools.sh` — byte-identical; install-spine profile **selection** is out of
  scope (a separate, later concern).
- `installer/profile.sh`, `installer/output.sh`, `cli/commands/doctor_deep.sh` —
  byte-identical (the built-in deep gate is the community fallback).
- `modules/audit/audit.sh` — out of scope (`--deep` is a mode flag, not a
  hardcoded source; modules are forbidden scope).
- Reused existing stubs: `tests/fixtures/profiles/test/plus_preflight_check.sh`
  and `.../plus_handoff_section.sh`.

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none (already profile-aware in P0-E; extra-field consumption now test-covered, collected as a no-op) |
| Profile loading | none |
| Install stages | none |
| CLI | none (`cli/actools` untouched) |
| Generated files | none (golden drift 6/6) |
| Preflight | extras now dispatched via `resolve_profile_check "preflight"`; unknown → hard fail for non-default; community loop body never runs |
| Doctor | `--deep` handler resolved via `resolve_feature_handler` with baseline fallback; community falls back to the built-in gate (byte-identical). `PROFILE_DOCTOR_EXTRA` per-check loop deferred |
| Handoff | non-built-in sections resolved via `resolve_handoff_section`; unresolved → visible non-fatal notice; community never hits `*)` |

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
export PATH="$PWD/../bats-core-1.11.0/bin:$PATH"

# Community-unchanged regression (identical to baseline):
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

## Test result

PASS — 144/144 across the tree (9 new). Community behaviour suites unchanged
(doctor 5, preflight 6, init_profile 10, d0_dispatch 48); golden drift 6/6 with
no fixture modified. `bash -n` clean; shellcheck shows only pre-existing
info-level `SC2012` (`ls -t` on untouched lines) and a pre-existing `SC2034` in
the unedited `init.sh` — no new findings.

## Docs updated

Runtime authority map (Preflight/Doctor/Handoff rows flipped to consumed;
resolver-layer row + Init status updated; surface-blindness note closed; test
count 135 → 144; P0-H answer added); seam contract status note; CHANGELOG;
release note; test report; ledger Entry 013; this handoff.

## Changelog / release notes updated

CHANGELOG.md (P0-H section prepended), `docs/releases/P0-H-profile-aware-surfaces.md`
(with a `## Rollback` section), and `docs/tests/P0-H-profile-aware-surfaces.md`.

## Ledger entry

Entry number: 013

## Known risks

- **`PROFILE_DOCTOR_EXTRA` per-check loop deliberately deferred (recorded):**
  doctor deep handler wired via `resolve_feature_handler` + baseline fallback;
  per-check `PROFILE_DOCTOR_EXTRA` dispatch loop deliberately deferred —
  `resolve_doctor_check` primitive exists and is tested, consumer loop to be
  added when a profile defines doctor extras (community-plus/Phase-1). Spec #3's
  "deep/extra" is satisfied at the deep handler; the extra loop has no consumer
  in Phase 0. Consistent with the LOCKED-alignment §4.1 pin.
- The preflight/handoff **fail vs notice asymmetry** is deliberate: preflight is
  a readiness gate (unknown → fail), handoff is a display surface (unresolved →
  visible non-fatal notice). Documented in the release note.
- Profile preflight-extra handlers are expected to print their own status line
  and return non-zero to register a failure (documented convention).

## Blockers

None.

## Exact next allowed task

P0-I — extend the resolver-bypass guard (the sibling-scope audit) to cover
`actools.sh`, and add the fake-profile e2e (`actools.sh install` with a
non-default profile). Then P0-J phase-0 closure review.

## Explicitly forbidden scope for next task

Install-spine profile **selection** (sourcing the selected profile in
`actools.sh::main` instead of the hardcoded `community.profile`) and any
community-plus handler implementation — both are Phase-1 / later-phase scope.

## Review Gate notes

**Decision: Approved** — pending the operator's re-run of the test + lint gate on
the devbox after applying the diff against `main`. Rationale: the change consumes
the existing P0-E seam without modifying it (`dispatch.sh` byte-identical), every
dispatch point is exercised by the fake profile, the community profile is proven
byte-identical (golden drift 6/6 + four unchanged behaviour suites + six untouched
out-of-scope files), and the one scope judgment (the deferred
`PROFILE_DOCTOR_EXTRA` loop) is recorded verbatim in the ledger and release note.
