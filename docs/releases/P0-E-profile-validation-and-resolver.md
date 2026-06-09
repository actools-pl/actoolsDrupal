# Release note — P0-E · Profile Validation and Resolver Contract

Branch: `phase0/P0-E-profile-validation-and-resolver`
Phase: P0-E — Profile Validation and Resolver Contract
Status: pending Review Gate
Commit SHA: (recorded by operator at apply time)

## Summary

P0-E makes **profile selection safe at `init` time** and **completes the
resolver contract** to the LOCKED shape — without any community-plus feature
work and with community behaviour byte-identical.

Two things change:

1. **`init` now validates the profile.** Before writing `actools.env`, `init`
   sources `installer/profile.sh` for the chosen profile, confirms the
   `.profile` **file exists**, and enforces the profile's governance flags
   (`PROFILE_REQUIRES_ACTOR` / `PROFILE_REQUIRES_CHANGE_TICKET`). If the file is
   missing or a required flag is unmet, `init` **fails before persisting** —
   `actools.env` is never written. This closes the latent
   `--profile community-plus` break (an allowed *name* whose profile file is a
   Phase-1 product that does not ship here).

2. **The resolver contract is completed.** `resolve_feature_handler` now does
   LOCKED **3-tier path resolution** (active-profile override → profile module →
   default), returning a path instead of a token; and a LOCKED-named umbrella
   `resolve_profile_check <surface> <check_id>` delegates to the existing
   per-surface resolvers. Both are **internal primitives with no live call
   sites** — they change no runtime install behaviour. Their callers land in
   P0-H.

The **only live behaviour change is in the `init` command**, and it is a no-op
for the default community profile. Generated files are byte-identical
(golden drift 6/6).

## What changed

- `installer/init.sh` — sources `profile.sh`; validates the `.profile` file
  exists and fails **before** persisting `actools.env`; enforces
  `PROFILE_REQUIRES_ACTOR` / `PROFILE_REQUIRES_CHANGE_TICKET` via the existing
  accessors; consumes `PROFILE_INIT_FIELDS`. Adds `--actor-id` / `--change-ticket`
  (validated, **not** persisted — recording identity is P0-H).
- `installer/dispatch.sh` —
  - `resolve_feature_handler` → **3-tier PATH resolution**; community
    short-circuits to **empty** (byte-identical). Token→path is a deliberate
    contract change, safe because the function has **zero live call sites**.
  - **new** `resolve_profile_check <surface> <check_id>` umbrella delegating to
    `resolve_preflight_check` / `resolve_doctor_check` / `resolve_handoff_section`.
  - `resolve_preflight_check` / `resolve_doctor_check` / `resolve_handoff_section`
    stay **token-based** (documented asymmetry; surfaces wired in P0-H).
- `tests/installer/init_profile_test.bats` — **new**, 10 tests (init-time profile
  validation + governance + non-persistence).
- `tests/test_d0_dispatch.bats` — **+15 tests** (33 → 48): 3-tier order,
  `resolve_profile_check` delegation, side-effect-free loading (incl. a negative
  control). The one community-plus `resolve_feature_handler` test was updated
  from the `plus_doctor_deep` token to the resolved tier-3 path.
- `tests/fixtures/profiles/fake-actor.profile`, `…/fake-ticket.profile` —
  **test-only** fixtures (never shipped).
- `tests/installer/init_test.bats` — setup stages the loaders + community profile
  so the 11 existing init tests run the real (profile-sourcing) flow under
  `set -u`.
- Docs: ledger Entry 010, runtime authority map (resolver/init/profile-loading
  rows, test-surface count), CHANGELOG, this release note, the test report, and
  the handoff.

### Resolver contract — before vs after

| Resolver | Before (token) | After |
|---|---|---|
| `resolve_feature_handler` | `community`→`""`; `community-plus`→`plus_<f>`; `test`→`test_<f>` | **3-tier PATH** (override → module → default), first existing wins, else empty; `community`→`""` (short-circuit, preserved) |
| `resolve_preflight_check` | token | **unchanged** (token; → P0-H) |
| `resolve_doctor_check` | token | **unchanged** (token; → P0-H) |
| `resolve_handoff_section` | token | **unchanged** (token; → P0-H) |
| `resolve_profile_check` | **absent (0 hits)** | **new** umbrella delegating to the three above |

### `init` validation — community vs fake profiles

| Profile | Profile file | `REQUIRES_ACTOR` | `REQUIRES_CHANGE_TICKET` | `init` result |
|---|---|---|---|---|
| `community` (default) | ships | false | false | unchanged — succeeds with `--domain`/`--email` |
| `community-plus` | **absent here** | n/a | n/a | **fails before persisting** (exit 3, `actools.env` not written) |
| `<unknown name>` | n/a | n/a | n/a | fails on list membership (exit 3) |
| `test` ← `fake-actor.profile` | staged (test-only) | true | false | fails without `--actor-id` (exit 1); succeeds with it |
| `test` ← `fake-ticket.profile` | staged (test-only) | false | true | fails without `--change-ticket` (exit 1); succeeds with it |

## Operator impact

**None for community.** `sudo ./actools.sh init --domain … --email …` behaves
exactly as before and writes `ACTOOLS_PROFILE=community`. The only new observable
behaviour is that selecting a profile whose `.profile` file is not installed now
fails cleanly **before** writing `actools.env`, instead of writing a config the
next run cannot load.

## Verification

```bash
bats tests/generated/golden_drift_test.bats                                 # 6/6 (before and after)
bats tests/installer/init_profile_test.bats                                 # 10/10 (new)
bats tests/test_d0_dispatch.bats                                            # 48/48 (33 + 15)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
```

`actools.sh` is byte-identical to its pre-P0-E state (`git diff HEAD -- actools.sh`
is empty); no generator heredoc was touched.

## Rollback

Revert commit `<sha>`. No data migration is expected. The change is confined to
`installer/init.sh`, `installer/dispatch.sh`, tests, fixtures, and docs.
Reverting restores the prior `init` (list-membership-only validation, no
`profile.sh` source) and the prior token-based `resolve_feature_handler`. Because
the resolvers have no live call sites and `actools.sh` is untouched, reverting
has no effect on generated files, install behaviour, state, or already-installed
environments. Any `actools.env` written by the P0-E `init` is identical in shape
to one written by the prior `init` (the governance flags are validated, never
persisted), so a revert needs no env-file fixup.
