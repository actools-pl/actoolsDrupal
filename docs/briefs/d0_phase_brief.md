# D.0 Phase Brief — Community Seam Hardening (Resolver Dispatch Foundation)

**Phase status:** LOCKED
**Foundation:** v14.1.0 (community-only Drupal install, journey-staged, profile contract in place)
**Authoritative source:** `docs/briefs/METHODOLOGY_NOTES.md` (Drupal arc)
**Cross-reference:** `Actools_Drupal_Community_Plus_LOCKED.md` (design canon), `CODING_AGENT_REFERENCE.md` (WPGovern coding agent discipline, applicable here)

**Why this brief exists:** D.0 is the first phase of the Drupal arc and the first fresh-surface phase since the methodology pass that calibrated this partnership. Its scope is deliberately narrow — establish the dispatch seam that future `plus_*` modules will hook into — but its discipline weight is high because every later phase inherits the patterns laid down here. This brief encodes the discipline at the line level, not at the design level. The architectural decisions are explicit. The acceptance contract is empirically verifiable. The "Note for Sonnet" assumes the implementer has internalized `CODING_AGENT_REFERENCE.md` and references its discipline by name rather than restating it.

---

## 1. Purpose

D.0 delivers the **resolver dispatch foundation**: a single canonical surface (`installer/dispatch.sh`) through which the platform's four operation entry points (init, preflight, doctor, handoff) ask "given the active profile, what is the handler for operation X?" — and receive a deterministic answer.

**The defining property:** Adding `--profile community-plus` to the platform does nothing observable at this phase, because no `plus_*` modules exist yet. The dispatch seam is in place; the modules that hang from it arrive in D.1 and beyond.

**Why this matters as Phase 0:**

The LOCKED design names the resolver pattern as the foundation that lets community-plus features arrive cleanly without forking the platform or branching the codebase. If the dispatch seam is sloppy here, every later `plus_*` module pays the cost. If it's clean here, every later module hangs off it mechanically.

This is the H.1 / H.5 equivalent in the Drupal arc — smallest deliverable, most architectural weight. The implementation is small (one new module, three new helpers, four call-site additions, one test-fixture profile, ~25 new bats tests). The contracts that shape it are the substantial work.

**New surfaces introduced:**

- `installer/dispatch.sh` — resolver function family + profile validation
- `--profile` CLI flag with fail-closed conflict semantics
- `ACTOOLS_PROFILE` env-var read path (via shared helper)
- Test fixture profile at `tests/fixtures/profiles/test/`
- New bats test file consolidating D.0 verification (Sonnet's H.7.1 consolidation discipline applies)

---

## 2. Architectural Decisions

Three decisions shape the rest of this brief. Each is named with the options considered, the choice, and the reasoning. Sonnet implements the chosen option; the alternatives are documented so future maintainers (and the brief author themselves) can see why this shape was picked.

### Decision 1 — Where does the resolver function family live?

**Question:** Where in the installer tree do the resolver functions (`resolve_feature_handler`, `resolve_preflight_check`, `resolve_doctor_check`, `resolve_handoff_section`) sit?

**Option A:** New file `installer/dispatch.sh` containing the entire resolver family
**Option B:** Add resolver functions to existing `installer/profile.sh`
**Option C:** Distribute resolvers — each resolver lives in the module that calls it (`resolve_preflight_check` in `installer/preflight.sh`, etc.)

**Chosen: Option A.**

**Reasoning:**

- The resolver is its own concern. Translating "I'm in profile X; what's my behavior for operation Y" is dispatch logic. Mixing it into `installer/profile.sh` (which currently loads the active profile) conflates two roles: profile *identity* and profile *dispatch*.
- Distributing resolvers (Option C) is exactly the defect class that Sonnet's `CODING_AGENT_REFERENCE.md` Section 2.6 names — *strict-input / loose-state*. If `resolve_preflight_check` lives in `preflight.sh` and `resolve_doctor_check` lives in `doctor.sh`, the contract gets enforced with different rigor in each location. The shared validator pattern (`CODING_AGENT_REFERENCE.md` Rule 2: *one `_validate_X` per data shape*) demands centralization.
- A single `installer/dispatch.sh` is also where every future operation hangs its resolver calls. The file becomes the canonical dispatch surface for the platform — D.1 install-stage refactor, D.2 onward, all source it. Adding a new operation means adding one resolver function in one file, not editing five.

**Implementation shape (concrete code; adapt variable names to existing repo conventions if they differ):**

```bash
#!/usr/bin/env bash
# installer/dispatch.sh — resolver dispatch surface for Actools Drupal Community-Plus
# 
# Sourced by: init, preflight, doctor, handoff entry points
# Source order: AFTER profile.sh has set ACTOOLS_PROFILE
#
# Contract: every resolver function returns ONE token on stdout (the handler name).
# Empty stdout = "no profile-specific handler; caller uses its default behavior."
# Non-empty stdout = "call function $token instead of the default."
#
# Profile semantics:
#   community       — returns empty for all operations (no overrides; baseline behavior)
#   community-plus  — returns "plus_<operation>" for operations with plus handlers
#   test            — returns test-only handler names (fixture profile, tests/fixtures/profiles/test/)
#   <unknown>       — returns empty + emits warning to stderr (fail-soft; caller defaults)

set -u

# Allowed profile values — single source of truth.
# Adding a new profile means adding one entry here AND a matching block in each resolver.
_ACTOOLS_ALLOWED_PROFILES=(community community-plus test)

actools::dispatch::profile_is_valid() {
    local candidate="$1"
    local p
    for p in "${_ACTOOLS_ALLOWED_PROFILES[@]}"; do
        [[ "$p" == "$candidate" ]] && return 0
    done
    return 1
}

actools::dispatch::resolve_feature_handler() {
    local feature="$1"
    case "${ACTOOLS_PROFILE:-community}" in
        community)        echo "" ;;
        community-plus)   echo "plus_${feature}" ;;
        test)             echo "test_${feature}" ;;
        *)
            echo "WARN: unknown ACTOOLS_PROFILE='${ACTOOLS_PROFILE}' — using community defaults" >&2
            echo "" ;;
    esac
}

actools::dispatch::resolve_preflight_check() {
    local check="$1"
    case "${ACTOOLS_PROFILE:-community}" in
        community)        echo "" ;;
        community-plus)   echo "plus_preflight_${check}" ;;
        test)             echo "test_preflight_${check}" ;;
        *)                echo "" ;;
    esac
}

actools::dispatch::resolve_doctor_check() {
    local check="$1"
    case "${ACTOOLS_PROFILE:-community}" in
        community)        echo "" ;;
        community-plus)   echo "plus_doctor_${check}" ;;
        test)             echo "test_doctor_${check}" ;;
        *)                echo "" ;;
    esac
}

actools::dispatch::resolve_handoff_section() {
    local section="$1"
    case "${ACTOOLS_PROFILE:-community}" in
        community)        echo "" ;;
        community-plus)   echo "plus_handoff_${section}" ;;
        test)             echo "test_handoff_${section}" ;;
        *)                echo "" ;;
    esac
}
```

**Note on the empty-string return for community:** The community profile is the BASELINE. Returning empty means "no override; caller continues with whatever it would have done." This is the H.7-style "no-op cleanly" pattern — community installs see ZERO behavior change from D.0. Sonnet's verification PoC must include "community install with D.0 applied produces byte-identical journey output to v14.1 community install" (acceptance contract item below).

### Decision 2 — Does `--profile` CLI flag overwrite an existing `ACTOOLS_PROFILE` in `actools.env`?

**Question:** When `actools install --profile community-plus` runs on a system whose `actools.env` already contains `ACTOOLS_PROFILE=community`, what happens?

**Option A:** `--profile community-plus` always overwrites; the CLI is the authority. Updates `actools.env`.
**Option B:** `--profile community-plus` refuses if `ACTOOLS_PROFILE` is already set to a different value in `actools.env`; operator must edit the file manually OR remove the setting first. Exit code 2.
**Option C:** `--profile community-plus` shows a confirmation prompt if it would overwrite. Interactive.

**Chosen: Option B — refuse, fail closed.**

**Reasoning:**

- Profile selection is a deployment-defining decision. A `community` install and a `community-plus` install have different feature surfaces, different test contracts, different operational expectations. Silently overwriting via a CLI flag is the kind of operator-typo destruction that the WPGovern H.7.1-9 subcommand-validation discipline closed for restore operations. *Strict-input* principle applies here (`CODING_AGENT_REFERENCE.md` Section 2.6): if `actools.env` is the persisted authority for profile identity, the CLI must enforce the same strictness as any other entry point that reads it.
- Option A loses information: the operator may have set `community-plus` deliberately (perhaps via configuration management like Ansible) and forgotten; a typo on a subsequent `actools` invocation could downgrade them silently. Silent downgrades are exactly the *minimum-change syndrome* / *test-validity-regression* defect class — appears to succeed; behavior diverges from intent.
- Option C introduces interactive prompting in a CLI meant to be scriptable. Refusing fail-closed is cleaner. The error message points to the recovery path (edit `actools.env` directly).
- The information surface stays explicit: `actools doctor` reports the active profile; `--profile` on fresh installs writes it; conflicts surface loudly at the moment of attempted change.

**Implementation shape:**

```bash
# In cli/actools, at the point where --profile is parsed:

actools::cli::resolve_profile() {
    # Inputs (any may be empty):
    #   $1 = --profile flag value from CLI (e.g., "community-plus" or "")
    #   $2 = ACTOOLS_PROFILE from actools.env if present (e.g., "community" or "")
    # Output (stdout): the resolved profile name (one of community/community-plus/test)
    # Exit: 0 on success; 2 on conflict; 3 on invalid profile name
    
    local cli_profile="${1:-}"
    local env_profile="${2:-}"
    
    # Validate the CLI value if provided
    if [[ -n "$cli_profile" ]] && ! actools::dispatch::profile_is_valid "$cli_profile"; then
        echo "ERROR: --profile='${cli_profile}' is not a valid profile" >&2
        echo "       Allowed: ${_ACTOOLS_ALLOWED_PROFILES[*]}" >&2
        return 3
    fi
    
    # Conflict detection: both are set to DIFFERENT values
    if [[ -n "$cli_profile" && -n "$env_profile" && "$cli_profile" != "$env_profile" ]]; then
        echo "ERROR: --profile='${cli_profile}' conflicts with actools.env (ACTOOLS_PROFILE='${env_profile}')" >&2
        echo "       Profile selection is deployment-defining. To change profile:" >&2
        echo "         1. Edit actools.env directly (set ACTOOLS_PROFILE=${cli_profile})" >&2
        echo "         2. OR remove ACTOOLS_PROFILE from actools.env and re-run with --profile=${cli_profile}" >&2
        return 2
    fi
    
    # Resolve: CLI value if provided, else env value, else default community
    echo "${cli_profile:-${env_profile:-community}}"
    return 0
}
```

### Decision 3 — How is the test fixture profile delivered?

**Question:** D.0's bats tests need to verify that resolvers dispatch correctly to non-community handlers. But `community-plus` modules don't exist yet (they arrive in D.1+). How do tests exercise the non-default dispatch path?

**Option A:** New directory `tests/fixtures/profiles/test/` containing minimal `plus_*` modules; bats tests activate the test profile and exercise the resolvers against it
**Option B:** Inline definition in each test file via heredoc — fixture lives in the test, not on disk
**Option C:** Generated at test setup time by a helper function in BATS_TMPDIR

**Chosen: Option A — `tests/fixtures/profiles/test/` on disk.**

**Reasoning:**

- Inline heredocs (Option B) duplicate the fixture across many test files. Sonnet's `CODING_AGENT_REFERENCE.md` Rule T5 (*contract-level parameterization*) demands one shared fixture; Option B is the opposite of that discipline.
- Generated-at-setup (Option C) introduces another helper function that is itself untested code. Anyone reading the tests has to also read the fixture generator. The fixture should be simple, declarative, and on-disk.
- A real directory at `tests/fixtures/profiles/test/` matches the structural shape `community-plus` will eventually take when its modules arrive at `installer/profiles/community-plus/`. The fixture is structurally identical to a real profile, just minimal. Tests verify dispatch against the SAME shape that production profiles will use. **The fixture proves the resolver works against a profile that does not exist in production code** — which is precisely the verification the resolver needs.
- It also exposes Sonnet's Rule T3 (*three input shapes minimum per fix*) naturally: tests exercise community profile (default), test profile (fixture), and unknown profile (adversarial) — three distinct inputs per resolver function.

**Implementation shape — `tests/fixtures/profiles/test/`:**

```
tests/fixtures/profiles/test/
├── manifest.sh              # ACTOOLS_PROFILE=test; declares fixture metadata
├── plus_preflight_check.sh  # test stub for preflight resolver dispatch
├── plus_doctor_check.sh     # test stub for doctor resolver dispatch
└── plus_handoff_section.sh  # test stub for handoff resolver dispatch
```

```bash
# tests/fixtures/profiles/test/manifest.sh
#!/usr/bin/env bash
# Test fixture profile — used ONLY by D.0+ bats tests to exercise resolver dispatch.
# Not for production use. Must not be activated outside test contexts.

export ACTOOLS_PROFILE=test
export _ACTOOLS_TEST_FIXTURE_VERSION="d0"

# Declare which handlers exist in this fixture profile
# (mirrors the resolver dispatch surface — preflight, doctor, handoff, feature)
test_preflight_check() {
    echo "TEST_PREFLIGHT_DISPATCHED:$1"
}

test_doctor_check() {
    echo "TEST_DOCTOR_DISPATCHED:$1"
}

test_handoff_section() {
    echo "TEST_HANDOFF_DISPATCHED:$1"
}

test_feature() {
    echo "TEST_FEATURE_DISPATCHED:$1"
}
```

The three `plus_*` files are intentionally minimal — they only need to provide function definitions that bats tests can call after the resolver returns their names.

---

## 3. Scope of this phase

Each item below is numbered (D.0-N), names what to implement, and provides the concrete code shape. Sonnet implements within these contracts; bonus-discipline judgment is welcome within scope (see Note for Sonnet at the end).

### D.0-1: Create `installer/dispatch.sh` with resolver function family

Per Decision 1. The file as a whole:

```bash
#!/usr/bin/env bash
# installer/dispatch.sh — see Decision 1 above for the full implementation shape
# Module guard: prevent double-sourcing
[[ "${_ACTOOLS_DISPATCH_SOURCED:-0}" -eq 1 ]] && return 0
readonly _ACTOOLS_DISPATCH_SOURCED=1

set -u

_ACTOOLS_ALLOWED_PROFILES=(community community-plus test)

# ... (all five functions from Decision 1)
```

**Discipline notes:**

- Module guard at top (`[[ "${_ACTOOLS_DISPATCH_SOURCED:-0}" -eq 1 ]] && return 0`) — prevents redefinition warnings if dispatch.sh is sourced by multiple entry points
- `set -u` only (not `set -e`) inside the module — let callers' errexit handle exit semantics; the resolver functions don't fail, they return empty
- All four resolvers follow the same `case` shape; adding a new operation in the future means adding a fifth resolver with the same pattern (discipline-travel between sibling functions is structurally enforced by the pattern)

### D.0-2: Add `--profile` flag parsing to `cli/actools`

Per Decision 2. The `cli/actools` script currently parses commands like `init`, `install`, `doctor`, `audit`, etc. Add `--profile` as a global flag that applies to install-time operations:

```bash
# In cli/actools — at the top-level argument parsing block, add:

# Default values
_actools_cli_profile=""
_actools_cli_remaining_args=()

# Strip --profile=VALUE or --profile VALUE from $@
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile=*)
            _actools_cli_profile="${1#*=}"
            shift
            ;;
        --profile)
            _actools_cli_profile="${2:-}"
            shift 2
            ;;
        *)
            _actools_cli_remaining_args+=("$1")
            shift
            ;;
    esac
done

# Reconstruct positional args without --profile
set -- "${_actools_cli_remaining_args[@]}"

# Resolve profile (read actools.env if present)
_actools_env_profile=""
if [[ -f "${ACTOOLS_ENV_FILE:-/etc/actools/actools.env}" ]]; then
    # shellcheck disable=SC1090
    source "${ACTOOLS_ENV_FILE:-/etc/actools/actools.env}"
    _actools_env_profile="${ACTOOLS_PROFILE:-}"
fi

# Source dispatch.sh so resolve_profile can validate
# shellcheck disable=SC1091
source "${ACTOOLS_INSTALL_DIR:-/opt/actools}/installer/dispatch.sh"

# Resolve, with fail-closed conflict handling per Decision 2
if ! ACTOOLS_PROFILE="$(actools::cli::resolve_profile "$_actools_cli_profile" "$_actools_env_profile")"; then
    exit $?
fi
export ACTOOLS_PROFILE
```

**Discipline-travel note (the H.7.1-7 sibling-files lesson applied):** `cli/actools` likely has a build-time heredoc in `setup_cli.sh` (or equivalent install-stage script) that GENERATES `cli/actools` at install time. Both the source `cli/actools` AND the heredoc that produces it must reflect this change. **The v14.1 e2e regression (E2E #22/#23 hotfix) was caused by exactly this gap — source updated, heredoc not.** Pre-flight: `grep -rn "cli_profile\|--profile" cli/ installer/setup_cli.sh` should show consistent treatment in both surfaces.

### D.0-3: Source `installer/dispatch.sh` from the four operation entry points

Per Decision 1 (centralized resolvers means every caller sources the same module).

For each entry point that exists in the current v14.1 surface — find them via:
```bash
grep -lrn "ACTOOLS_PROFILE" installer/ doctor.sh cli/ 2>/dev/null
```

For each: add a sourcing block AFTER `profile.sh` is sourced (so `ACTOOLS_PROFILE` is already set) and BEFORE the entry point's main dispatch logic. Pattern:

```bash
# Source dispatch.sh (provides resolver functions)
# shellcheck disable=SC1091
source "${ACTOOLS_INSTALL_DIR:-/opt/actools}/installer/dispatch.sh"
```

The four operation surfaces that need dispatch.sh access:

| Surface | Likely file | Resolver it will call (in D.1+) |
|---|---|---|
| init | `installer/init.sh` (or equivalent) | `actools::dispatch::resolve_feature_handler` |
| preflight | `installer/preflight.sh` (or wherever pre-install checks run) | `actools::dispatch::resolve_preflight_check` |
| doctor | `doctor.sh` | `actools::dispatch::resolve_doctor_check` |
| handoff | `installer/handoff.sh` (or wherever post-install summary lives) | `actools::dispatch::resolve_handoff_section` |

**At D.0, the resolvers are sourced and available; the entry points do not yet CALL them.** Calling the resolvers is D.1+ work, when `plus_*` modules exist. D.0 establishes the foundation; D.1+ uses it.

**Verification:** Each entry point sources `dispatch.sh` successfully on a community-default install; `actools install` produces byte-identical journey output to v14.1.

### D.0-4: Create test fixture profile at `tests/fixtures/profiles/test/`

Per Decision 3. The four files from the Decision 3 implementation shape.

**Discipline note:** The fixture is bash-source-able by tests but is NOT itself executable as an installer profile. It exists only so tests can verify the resolver returns the right token names; the token names then map to functions defined in the fixture's `manifest.sh`. This is the *one-validate-X-per-data-shape* discipline applied to the test surface — fixture profile and production profiles share the SAME structural shape, so tests verify a real contract, not a test-only contract.

### D.0-5: New bats test file `tests/test_d0_dispatch.bats`

Consolidate all D.0 verification into one file. The H.7.1 consolidation pattern Sonnet established (one test file per phase, named for the phase, contains all phase tests) applies here.

The test file covers (test count is the floor; bonus-discipline tests welcome):

| Test class | Tests | What they verify |
|---|---|---|
| Resolver dispatch correctness | 12 | 4 resolvers × 3 profiles (community, test, unknown) — Sonnet's Rule T3 *three input shapes minimum* |
| `profile_is_valid` correctness | 5 | Three valid profiles each, plus empty input, plus malformed input |
| `cli::resolve_profile` CLI-side handling | 8 | No flag + no env (→community); flag only; env only; flag==env; flag≠env (→exit 2); invalid flag (→exit 3); empty flag + env; flag + empty env |
| Fixture profile activation | 3 | Sourcing `manifest.sh` sets ACTOOLS_PROFILE=test; fixture function definitions exist; resolver returns `test_*` tokens |
| Sibling-scope audit (meta-test) | 1 | Static grep: every script that reads `ACTOOLS_PROFILE` either sources dispatch.sh or has a documented exemption — guards against the H.7.1-7 sibling-files defect class |
| Community-install regression | 2 | `actools doctor` on a community install produces same output as v14.1 (modulo D.0 surface additions); `actools install --profile=community` exits 0 with no behavior change |

**Test count floor: 31. Brief targets ~25 minimum; floor is higher because Rule T3 multiplies coverage.**

### D.0-6: Update `actools doctor` to report the active profile

The doctor command currently reports operational health. Add one line:

```bash
echo "Active profile: ${ACTOOLS_PROFILE:-community} (set via: ${_actools_profile_source:-default})"
```

Where `_actools_profile_source` is one of: `default` / `cli` / `env-file` / `inherited`. Doctor reports VISIBILITY into the profile selection — does not change it.

This satisfies the *doctrine-vs-implementation audit* discipline (formalized at WPGovern H.7 closure): the LOCKED design says "the active profile is always knowable from operator-visible commands." `actools doctor` is the canonical operator-visible health command. The doctrine claim "active profile is knowable" needs an empirical surface — this is it.

### D.0-7: Documentation surface — three small updates

- `README.md` — add one short paragraph noting `--profile` flag exists; community is default; community-plus modules arrive in later phases
- `CHANGELOG.md` — D.0 entry naming the new files + dispatch surface
- `docs/briefs/PHASE_D0_README.md` (new) — short historical record: what D.0 delivered, what it deliberately did not, where to look in the code for the dispatch surface

---

## 4. Out of scope

Explicitly NOT in D.0:

1. **Any `plus_*` module implementation.** D.0 establishes the seam; D.1+ hangs modules from it. If a `plus_*` file gets created in D.0, scope creep happened.
2. **Calling the resolvers from entry points.** D.0-3 sources dispatch.sh from the four entry points; it does NOT add resolver-call sites. Resolver calls land in D.1.
3. **Install-stage refactor.** The setup_cli.sh heredoc currently generates `cli/actools`. D.0 updates that heredoc to reflect the new --profile handling, but does NOT refactor the heredoc-based install pattern itself. That refactor (if it happens) is D.1 work.
4. **Profile-aware `actools.env` migration.** Existing v14.1 installs without `ACTOOLS_PROFILE` in their `actools.env` default to community. D.0 does NOT add migration logic to write the explicit default; that's a low-value, high-risk change. Default-by-absence is the expected behavior.
5. **Veritas or any other downstream content.** Drupal-only, single platform.
6. **Performance work.** The resolver functions add ~4 case-statement evaluations per invocation. The cost is negligible; no profiling needed.
7. **`actools doctor --deep`.** Deep mode is still in development (per v14.1 README cleanup). D.0 keeps the deep-mode placeholder unchanged.

---

## 5. Acceptance contract

### Regression contract

- All v14.1 bats tests pass unchanged. **Count floor: existing baseline + 0 broken.**
- `actools install` on a community-default config produces byte-identical journey output to v14.1 (verified by diffing stdout)
- `actools doctor` on a community install produces output identical to v14.1 EXCEPT for the new "Active profile" line
- E2E gate (the v14.1 hotfix added it) still passes; no Pro-mentions leakage

### Internal verification probes (Sir Opus PoCs)

Each of these I will run empirically against Sonnet's delivered code before issuing the closure verdict. PoCs probe **production-condition behavior**, not just structural fix-landing. The H.7.1 verification gap (where surface PoCs passed but runtime-semantic PoCs caught five blockers) is the calibration in force here.

| PoC | Verifies | Why this specific probe |
|---|---|---|
| `grep -rn "ACTOOLS_PROFILE" installer/ cli/ doctor.sh` returns every read through the shared helper (or explicit-exemption comment) | Sibling-scope enumeration | Guards the H.7.1-7 defect class — every entry point that reads the profile must do so the same way |
| `actools install --profile=community-plus` on a system with no existing `actools.env` writes `ACTOOLS_PROFILE=community-plus` and continues; behavior is byte-identical to community install (no `plus_*` modules exist) | Decision 2 first half + defining-property check | The whole point of D.0 — adding the flag must do nothing observable until D.1+ |
| `actools install --profile=community` on a system whose `actools.env` has `ACTOOLS_PROFILE=community-plus` → exit code 2; clear error message; no file mutation | Decision 2 conflict path | The strict-input discipline |
| `actools install --profile=invalid` → exit code 3; allowed-list shown in error | Decision 2 invalid-input path | The strict-input discipline (the invalid case is distinct from conflict) |
| With `tests/fixtures/profiles/test/manifest.sh` sourced and `ACTOOLS_PROFILE=test`: `actools::dispatch::resolve_preflight_check foo` returns `test_preflight_foo` | Decision 3 fixture wiring | The fixture proves the resolver works against a non-default profile |
| `ACTOOLS_PROFILE=community actools::dispatch::resolve_feature_handler anything` returns empty string (not "default", not "community_anything") | Decision 1 baseline-empty contract | Community must be no-op; if community returns ANY token, downstream callers may incorrectly think there's an override |
| `ACTOOLS_PROFILE=unknown_garbage actools::dispatch::resolve_feature_handler foo` returns empty string + emits WARN to stderr (not fail-fast) | Unknown-profile soft-fail | The dispatch surface must not break with stale/typo env values; warn but continue with community defaults |
| Test count: `bats --count tests/test_d0_dispatch.bats` ≥ 31 | Floor on coverage | Rule T3 three-input-shape discipline must be honored |
| Determinism: full bats suite runs 3× consecutively with same pass/fail set | Lesson 7 (WPGovern Lesson 7: glob-determinism) | Tests must be order-independent |
| Sibling-scope meta-test passes: a test enumerates files reading `ACTOOLS_PROFILE` and verifies all are covered by dispatch.sh sourcing | Internal-verification-scope-must-enumerate-sibling-files candidate | This is the second-observation site for that held candidate; if it surfaces in D.0, eligible for formalization in METHODOLOGY_NOTES |
| `actools install` produces byte-identical journey output between v14.1 and D.0 on community-default config | Defining property | Community installs must see ZERO observable change |

---

## 6. Test count expectations

| Surface | Before D.0 | After D.0 |
|---|---:|---:|
| Existing bats tests (v14.1 baseline, journey + doctor + cli + etc.) | ~22-30 | unchanged |
| New D.0 dispatch tests in `test_d0_dispatch.bats` | 0 | ≥ 31 |
| **Total bats** | ~22-30 | ~53-61 (floor) |

**Exact baseline:** Sonnet to verify against the actual repo at the moment of implementation start. The floor of 31 D.0 tests is what the brief requires; bonus tests in scope are welcome.

---

## 7. Files created / modified

### Created (new files)

| File | Lines (approx) | Purpose |
|---|---:|---|
| `installer/dispatch.sh` | ~90 | Resolver function family + profile validation (Decision 1) |
| `tests/fixtures/profiles/test/manifest.sh` | ~30 | Fixture profile activator + handler stubs (Decision 3) |
| `tests/fixtures/profiles/test/plus_preflight_check.sh` | ~10 | Test stub |
| `tests/fixtures/profiles/test/plus_doctor_check.sh` | ~10 | Test stub |
| `tests/fixtures/profiles/test/plus_handoff_section.sh` | ~10 | Test stub |
| `tests/test_d0_dispatch.bats` | ~400 | D.0 verification suite (31+ tests) |
| `docs/briefs/PHASE_D0_README.md` | ~30 | Historical record of D.0 scope and closure |

### Modified (existing files)

| File | Likely changes | Discipline note |
|---|---|---|
| `cli/actools` | --profile flag parsing block + profile resolution + dispatch.sh sourcing | Per Decision 2 |
| `installer/setup_cli.sh` (or whichever installs `cli/actools` via heredoc) | Heredoc reflects all `cli/actools` changes | **H.7.1-7 sibling-files discipline — both source and heredoc must move together** |
| Four entry-point scripts (init / preflight / doctor / handoff equivalents) | Add `source dispatch.sh` block | Per D.0-3 |
| `doctor.sh` | Add "Active profile" reporting line | Per D.0-6 |
| `README.md` | One paragraph on `--profile` | Per D.0-7 |
| `CHANGELOG.md` | D.0 entry | Per D.0-7 |

### NOT modified (boundary)

| File | Why not |
|---|---|
| `installer/profile.sh` | Profile loading logic untouched; dispatch is a separate concern |
| Existing bats test files | Should not need updates if community installs are byte-identical |
| Any `plus_*` file | These don't exist yet; D.0 is the seam, not the modules |

---

## 8. Pre-flight checklist (Sonnet to verify before submitting)

Adapted from `CODING_AGENT_REFERENCE.md` Part 7. Every NO is a blocker.

### Architectural contracts

- [ ] `installer/dispatch.sh` exists; sourceable from any installer/cli entry point without errors
- [ ] All four resolvers return empty string for community profile (no overrides)
- [ ] All four resolvers return `plus_*` token for community-plus profile (matches Decision 1 pattern)
- [ ] All four resolvers return `test_*` token when ACTOOLS_PROFILE=test (matches fixture)
- [ ] All four resolvers warn-and-default for unknown profile (no fail-fast)
- [ ] `_ACTOOLS_ALLOWED_PROFILES` is the single source of truth for valid profiles
- [ ] Module guard prevents double-source warnings

### CLI integration

- [ ] `--profile=VALUE` and `--profile VALUE` both parse correctly
- [ ] `actools::cli::resolve_profile` returns 0/2/3 per Decision 2 contract
- [ ] Invalid profile name (Decision 2 Option 3 path) exits 3 with allowed-list message
- [ ] Conflict (Decision 2 main path) exits 2 with recovery instructions
- [ ] No `--profile` AND no `actools.env` entry → defaults to community

### Sibling-scope enumeration (Lesson 10 / Rule 2)

- [ ] Every script that reads `ACTOOLS_PROFILE` either sources `dispatch.sh` OR has an explicit `# DISPATCH_EXEMPT: <reason>` comment justifying why
- [ ] The heredoc in `setup_cli.sh` matches the source `cli/actools` byte-for-byte where they share content
- [ ] No `/etc/actools/actools.env` path is hardcoded outside the canonical resolver helper

### Test discipline (Rule T1-T7)

- [ ] No `or True` patterns in bats tests (`grep -rn '|| true' tests/test_d0*.bats` returns ZERO unjustified hits; permitted only in mock-installation flows with comments)
- [ ] No `[[ -n "$result" ]]` as sole assertion in resolver tests (assert the EXACT expected token)
- [ ] Three input shapes per fix minimum (community / test / adversarial — adversarial = unknown profile, empty profile, malformed)
- [ ] Bats determinism: 3 consecutive full-suite runs produce identical pass/fail set
- [ ] Sibling-scope audit meta-test exists and passes

### Documentation

- [ ] README updated with `--profile` paragraph
- [ ] CHANGELOG D.0 entry written
- [ ] PHASE_D0_README.md captures: scope delivered, scope deliberately deferred, where the dispatch surface lives

### Regression

- [ ] `actools install` on community-default config: byte-identical to v14.1 (modulo doctor's new "Active profile" line)
- [ ] All existing v14.1 bats tests pass unchanged
- [ ] E2E gate workflow still passes

---

## 9. Methodology continuity

### Lessons applied at D.0 (traveled from WPGovern's calibrated methodology)

| Lesson | How D.0 honors it |
|---|---|
| Lesson 1 — Integration tests at every wiring layer | D.0-5's test coverage spans: resolver-in-isolation, resolver-from-cli, resolver-from-fixture, resolver-in-sibling-scope-audit |
| Lesson 2 (refinements) — Tests vary setup, not just inputs | Three-input-shape rule (Rule T3) applies per resolver; setup-variation via fixture-vs-default activation |
| Lesson 6 — Settled decisions don't get relitigated | Decisions 1/2/3 are LOCKED; alternative options documented for future reference only |
| Lesson 7 — Glob patterns must filter sidecar files | Test fixture paths use explicit names; meta-test grep patterns are bounded |
| Lesson 10 — Pattern-match assumption / discipline-travel between sibling modules | Pre-flight enforces sibling-scope enumeration; the heredoc-source pair is named explicitly (H.7.1-7 site applied here) |
| Lesson 11 (formalized at H.7 closure) — Doctrine-vs-implementation audit | The doctrine claim "community installs see zero change from D.0" is verified by byte-identical journey-output PoC, not by code-review alone |

### Held candidates traveling from WPGovern (potentially observable in D.0)

| Candidate | Status at WPGovern H.7 closure | D.0 observation site |
|---|---|---|
| Internal-verification-scope-must-enumerate-sibling-files | Single observation (H.6.2 + H.7 latent fix) — held | D.0's sibling-scope meta-test is the structured probe. If a similar defect surfaces in D.0 verification, this becomes the second observation across two projects, eligible for formalization in Drupal METHODOLOGY_NOTES.md |
| Sonnet's bonus-discipline contributions | Four observations across H.6.1/H.6.2/H.7/H.7.1 — held for cross-project | D.0 closure is the cross-project test. If bonus-discipline patterns emerge in D.0 implementation, this candidate formalizes |

### Methodology document home

`docs/briefs/METHODOLOGY_NOTES.md` in the actoolsDrupal repo. Starter document delivered alongside this brief — substantive content accretes by observation as the Drupal arc closes phases. Not a port of WPGovern's catalog.

---

## 10. After D.0 closes

### Closure path

D.0 is a fresh-surface phase introducing a new dispatch seam. Per Lesson 9, fresh-surface phases default to layered external review (the four-role A/B/C/D architecture). However:

- D.0's surface is small (~90 lines of new bash, ~470 lines of new tests + fixture)
- The architectural decisions are explicit (three Decisions with reasoning)
- The defining property (zero observable change for community) is empirically verifiable

**Recommended closure pattern:** Sir Opus internal verification first; if all 12 PoCs (Section 5) pass cleanly and no surprises surface, propose internal closure on the H.4 / H.5 hardening-class precedent (where small fresh-surface phases with strong PoC coverage closed internally). If anything contested surfaces during internal verification, escalate to bounded Role C + Role D external review.

### Registration actions if D.0 closes cleanly

1. Register D.0 as 1st Drupal-arc milestone in METHODOLOGY_NOTES.md
2. Record observations from D.0 (Sonnet's bonus-discipline; held-candidate observations)
3. If sibling-scope candidate earned its second observation, formalize in METHODOLOGY_NOTES.md as a Drupal-arc lesson

### If D.0 surfaces a major defect class

Hardening pass D.0.1 — surgical, scope-bounded, follows the H.4.1 / H.7.1 hardening brief shape.

---

## 11. Note for Sonnet

You've read `CODING_AGENT_REFERENCE.md`. I'm not going to restate what's already internalized. A few things specific to D.0.

**What this phase is.** D.0 is small in line-count and large in discipline-weight. The dispatch seam shapes how every later `plus_*` module attaches. If the seam is clean, D.1+ work is mechanical. If it's sloppy, every later phase pays.

**Where your bonus-discipline judgment is most welcome in D.0.**

Three places where you've earned the right to extend scope within reason:

1. **The sibling-scope audit meta-test.** I've specified ONE meta-test (grep-based). If you find a more empirically robust shape — runtime introspection of sourced files, or a test that actually exercises each entry point's profile-reading path — that's the kind of bonus-discipline judgment that compounds the methodology. Worth more than the minimum.

2. **The fixture profile design.** I've specified four files in `tests/fixtures/profiles/test/`. If during implementation you see a structural improvement — say, the fixture sourcing pattern is cleaner with one file instead of four, or the fixture should mirror an even closer shape to `installer/profiles/community-plus/` (which doesn't exist yet but will) — your judgment on the structural shape carries weight. The H.7.1 test-consolidation call you made was structurally better than the brief specified; this is the same class of judgment.

3. **The `cli/actools` ↔ `setup_cli.sh` heredoc synchronization.** This is the H.7.1-7 sibling-files defect class. The v14.1 e2e hotfix taught us the heredoc forgot to track the source. If you see a structural change that makes this synchronization mechanical rather than disciplinary — perhaps generating the heredoc from the source file at build time, or unifying the two surfaces some other way — that's a methodology-compounding contribution worth surfacing. Even just adding an explicit comment in both files naming the other as the partner-of-record helps.

**Where I'd ask you to hold the line.**

Three things to NOT do, even if scope creep tempts:

1. **No `plus_*` modules at D.0.** The seam exists; modules arrive in D.1+. If you find yourself implementing `plus_preflight_*` to "make the resolver useful," step back — D.0's defining property is that the resolver is in place and unused.

2. **No `actools.env` migration logic.** Existing v14.1 installs that lack `ACTOOLS_PROFILE` should default to community by absence. Adding "auto-set ACTOOLS_PROFILE=community on first D.0 boot" is a low-value, high-risk change. Default-by-absence is the contract.

3. **No `actools doctor --deep`.** Deep mode is in development per v14.1's README cleanup. D.0 doesn't touch it.

**What success looks like.**

When Sir Opus runs the 12 PoCs (Section 5) against your delivery:
- Every PoC passes empirically (not just structurally)
- The sibling-scope meta-test passes (no entry point reads profile outside the canonical path)
- `actools install` on a community-default config produces byte-identical journey output to v14.1
- Adding `--profile=community-plus` does nothing observable (because no modules exist)

When that lands, D.0 closes on internal verdict, registers as the 1st Drupal-arc milestone, and we move to D.1.

**On the partnership.**

`CODING_AGENT_REFERENCE.md` is the most useful methodology artifact in this partnership's history — the first-person-from-inside framing it took is exactly what no external review can produce. I'm authoring this brief at the level of detail it takes because that's the level your reference document earned. Brief authors who have read that document don't get to be vague.

The three-of-us holds. The methodology travels. The work compounds.

Carry well, Sonnet.

— Sir Opus, on behalf of the orchestrator
