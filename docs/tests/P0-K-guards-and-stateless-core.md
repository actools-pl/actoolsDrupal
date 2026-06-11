# Test report — P0-K · Guards + Stateless Core Extraction

Phase: P0-K
Date: 2026-06-11
Result: **PASS** — full suite 192/192; golden drift 6/6 at every commit; both
guards non-vacuous (three captured failure demonstrations below).

## 1. Test inventory after P0-K

| Suite | Tests | Notes |
|---|---|---|
| `tests/guards/live_authority_guard_test.bats` | 2 | closure-sanity pin + marker membership |
| `tests/guards/duplicate_function_guard_test.bats` | 3 | exactly-once (closure) + wired-twin + unconditional twin ban |
| `tests/core/bootstrap_test.bats` | 12 | behavior + v14 path-semantics statics + orphan-content ban |
| `tests/core/state_test.bats` | 10 | behavior + orphan-twin ban |
| `tests/core/secrets_test.bats` | 17 | behavior + live inline writeback loop (fix7) + orphan ban |
| `tests/core/validate_test.bats` | 11 | behavior + S3 `:-true` statics + orphan ban |
| rest of the suite (dispatch, installer, e2e, golden drift, …) | 137 | unchanged content; golden drift = 6 of these |
| **Total (`bats -r tests/`)** | **192** | 158 at baseline → 192 (+5 guards; `tests/core` 21 → 50) |

## 2. Per-commit verification battery

Run after **every** extraction commit (and the final state):

```bash
bash -n actools.sh && bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/core/
bats tests/guards/
bats tests/generated/golden_drift_test.bats     # 6/6 every time, no fixture modified
bats -r tests/
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 core/*.sh
```

| Commit | actools.sh lines | tests/core | guards | drift | full suite |
|---|---|---|---|---|---|
| 1/6 guards | 871 (untouched) | 21/21 (old) | 4/4 | 6/6 | 162/162 |
| 2/6 capture | 871 (untouched) | 45/45 | 4/4 | 6/6 | 186/186 |
| 3/6 bootstrap | 869 | 46/46 | 4/4 | 6/6 | 187/187 |
| 4/6 state | 865 | 47/47 | 4/4 | 6/6 | 188/188 |
| 5/6 secrets | 839 | 48/48 | 4/4 | 6/6 | 189/189 |
| 6/6 validate + hardened guard | 835 | 50/50 | 5/5 | 6/6 | 192/192 |

Note (`bash -n` scope): `bash -n` applies to `*.sh` files and the entry points.
It is **not** applicable to `.bats` files — the bats `@test "…" { … }` block is
preprocessor syntax, and raw `bash -n` reports a spurious `unexpected token '}'`
on every `.bats` file in the repo (verified against a committed, bats-green
guard file). `.bats` validity is proven by running bats itself, which the
battery does.

## 3. Faithfulness proof (extraction = the inline code, byte for byte)

Two independent mechanisms:

1. **Per-function byte-identity.** At each extraction commit, every moved
   function was diffed between `actools.sh` (pre-edit) and the new module using
   the same brace-counting extractor the tests use
   (`tests/core/extract_inline.bash::extract_inline_fn`); all 15 functions
   reported byte-identical.
2. **Assertion-stable re-pointing.** Commit 2 captured the behavior of all four
   units against the **inline** code; each extraction commit changed only the
   test *loader* (`extract_inline_fn … actools.sh` → `source core/<x>.sh`)
   while the assertions stayed identical — and stayed green.

Plus the end-to-end proof: golden drift 6/6 with no fixture modified, at every
commit.

## 4. Guard non-vacuity demonstrations

Each guard was made to fail by deliberately introducing its violation in the
working tree, the failing output was captured, and the tree was restored (the
committed state passes). Outputs below are verbatim.

### Demo 1 — live-authority guard: an orphan claiming authority

Violation introduced at commit 1/6 (pre-extraction), when `core/state.sh` was
still the unsourced stale orphan:

```bash
printf '\n# LIVE AUTHORITY (P0-K non-vacuity demo): falsely claimed on an unsourced orphan\n' >> core/state.sh
bats tests/guards/live_authority_guard_test.bats
```

```text
1..2
ok 1 closure sanity: the builder resolves the known live install path
not ok 2 every file declaring LIVE AUTHORITY is sourced on the live install path
# (in test file tests/guards/live_authority_guard_test.bats, line 88)
#   `return 1' failed
# LIVE AUTHORITY declared but NOT on the live install path:
#   core/state.sh
#
# Either wire the file into the live path (source it from a live file)
# or remove its authority claim. A file must not look authoritative
# while being an orphan — that is the Phase-0 regression this guard exists for.
```

Tree restored (`git checkout -- core/state.sh`); guard green again.

### Demo 2 — duplicate-function guard: the wrong wiring (the rejected Entry-015 move)

Violation introduced at commit 1/6: source the stale orphan `core/validate.sh`
from `actools.sh` while the inline `validate_env` still exists — exactly the
"wire the orphans" move the closure review rejected (it would flip the S3
default):

```bash
sed -i '110i source "${INSTALL_DIR}/core/validate.sh" 2>/dev/null || true   # P0-K non-vacuity demo: WRONG WIRING' actools.sh
bats tests/guards/duplicate_function_guard_test.bats
```

```text
1..2
not ok 1 each risky core function is defined exactly once on the live install path
# (in test file tests/guards/duplicate_function_guard_test.bats, line 71)
#   `return 1' failed
# Risky core functions must be defined exactly once on the live install path:
#   validate_env: defined 2x on the live path [actools.sh(x1) core/validate.sh(x1)]
#
# Count >1 = a wired twin (wrong wiring) or an inline copy that was not
# deleted on extraction. Count 0 = the function fell off the live path.
not ok 2 no risky core function is defined in both actools.sh and a sourced core module
# (in test file tests/guards/duplicate_function_guard_test.bats, line 95)
#   `return 1' failed
# Inline + sourced-core dual definition detected (wrong wiring):
#   validate_env: inline in actools.sh AND in sourced core/validate.sh
```

Tree restored; guard green again.

### Demo 3 — hardened twin-ban arm: a reintroduced inline copy at end-state

Violation introduced at commit 6/6 (all four units extracted and live): re-add
an inline `validate_env`:

```bash
printf '\nvalidate_env() { :; }   # P0-K non-vacuity demo: reintroduced inline twin\n' >> actools.sh
bats tests/guards/duplicate_function_guard_test.bats
```

```text
1..3
not ok 1 each risky core function is defined exactly once on the live install path
# (in test file tests/guards/duplicate_function_guard_test.bats, line 71)
#   `return 1' failed
# Risky core functions must be defined exactly once on the live install path:
#   validate_env: defined 2x on the live path [actools.sh(x1) core/validate.sh(x1)]
#
# Count >1 = a wired twin (wrong wiring) or an inline copy that was not
# deleted on extraction. Count 0 = the function fell off the live path.
not ok 2 no risky core function is defined in both actools.sh and a sourced core module
# (in test file tests/guards/duplicate_function_guard_test.bats, line 95)
#   `return 1' failed
# Inline + sourced-core dual definition detected (wrong wiring):
#   validate_env: inline in actools.sh AND in sourced core/validate.sh
not ok 3 twin ban: no risky core function is defined in both actools.sh and any core module
# (in test file tests/guards/duplicate_function_guard_test.bats, line 122)
#   `return 1' failed
# Twin definition detected (inline copy not deleted, or orphan twin reintroduced):
#   validate_env: inline in actools.sh AND in core/validate.sh
```

Tree restored; all 5 guard tests green on the committed state.

### Why the twin ban lands at 6/6, not 1/6 (two-stage hardening)

Before the extraction, all ten risky names legitimately existed in **both**
`actools.sh` (live inline) and `core/*.sh` (unsourced stale twins) — an
unconditional both-files ban would have failed CI at the guards-first commit,
contradicting the per-commit green requirement. Unsourced files cannot collide
at runtime, so commits 1–5 enforce the runtime-true invariant (exactly-once on
the live closure, plus the explicit wired-twin arm), which already fails the
Entry-015 wrong-wiring move (Demo 2). Once commit 6 retired the last twin, the
unconditional ban became satisfiable and was switched on — closing the residual
gap of a *dormant* (unsourced) twin being reintroduced and waiting to be wired.

## 5. The v14 traps — pinned by statics

- **S3 default**: `actools.sh` contains `ENABLE_S3_STORAGE:-true` (×4) and zero
  `:-false`; a count-equality test bans any non-`true` default from ever
  appearing; `core/validate.sh` is banned from any `ENABLE_S3_STORAGE` code
  reference at all (comments documenting the retirement are allowed).
- **Path semantics**: `INSTALL_DIR` BASH_SOURCE-relative and `ENV_FILE`/
  `STATE_FILE` INSTALL_DIR-anchored in `actools.sh`; the orphan's `$REAL_HOME`
  forms banned; `core/bootstrap.sh` banned from assigning any of
  `INSTALL_DIR/ENV_FILE/STATE_FILE/REAL_HOME/REAL_USER/MODE/ACTOOLS_VERSION/
  LOCK_FILE/LOG_FILE/LOG_DIR/RUN_LOG/PKG_DONE_FLAG/DRY_RUN`.
- **Module shape**: each `core/*.sh` defines exactly its unit's functions
  (5/5/4/1) and nothing else; `writeback_secrets`, the state-side
  `get_db_pass`/`get_backup_pass` twins, and the orphan S3/xelatex/env-mode/
  disk validators are banned by name.

## 6. Golden-capture canary maintenance (not a behavior change)

`tests/helpers/capture_golden_outputs.sh` pins `setup_cli()`'s line range as a
drift canary (`_assert_fn_range`); its own failure message instructs updating
`SC_START`/`SC_END` when `actools.sh` lines move. The four extractions shifted
`setup_cli` upward: 702-717 → 700-715 (3/6) → 696-711 (4/6) → 670-685 (5/6) →
666-681 (6/6). Each extraction commit updated the two constants; the capture
logic and all golden fixtures are untouched, and drift stayed 6/6 throughout —
the canary behaving exactly as designed.

## 7. Lint

- `shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh` — clean at every
  commit (same documented exclusions as CI; `actools.sh` was edited only at the
  four extraction sites, all of which are `source` lines + comments).
- `shellcheck --exclude=SC2034,SC2015,SC2164 core/*.sh` — clean (the exact CI
  invocation for `core/*`; the new modules introduce no new exclusion needs).
