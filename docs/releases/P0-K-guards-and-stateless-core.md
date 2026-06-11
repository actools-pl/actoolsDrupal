# Release note — P0-K · Guards + Stateless Core Extraction

Phase: P0-K — Guards + Stateless Core Extraction (first post-closure phase)
Branch: `phase0/P0-K-guards-stateless-core`
Date: 2026-06-11
Status: pending Review Gate

## Summary

Phase 0 closed (Entry 015) with a documented hazard left standing: the four
stale **v9.2 orphan twins** in `core/*.sh` looked authoritative but were sourced
by nobody, while the inline **v14** code in `actools.sh` was what actually ran.
The closure review rejected the "just wire the orphans" recommendation because
it would have silently flipped `ENABLE_S3_STORAGE` off (`core/validate.sh`'s
`:-false` vs the live `:-true`) and moved every path to `$REAL_HOME`
(`core/bootstrap.sh`'s `INSTALL_DIR="$REAL_HOME"` vs the live BASH_SOURCE-relative
form).

P0-K resolves that hazard in the only safe direction — **the inline v14 code is
the authority; the orphans are overwritten with it** — and first installs two CI
guards so the unsafe direction can never be taken silently again:

- **Live-authority guard** — a `LIVE AUTHORITY` claim (the P0-G marker) requires
  presence on the live install path (the transitive source-closure of
  `actools.sh`). A file may not *look* authoritative while being an orphan.
- **Duplicate-function guard** — each of the ten risky stateless-core functions
  must be defined **exactly once** on the live path. Wiring a twin while the
  inline copy exists — or reintroducing an inline copy after extraction — fails
  CI with a message naming the exact collision.

Then the stateless core moved, **one unit per commit** (bootstrap → state →
secrets → validate), each commit: overwrite `core/<x>.sh` with the verbatim
inline implementation, source it from `actools.sh` at the exact spot the
definitions occupied, delete the inline copy, re-point `tests/core/<x>_test.bats`
at the now-live module, and prove golden drift 6/6 + full suite green.

**This is an authority move, not an output change** (the P0-G pattern):
`actools.sh` shrinks 871 → 835 lines, the six generated stack files stay
byte-identical across all five variants at **every** commit, and every extracted
function body is **byte-identical** to its inline original (verified
per-function with the test extractor).

## Scope — what moved, what did not

**Moved to modules (now live authority), function definitions only:**

- `core/bootstrap.sh` — `log` / `warn` / `error` / `section` / `dryrun`.
- `core/state.sh` — `init_state` / `set_state` / `get_state` / `is_installed` /
  `mark_installed` (jq semantics unchanged: atomic tmp+mv writes, literal
  `"null"` for missing keys, `INSTALL_DIR`-anchored `STATE_FILE`).
- `core/secrets.sh` — `rand_pass` / `gen_if_empty` / `get_db_pass` /
  `get_backup_pass` (the P0-K unit assignment: the per-env password accessors
  belong to secrets, not state).
- `core/validate.sh` — `validate_env` **only**.

Each module carries a `LIVE AUTHORITY (P0-K)` header documenting the globals it
relies on (`set -u` handled by construction: no module-level variable reads or
assignments — the spine sets `R/G/Y/C/NC`, `DRY_RUN`, `STATE_FILE`, `REAL_USER`
before any call, exactly as before).

**Deliberately NOT moved (stays top-level in `actools.sh`, byte-untouched):**

- `DRY_RUN=false` + the dry-run mode flip (spine state).
- The secret flow in its original order: `gen_if_empty DB_ROOT_PASS` /
  `DRUPAL_ADMIN_PASS`, then the **v9.2-fix7 writeback loop** — the
  secret-writeback order is unchanged and the loop is still pinned by tests
  where it lives.
- The **S3 gate** with the v14 default `${ENABLE_S3_STORAGE:-true}`
  (4 occurrences in `actools.sh`; `:-false` occurs nowhere on the live path),
  S3 provider auto-detection, and the XeLaTeX / environment-mode / disk checks.
- `main()`'s hardcoded `source profiles/community.profile` (P0-P), the DB layer
  / `install_env` / cron / CLI (P0-L / P0-M / P0-N), every standalone feature
  orphan (P0-O audit first).

**Retired stale orphan content (none of it survives anywhere):**

`INSTALL_DIR="$REAL_HOME"` and all `$REAL_HOME`-anchored paths,
`ACTOOLS_VERSION="9.2"`, the orphan lock/exec-redirect logic,
`writeback_secrets()`, the state-side `get_db_pass`/`get_backup_pass` twins,
`validate_s3()` (`:-false`), `detect_s3_provider`, `validate_xelatex`,
`validate_environment_mode`, `validate_disk`. Per-unit statics in
`tests/core/*` ban each item from returning; the hardened twin-ban guard arm
bans any risky-name twin from ever existing in both `actools.sh` and
`core/*.sh` again.

## Guards — semantics and CI wiring

Both guards live under `tests/guards/` and are gated by the existing recursive
CI job (`lint.yml`: `bats --print-output-on-failure -r tests/`) — **zero
workflow edit**, by design of P0-I's recursive switch.

The duplicate-function guard's semantics are **closure-based** so it stays green
at every commit of the phase while still biting on the real hazard: files on
disk but unsourced cannot collide at runtime; the moment one is *wired* while
its inline twin exists, the count goes to 2 and CI fails. The unconditional
twin ban (risky name in both `actools.sh` and any `core/*.sh`, sourced or not)
became satisfiable only once the stale twins were retired, so it was added in
the final extraction commit — a deliberate two-stage hardening, recorded in the
test report with all three non-vacuity demonstrations.

## Test-net changes

- `tests/core/*`: 21 stale-orphan tests → **50** live-code tests. Behavior was
  captured against the **inline v14 code first** (commit 2, via the
  brace-counting extractor in `tests/core/extract_inline.bash`), then each
  suite was re-pointed at its live module in the unit's extraction commit with
  the **same assertions** — the unchanged assertions are the faithfulness proof.
- `tests/guards/*`: +5 tests (closure sanity, authority membership, and the
  duplicate guard's three arms).
- `tests/helpers/capture_golden_outputs.sh`: the `setup_cli` line canary moved
  702-717 → 666-681 as the extractions shifted `actools.sh` upward — the
  helper's own documented maintenance step (its error message instructs exactly
  this update). Capture logic untouched; **no golden fixture modified**.
- Full suite: 158 → **192**, green throughout; golden drift **6/6 at each of
  the six commits**.

## Operator impact

None. `community` install behavior, generated files, CLI, paths, defaults and
versions are unchanged (`ACTOOLS_VERSION` stays 14.0). This phase changes which
files are authoritative for the stateless core and adds the CI guards that keep
it that way.

## Commit sequence (one unit per commit)

1. `P0-K(1/6)` — guards + closure engine (non-vacuity demos 1 & 2 captured).
2. `P0-K(2/6)` — behavior capture against the inline v14 code (45 tests).
3. `P0-K(3/6)` — bootstrap → `core/bootstrap.sh` (canary 702-717 → 700-715).
4. `P0-K(4/6)` — state → `core/state.sh` (canary → 696-711).
5. `P0-K(5/6)` — secrets → `core/secrets.sh` (canary → 670-685).
6. `P0-K(6/6)` — validate → `core/validate.sh`; twin-ban guard arm + demo 3
   (canary → 666-681).
7. Docs — ledger Entry 016, runtime-authority-map (Bootstrap row + new
   stateless-core row + P0-K answer), CHANGELOG, this note, the test report,
   `HANDOFF-P0-K.md`.
