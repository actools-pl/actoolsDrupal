# P0-E Profile Validation and Resolver Contract — Test Report

> **Status:** Passing — `init` validates the profile safely, the resolver
> contract is complete to the LOCKED shape, community is byte-identical, golden
> net green.
> Phase: P0-E — Profile Validation and Resolver Contract
> Produced by: Coding Window (Opus)
> Date: 2026-06-09

---

## Summary

P0-E adds init-time profile validation (`installer/init.sh`) and completes the
resolver contract (`installer/dispatch.sh`): 3-tier `resolve_feature_handler`
(alignment §4.1) and the `resolve_profile_check` umbrella (alignment §4.2). This
report records the tests added/changed and the regression + golden evidence that
**community behaviour is unchanged** and **generated output is byte-identical**.

Defining properties this phase must hold (all verified below):

- **Community default behaviour byte-identical** — `init --domain … --email …`
  unchanged; community resolvers still return empty; the install path is
  untouched (`actools.sh` byte-identical).
- **`community-plus` (and any profile whose `.profile` is absent) cannot be
  persisted** by `init` — it fails before `actools.env` is written.
- **A fake profile proves** the actor and change-ticket requirements fire.
- **Side-effect-free profile loading** — sourcing a `.profile` sets variables
  only.
- **Golden drift 6/6** before and after.

---

## Test surface (before → after)

| Suite | Before | After | Δ |
|---|---:|---:|---:|
| `tests/core/validate_test.bats` | 11 | 11 | — |
| `tests/core/secrets_test.bats` | 10 | 10 | — |
| `tests/installer/init_test.bats` | 11 | 11 | — (setup staged loaders) |
| `tests/installer/init_profile_test.bats` | 0 | **10** | **+10 (new)** |
| `tests/installer/preflight_test.bats` | 6 | 6 | — |
| `tests/installer/doctor_test.bats` | 5 | 5 | — |
| `tests/installer/dispatch_stages_test.bats` | 12 | 12 | — |
| `tests/test_d0_dispatch.bats` | 33 | **48** | **+15** |
| **Regression total** | **88** | **113** | **+25** |
| `tests/generated/golden_drift_test.bats` | 6 | 6 | — |
| **Grand total** | **94** | **119** | **+25** |

---

## Tests added — init-time profile validation

New file: `tests/installer/init_profile_test.bats` — 10 tests. Each runs the real
`run_init` against a sandbox `INSTALL_DIR` staged with the template, `dispatch.sh`,
`profile.sh`, and `community.profile`; governance fixtures are staged as
`profiles/test.profile` (the only test-friendly allowed profile name).

1. unknown profile name fails cleanly (exit 3); `actools.env` not written.
2. `community-plus` fails **before persisting** — its `.profile` is absent here,
   so `init` exits 3 and `actools.env` is **not** written (the latent break this
   phase closes).
3. actor-required fixture fails without `--actor-id` (exit 1); env not written.
4. actor-required fixture succeeds with `--actor-id`; `ACTOOLS_PROFILE=test`
   persisted.
5. actor id is **validated but not persisted** (the value never appears in
   `actools.env`).
6. ticket-required fixture fails without `--change-ticket` (exit 1).
7. ticket-required fixture succeeds with `--change-ticket`.
8. change ticket is **validated but not persisted**.
9. default (community) profile requires **neither** actor nor ticket — succeeds,
   `ACTOOLS_PROFILE=community`.
10. explicit `--profile community` also succeeds with no governance flags.

These cover the spec's `## Tests` items: *unknown profile fails*, *missing
profile file fails*, *fake profile actor required*, *fake profile change-ticket
required*, *default profile does not require actor/ticket*.

---

## Tests added — resolver contract (`tests/test_d0_dispatch.bats`, +15)

### Block 9 — `resolve_feature_handler` 3-tier order (5 tests)

A sandbox `INSTALL_DIR` is staged with selected tiers present; the test asserts
which path wins.

34. Tier-1 active-profile override (`profiles.d/<p>/commands/<f>.sh`) wins over
    module and default.
35. Tier-2 profile module (`modules/<mod>/<f>.sh`, via `PROFILE_FEATURE_MODULES`)
    wins when no override exists.
36. Tier-3 default (`cli/commands/<f>.sh`) when no override or module.
37. empty when no tier provides the feature.
38. **community short-circuits to empty even with a staged override** — the
    byte-identical guarantee (community never resolves a handler, even if a
    `profiles.d/community` override file is physically present).

### Block 10 — `resolve_profile_check` umbrella delegation (6 tests)

39. `preflight` surface delegates to `resolve_preflight_check`
    (community-plus → `plus_preflight_disk`).
40. `doctor` surface delegates to `resolve_doctor_check`
    (community-plus → `plus_doctor_tls`).
41. `handoff` surface delegates to `resolve_handoff_section`
    (community-plus → `plus_handoff_site`).
42. community returns empty through the umbrella (delegated baseline preserved).
43. umbrella result **equals** the per-surface internal it delegates to.
44. unknown surface WARNs to stderr and returns empty.

### Block 11 — side-effect-free profile loading (4 tests)

Each profile is sourced in a clean bash subshell from an empty CWD with all
output captured; the test asserts exit 0, **no stdout/stderr**, and **no files
created**.

45. `profiles/community.profile` sources with no executable side effects.
46. `fake-actor.profile` fixture — no side effects.
47. `fake-ticket.profile` fixture — no side effects.
48. **negative control** — a profile that calls `mkdir`/`echo` IS detected (the
    harness must flag it; a check that cannot fail is worthless).

### Test changed (not added)

- `resolve_feature_handler: community-plus …` — was *"returns `plus_doctor_deep`
  token"*; now *"resolves to a tier-3 default handler path"* (asserts the resolved
  path ends `cli/commands/doctor_deep.sh` and that file exists). This is the one
  existing test the §4.1 contract change touches; the preflight/doctor/handoff
  resolver tests are unchanged because those resolvers stay token-based.

---

## Commands run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean HEAD, WIP stashed):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 88/88

# Syntax:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/installer/init_profile_test.bats                                 # 10/10
bats tests/test_d0_dispatch.bats                                            # 48/48
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113
```

## Result

PASS — golden drift **6/6** before and after (generated output byte-identical);
**113/113** regression+new; **119/119** overall. `actools.sh` byte-identical to
its pre-P0-E state.

---

## Limitations / notes

- **Resolvers remain uncalled on the live path.** `resolve_feature_handler` and
  `resolve_profile_check` are internal primitives; their correctness is proven in
  isolation (sandbox staging + the fixture profile). Wiring them into the
  preflight/doctor/handoff/feature surfaces is **P0-H** and is explicitly out of
  scope here.
- **Token→path asymmetry is intentional.** Only `resolve_feature_handler` is
  path-based; `resolve_preflight_check` / `resolve_doctor_check` /
  `resolve_handoff_section` stay token-based until P0-H, so their existing token
  assertions stay green. The umbrella (`resolve_profile_check`) therefore returns
  tokens today (it delegates to the token resolvers).
- **Fake fixtures are test-only.** `fake-actor.profile` / `fake-ticket.profile`
  live under `tests/fixtures/profiles/` and are staged as `profiles/test.profile`
  inside a sandbox `INSTALL_DIR`; they are never shipped and community never gains
  an actor/ticket requirement.
- **Governance identity is validated, not persisted.** `--actor-id` /
  `--change-ticket` are required when a profile demands them but are not written
  to `actools.env`; recording them is a community-plus concern (P0-H). Tests 5
  and 8 assert non-persistence.
- **Side-effect harness scope.** Block 11 detects side effects that produce
  output (`echo`/`printf`, failed external commands) or create files
  (`mkdir`/`touch`/`cp`); pure variable assignments (the allowed shape) produce
  neither, so the shipped profile and both fixtures pass. The negative control
  confirms the harness bites.
