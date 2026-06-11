# Handoff — P0-K · Guards + Stateless Core Extraction

## Repository state

Branch: `phase0/P0-K-guards-stateless-core` (sandbox `master`; operator records the applied branch)
Commit SHA: seven commits, in order — `11ea38d` P0-K(1/6) guards · `c8e32b7` P0-K(2/6) behavior capture · `3efc1d5` P0-K(3/6) bootstrap · `6200979` P0-K(4/6) state · `0f012c5` P0-K(5/6) secrets · `9018a0c` P0-K(6/6) validate + guard hardening · docs commit (ledger/map/changelog/release/test report/this handoff). Baseline: `1fa986e` (pristine import of upstream `e013e93`).
Working tree clean? yes
Zip/package name if applicable: `actools-P0-K-complete.zip` (full repo incl. `.git` with the commit sequence)

## Task completed

P0-K in full, per the spec and the coding-window prompt:

1. **Two anti-regression guards, CI-gated, non-vacuous** (commit 1/6).
   - *Live-authority guard* — every file declaring the P0-G `LIVE AUTHORITY`
     marker must be on the live install path (the transitive source-closure of
     `actools.sh`, computed by `tests/guards/live_closure.bash`: static +
     `for`-loop-expanded `${INSTALL_DIR}`-anchored sources; a closure-sanity
     test pins the known path so the guard cannot pass vacuously).
   - *Duplicate-function guard* — each of the ten risky names (`validate_env
     rand_pass gen_if_empty init_state set_state get_state is_installed
     mark_installed get_db_pass get_backup_pass`) defined **exactly once** on
     the live path; an explicit wired-twin arm names the inline+sourced-core
     dual; an unconditional twin ban (both `actools.sh` AND any `core/*.sh`,
     sourced or not) was added at 6/6 once the stale twins were retired.
   - CI wiring: both live under `tests/guards/` and are auto-discovered by the
     existing recursive job (`lint.yml`: `bats -r tests/`) — no workflow edit.
   - **Non-vacuity proven three times** with captured failing output
     (`docs/tests/P0-K-guards-and-stateless-core.md` §4): orphan authority
     claim → guard 1 fails; wiring the stale `core/validate.sh` while inline
     `validate_env` exists (the exact Entry-015 rejected move) → guard 2 fails
     naming the collision; reintroduced inline `validate_env(){ :; }` at
     end-state → all three arms fail incl. the twin ban.
2. **Behavior captured before moving anything** (commit 2/6): 45 tests pin the
   inline v14 behavior of all four units (loader = brace-counting extractor
   `tests/core/extract_inline.bash`), incl. the live top-level fix7 writeback
   loop pinned where it lives.
3. **Per-unit extraction, one commit each, bootstrap → state → secrets →
   validate** (commits 3-6): `core/<x>.sh` overwritten with the verbatim
   inline implementation (+ `LIVE AUTHORITY (P0-K)` header + required-globals
   docs, functions only — `set -u` safe by construction), sourced from
   `actools.sh` at the exact spot the definitions occupied, inline copy
   deleted in the same commit, the unit's `tests/core/<x>_test.bats` loader
   re-pointed at the module with the **same assertions**.
4. **After each unit**: golden drift 6/6 (no fixture modified), full suite
   green, duplicate-function guard green — no dual definition existed at any
   point.

## Files changed

- `core/bootstrap.sh` — live: `log/warn/error/section/dryrun` (verbatim)
- `core/state.sh` — live: `init_state/set_state/get_state/is_installed/mark_installed` (verbatim)
- `core/secrets.sh` — live: `rand_pass/gen_if_empty/get_db_pass/get_backup_pass` (verbatim)
- `core/validate.sh` — live: `validate_env` only (verbatim)
- `actools.sh` — 871 → 835 lines; four definition blocks → four
  `source "${INSTALL_DIR}/core/<x>.sh"` lines; nothing else touched
- `tests/guards/{live_closure.bash,live_authority_guard_test.bats,duplicate_function_guard_test.bats}` — new
- `tests/core/{extract_inline.bash,bootstrap_test.bats,state_test.bats}` — new;
  `tests/core/{secrets_test.bats,validate_test.bats}` — rewritten off the stale
  orphans onto the live code (21 → 50 tests total)
- `tests/helpers/capture_golden_outputs.sh` — `setup_cli` line canary constants
  only (702-717 → 666-681; the helper's own documented maintenance step)
- `docs/runbooks/PHASE0_LEDGER.md` (Entry 016), `docs/architecture/runtime-authority-map.md`
  (Bootstrap row reworked; new stateless-core row; test-surface addendum; P0-K
  answer), `docs/CHANGELOG.md`, `docs/releases/P0-K-guards-and-stateless-core.md`,
  `docs/tests/P0-K-guards-and-stateless-core.md`, this handoff

## Files not changed but relevant

- `main()`'s `source profiles/community.profile` (`actools.sh`) — untouched (P0-P)
- DB layer / `install_env` / cron / CLI — untouched (P0-L / P0-M / P0-N)
- All standalone feature orphans — untouched (P0-O audit first)
- `.github/workflows/lint.yml` — untouched; recursion already gates the guards
- `tests/fixtures/golden/**` — untouched; drift proven against the existing fixtures
- `installer/*`, `modules/*`, `profiles/*` — untouched

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | Helper functions (`log/warn/error/section/dryrun`) moved to `core/bootstrap.sh` (live). Variables/paths stay in `actools.sh`: `INSTALL_DIR` BASH_SOURCE-relative, `ENV_FILE`/`STATE_FILE` INSTALL_DIR-anchored. The orphan's `$REAL_HOME` semantics are dead and statically banned. |
| Init | none (untouched) |
| Profile loading | none (untouched) |
| Install stages | none (dispatcher untouched; the stage handlers call the same functions, now module-defined) |
| CLI | none (untouched) |
| Generated files | none (generators untouched; drift 6/6) |
| Preflight | none |
| Doctor | none |
| Handoff | none |
| **State / Secrets / Validate (new)** | `core/state.sh`, `core/secrets.sh`, `core/validate.sh` are the live authority for their functions; inline copies deleted; stale v9.2 twins retired in full. |

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
bash -n actools.sh
bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/core/                              # 50/50
bats tests/guards/                            # 5/5
bats tests/generated/golden_drift_test.bats   # 6/6
bats -r tests/                                # 192/192
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 core/*.sh
```

## Test result

PASS — 192/192; drift 6/6 at each of the six implementation commits; guards
non-vacuous (three captured demos in the test report).

## Docs updated

Ledger (Entry 016) · runtime-authority-map (P0-K answer: **Yes** — four
concerns moved) · release note · test report · this handoff.

## Changelog / release notes updated

`docs/CHANGELOG.md` — new `[Unreleased] — P0-K` section;
`docs/releases/P0-K-guards-and-stateless-core.md`;
`docs/tests/P0-K-guards-and-stateless-core.md`.

## Ledger entry

Entry number: 016

## Known risks

- The `setup_cli` line canary (`SC_START=666 SC_END=681` in
  `tests/helpers/capture_golden_outputs.sh`) must be updated by any future
  phase that shifts `actools.sh` lines above `setup_cli` — the helper fails
  loudly with self-describing instructions (by design).
- The closure builder covers the live tree's two source patterns
  (`${INSTALL_DIR}`-anchored static + single-level `for`-loop interpolation);
  an exotic future pattern needs a builder extension. The closure-sanity test
  pins the known path shape so under-resolution fails CI rather than passing
  vacuously.

## Blockers

None.

## Exact next allowed task

**P0-L — DB layer extraction** (post-closure track order).

## Explicitly forbidden scope for next task

No `install_env`/cron/CLI extraction before P0-M/P0-N; no
standalone-feature-orphan wiring before P0-O's audit; `main()`'s hardcoded
profile source stays until P0-P; no generated-file change; no community-plus
feature work.

## Review Gate notes

Explicit confirmations the spec asks the Gate to verify:

1. **Drift held**: golden drift **6/6 at every commit**, no fixture modified.
2. **Tests re-pointed**: `tests/core/*` load the live modules (the writeback
   tests deliberately keep pinning the inline loop — it was not extracted);
   the assertions are unchanged from the inline capture (faithfulness proof),
   plus per-function byte-identity was verified at each extraction.
3. **No dual definitions remain**: zero risky-name definitions in `actools.sh`
   (verified); each defined exactly once, in its module; enforced forever by
   the duplicate-function guard's three arms.
4. **S3/path/jq behavior matches the live code, not the orphan**:
   `ENABLE_S3_STORAGE:-true` ×4 in `actools.sh`, `:-false` ×0 on the live path,
   `core/validate.sh` has no S3 code reference at all; `INSTALL_DIR`
   BASH_SOURCE-relative and `ENV_FILE`/`STATE_FILE` INSTALL_DIR-anchored
   (statics ban the `$REAL_HOME` forms); jq/state-file semantics and the
   fix7 secret-writeback order byte-unchanged.
5. **Guards bite**: three verbatim failure demos in
   `docs/tests/P0-K-guards-and-stateless-core.md` §4, including the exact
   Entry-015 rejected move (wiring the stale `core/validate.sh`).
