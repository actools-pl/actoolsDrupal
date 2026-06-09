# Handoff — P0-E · Profile Validation and Resolver Contract

## Repository state

Branch: `phase0/P0-E-profile-validation-and-resolver`
Commit SHA: (recorded by operator at apply time)
Working tree clean? yes (after the P0-E commit)
Zip/package name if applicable: `actoolsDrupal-main` (snapshot; baseline `7d505e7` — "baseline: P0-D merged state (pre-P0-E)")

## Task completed

Made profile selection **safe at `init` time** and **completed the resolver
contract** to the LOCKED shape, with community behaviour byte-identical and no
community-plus feature work.

1. **`init` validation (alignment §4.3).** `installer/init.sh` sources
   `installer/profile.sh` for the chosen profile, validates the **`.profile` file
   exists**, and enforces `PROFILE_REQUIRES_ACTOR` / `PROFILE_REQUIRES_CHANGE_TICKET`
   **before persisting** `actools.env`. It consumes `PROFILE_INIT_FIELDS`. New
   flags `--actor-id` / `--change-ticket` are validated when required but **not
   persisted**. This closes the latent `--profile community-plus` break (allowed
   name, absent file).
2. **Resolver contract.** `actools::dispatch::resolve_feature_handler` now does
   **3-tier PATH resolution** (override → module → default; community → empty,
   alignment §4.1), and a LOCKED-named umbrella
   `actools::dispatch::resolve_profile_check <surface> <check_id>` (alignment §4.2)
   delegates to the existing per-surface internals. Both are **internal primitives
   with no live call sites** (callers are P0-H).

The **only live behaviour change is in `init`**, and it is a no-op for community.
`actools.sh` is **byte-identical**. Golden drift stays **6/6**.

## Files changed

- `installer/init.sh` — source `profile.sh`; validate `.profile` file existence
  and **fail before persisting**; enforce actor/ticket via the existing
  `profile_requires_actor` / `profile_requires_change_ticket`; consume
  `profile_init_fields`; add `--actor-id` / `--change-ticket` (validated, not
  persisted); `ACTOOLS_PROFILE` declared **local** in `run_init`.
- `installer/dispatch.sh` —
  - `resolve_feature_handler` → 3-tier PATH resolution; community short-circuit to
    empty; unknown → WARN + empty. `PROFILE_FEATURE_MODULES` read `+x`-guarded.
  - **new** `resolve_profile_check <surface> <check_id>` umbrella delegating to
    `resolve_preflight_check` / `resolve_doctor_check` / `resolve_handoff_section`
    (unknown surface → WARN + empty).
  - header updated to document the return-shape asymmetry.
- `tests/installer/init_profile_test.bats` — **new**, 10 tests.
- `tests/test_d0_dispatch.bats` — **+15 tests** (33 → 48); the one community-plus
  `resolve_feature_handler` test updated token → tier-3 path.
- `tests/fixtures/profiles/fake-actor.profile`, `…/fake-ticket.profile` — **new
  test-only** fixtures.
- `tests/installer/init_test.bats` — setup stages `dispatch.sh` + `profile.sh` +
  `community.profile` so the 11 existing tests run the real flow under `set -u`.
- `docs/runbooks/PHASE0_LEDGER.md` — Entry 010.
- `docs/architecture/runtime-authority-map.md` — Init / Profile-loading /
  Resolver-layer rows; test count 88→113; Review question (P0-E answer).
- `docs/CHANGELOG.md` — P0-E section.
- `docs/releases/P0-E-profile-validation-and-resolver.md` — release note (incl. Rollback).
- `docs/tests/P0-E-profile-validation-and-resolver.md` — test report.
- `docs/runbooks/HANDOFF-P0-E.md` — this handoff.

## Files not changed but relevant

- `actools.sh` — **forbidden this phase**; byte-identical (`git diff HEAD -- actools.sh` empty).
- `installer/profile.sh` — **in the allowed set but not edited**: all four
  accessors (`profile_requires_actor`/`profile_requires_change_ticket`/
  `profile_init_fields`, plus the missing-file `exit 1`) already existed and were
  sufficient. P0-E is **wiring, not authoring**.
- `profiles/community.profile` — read via the loader; not modified.
- All generator heredocs, `cli/*`, `modules/*`, `core/*`, `.github/workflows/*`,
  `tests/helpers/capture_golden_outputs.sh` — untouched.

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | **changed (live)** — sources `profile.sh`; validates `.profile` **file existence** and **fails before persisting**; enforces actor/ticket; consumes `PROFILE_INIT_FIELDS`. Community unchanged |
| Profile loading | loader + accessors **now consumed by `init`**; "variables only" guarded by a side-effect-free test. Live install-path consumption → P0-H |
| Install stages | none (P0-E does not touch `actools.sh`) |
| CLI | none |
| Generated files | none (golden 6/6 unchanged) |
| Preflight | none (resolver stays token-based, uncalled; → P0-H) |
| Doctor | none (resolver stays token-based, uncalled; → P0-H) |
| Handoff | none (resolver stays token-based, uncalled; → P0-H) |
| **Resolver layer** | `resolve_feature_handler` token→**path** (3-tier); `resolve_profile_check` **added**; both **uncalled on the live path** |

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

# BEFORE (clean HEAD, WIP stashed)
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 88/88

# Syntax
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# AFTER
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/installer/init_profile_test.bats                                 # 10/10
bats tests/test_d0_dispatch.bats                                            # 48/48
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113
```

## Test result

PASS — golden **6/6** before and after (byte-identical generated output);
**113/113** regression+new; **119/119** overall. `actools.sh` byte-identical.

## Docs updated

Ledger (Entry 010), runtime authority map, CHANGELOG, release note, test report,
this handoff.

## Changelog / release notes updated

`docs/CHANGELOG.md` (P0-E section) and
`docs/releases/P0-E-profile-validation-and-resolver.md` (with the required
`## Rollback`).

## Ledger entry

Entry number: 010

## Known risks

- **Token→path contract change (`resolve_feature_handler`).** Safe **only**
  because the function has **zero live call sites**; P0-H callers must consume a
  **path** (source/execute), not a token.
- **Resolver asymmetry.** `resolve_feature_handler` is path-based;
  preflight/doctor/handoff stay token-based; the `resolve_profile_check` umbrella
  returns tokens today (it delegates to the token resolvers). Reconciled at P0-H.
- **`PROFILE_FEATURE_MODULES`** is an internal resolver convention (not in the
  public profile contract, not set by `community.profile`), read `+x`-guarded.
- **`init` sources `profile.sh`.** Inert for community. Profile-declared *extra*
  init fields are collected but not yet validated/collected (→ P0-H; community has
  none).
- **Governance identity not persisted** (P0-H). Tests assert non-persistence.

## Blockers

None.

## Exact next allowed task

**P0-H — Surface wiring.** Wire the completed resolvers into the live surfaces:
preflight extras via `resolve_profile_check "preflight" …` (fail unknown for
non-default); replace doctor's hard `source doctor_deep.sh` with
`resolve_feature_handler` (consuming the **path** it now returns); replace
handoff's silent `*)` with `resolve_handoff_section`; and wire the install path to
the **selected** profile (`ACTOOLS_PROFILE`-driven, now safe because `init`
validates the profile file). Golden 6/6 must remain green. (The Review Gate owns
final sequencing.)

## Explicitly forbidden scope for next task

- No community-plus feature modules.
- No deep audit/doctor features.
- No governance gates beyond validation scaffolding.
- No generated-file byte change.
- No widening / commenting / disabling the golden harness range guard.

## Review Gate notes

Reviewer (separate session, ideally a different model) should confirm:
(1) golden **6/6** unchanged and `actools.sh` **byte-identical**
(`git diff HEAD -- actools.sh` empty);
(2) only allowed files touched (`installer/{init,dispatch}.sh`, tests, fixtures,
docs — note `installer/profile.sh` was allowed but intentionally not edited);
(3) `resolve_feature_handler` 3-tier order is correct **and community
short-circuits to empty even with a staged override** (test 38);
(4) `init` **fails before persisting** for `community-plus`/absent profiles
(`actools.env` not written) and community is unchanged (init_test 11/11 + the
community cases in init_profile_test);
(5) the fake fixtures are test-only and community gains no actor/ticket
requirement;
(6) the token→path asymmetry is acceptable for now (reconciled at P0-H).
Decision: **Approved / Needs revision / Blocked**.
