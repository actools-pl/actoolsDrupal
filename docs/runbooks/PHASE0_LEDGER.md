# Phase 0 Ledger

## Purpose

This ledger is the durable memory of the project. Update it after every phase, even if no code changed.

## Current status

Phase 0 status: NOT CLOSED  
Community-plus Phase 1 status: BLOCKED

## Ledger entry template

````markdown
## Entry 000 — Title

Date:
Branch:
Commit SHA:
Actor / Claude session (model):
Phase:
Task prompt source:

### Objective

### Files changed

- 

### Files intentionally not changed

- 

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
|  |  |  |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml |  |  |
| Caddyfile |  |  |
| my.cnf |  |  |
| Dockerfiles |  |  |
| CLI |  |  |

### Tests run

```bash
# paste exact commands
```

### Test result

PASS / FAIL / PARTIAL

### Documentation updated

- [ ] Runtime authority map
- [ ] Generated-file contract
- [ ] CLI authority contract
- [ ] Operator target docs
- [ ] Test plan

### Changelog / release notes

- [ ] CHANGELOG.md updated
- [ ] Release note added
- [ ] Test report added
- [ ] Review notes added

### Known risks

### Blockers

### Review Gate decision

Approved / Needs revision / Blocked

### Next safe task

### Forbidden next scope
````

## Entry 011 — P0-F · CLI Authority Consolidation

Date: 2026-06-09
Branch: `phase0/P0-F-cli-authority`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-F — CLI Authority Consolidation
Task prompt source: `P0-F-cli-authority.md` + coding-window prompt (filled, archived)

### Objective

Collapse the two divergent operator CLIs into **one canonical source**. Adopt
**Option A**: `cli/actools` is canonical; the installer (`setup_cli`) installs it
by copying it verbatim; the duplicate `cat > /usr/local/bin/actools <<HELPER`
generator is deleted. Preserve safe secret handling, retain every command's
behavior (parity matrix), declare the CLI **Changed intentionally** while proving
the six non-CLI generated files stay byte-identical (golden drift 6/6).

### Decision (Option A)

Option A over Option B because no runtime substitution is required: the CLI reads
all install-time state at runtime (`ACTOOLS_HOME`, `actools.env`, `.actools-state.json`).
The single value the heredoc baked in (`INSTALL_DIR`) is now resolved at runtime
via `INSTALL_DIR="${ACTOOLS_HOME:-$(self-locate)}"`. `setup_cli` already writes
`ACTOOLS_HOME` to `/etc/environment`; the fallback covers in-repo execution
(tests, `./cli/actools`). Because the installed file is a verbatim copy, the CLI
is **no longer a generated artifact** and is removed from the golden-fixture set;
its integrity is proven directly by an installed==source test.

### Files changed

- `cli/actools` — **now the single canonical CLI.**
  - `:7` `INSTALL_DIR="${ACTOOLS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"`
    (was self-location only) so the verbatim copy resolves correctly at
    `/usr/local/bin/actools`.
  - Stale comment (old `:12-15`, "no setup_cli.sh heredoc generator… audited")
    **rewritten** to describe install-by-copy and point at the contract.
  - `update` — snapshot switched to the **safe** `--defaults-extra-file` path
    (password fed via stdin into a temp cnf created **inside** the db container
    with `umask 077` + `trap` cleanup; never in argv), reusing the already-loaded
    `BACKUP_PASS` and keeping its guard; **kept** static's strict `exit 1` +
    rollback hint and `pull db redis php_prod`; **changed** the `drush updb` loop
    to env-driven (`for env in $(echo "${ENVIRONMENTS:-prod}" | tr ',' ' ')`).
  - `restore` / `restore-test` — root DB ops switched to
    `docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"'`
    (password from the db container's own env var, never in argv); removed the now
    **dead** `[[ -z "$DB_ROOT_PASS" ]]` guards (`DB_ROOT_PASS` is not exported to
    the host); kept confirmation/checksum/glob and the backtick-escaped DB name;
    **kept** `restore-test`'s `.restore-test-last` marker (consumed by
    `cli/commands/doctor.sh:194`); **dropped** the generated CLI's S3 reachability
    chain (accepted consequence — no functional dependency, avoids noise on
    non-S3 installs).
  - `storage-info` — `ENV_FILE` `/home/actools/actools.env` → `${INSTALL_DIR}/actools.env`.
  - `migrate` — `Current mode: local` → `Current mode: ${XELATEX_MODE:-local}`.
  - `health` — loop made env-driven (matches generated; identical for community).
  - **`audit` command added** (ported verbatim from the generated CLI; sets
    `ACTOOLS_HOME`, sources `modules/audit/lib/output.sh`, runs
    `modules/audit/audit.sh "${@:2}"`) + `audit` entries added to both help tiers.
    Parity preservation: the module already ships; only `--deep` is edition-gated.
- `actools.sh` — `setup_cli()` (`:1247-1262`): the `HELPER` heredoc (old
  `:1251-1520`) and the dead `local backup_pass=$(get_backup_pass)` removed;
  replaced with `install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools`;
  `chmod +x` / `log` / `ACTOOLS_HOME` write tail kept. `setup_stack` (`:569-1028`)
  untouched. (`get_backup_pass` retained — still used at `:588/:1169/:1629`.)
- `tests/helpers/capture_golden_outputs.sh` — `SC_END` 1528 → **1262**
  (`SC_START` 1247, `SS_*` unchanged); the PHASE-2 CLI render and the PHASE-3
  `actools-cli` copy removed; `actools-cli` dropped from the PHASE-4 sha manifest;
  orphaned `FIXED_CLI_INSTALL_DIR` removed. The `_assert_fn_range "setup_cli"`
  **drift guard is kept and updated** (range-checked though no longer rendered).
- `tests/fixtures/golden/{default,redis-off,s3-on,cadvisor-on,all-in-one}/` —
  `actools-cli` fixture deleted; each `SHA256SUMS` reduced to **6** entries by
  removing only the `actools-cli` line (the six stack-file sums are **byte-for-byte
  preserved**, so a passing drift run proves the non-CLI files are unchanged).
- `tests/generated/golden_drift_test.bats` — meta-test manifest-entry assertion
  7 → **6**.
- `tests/installer/cli_authority_test.bats` — **new, 14 tests.**
- `docs/architecture/cli-authority-contract.md` (Option A decision + 12-row matrix
  filled + Status: satisfied), `docs/architecture/runtime-authority-map.md`
  (CLI-install / Generated-CLI / Doctor / Handoff rows; test count 119→133),
  `docs/CHANGELOG.md`, `docs/releases/P0-F-cli-authority.md`,
  `docs/tests/P0-F-cli-authority.md`, `docs/runbooks/HANDOFF-P0-F.md`, and this
  ledger entry (Entry 011).

### Files intentionally not changed

- `actools.sh::setup_stack()` and the six non-CLI generators (`my.cnf`,
  `Dockerfile.{caddy,php,worker}`, `Caddyfile`, `docker-compose.yml`) — **not
  touched**; golden drift 6/6.
- `modules/audit/*` — the `audit` command was **wired**, not authored; the module
  ships as-is.
- `cli/commands/*.sh` — unchanged (the `.restore-test-last` consumer in
  `doctor.sh` verified intact by a test).
- `modules/dr/resurrect.sh` — its independent `actools-real` copy is **out of
  scope** (P0-J).
- The harness range guard was **updated, not widened or disabled**.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| CLI source | **two** divergent CLIs: a generated `HELPER` heredoc in `setup_cli` **and** static `cli/actools` | **one** canonical source: `cli/actools`; installer copies it verbatim |
| CLI install (`setup_cli`) | `cat > /usr/local/bin/actools <<HELPER …` (install-time `$`/`$()` expansion) | `install -m 0755 "${INSTALL_DIR}/cli/actools" …` (verbatim copy) |
| CLI `INSTALL_DIR` resolution | heredoc baked `INSTALL_DIR=<literal>` | runtime `"${ACTOOLS_HOME:-<self-locate>}"` |
| CLI golden coverage | rendered `actools-cli` fixture in all 5 variants (7-entry manifests) | **no CLI fixture** (6-entry manifests); installed==source proven by `cli_authority_test.bats` |
| DB secrets in CLI | snapshot `-p"$BACKUP_PASS"`; root ops `-p"$DB_ROOT_PASS"` (argv-visible) | snapshot `--defaults-extra-file` (umask 077 + trap); root ops `MYSQL_PWD` in-container — **never in argv** |
| `audit` in static CLI | absent | present (parity) |
| Install path / `setup_stack` | dispatcher-driven (P0-D) | **unchanged** |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | no generator edited; golden drift 6/6 |
| Caddyfile | Not touched | no generator edited; golden drift 6/6 |
| my.cnf | Not touched | no generator edited; golden drift 6/6 |
| Dockerfiles | Not touched | no generator edited; golden drift 6/6 |
| CLI (`actools-cli`) | **Changed intentionally** | CLI authority consolidated to `cli/actools` (Option A); CLI is no longer generated; `actools-cli` fixture retired; installed==source proven by `cli_authority_test.bats`. See release note. |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline @ aa881de):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6 (six non-CLI files byte-identical)
bats tests/installer/cli_authority_test.bats                                # 14/14 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# Syntax:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# Secret-safety static check (in the new suite):
grep -nE '(-p"?\$|--password=)' cli/actools                                 # no matches
```

### Test result

PASS — golden drift **6/6** before and after (six non-CLI generated files
byte-identical; `actools-cli` fixture retired by design). Unit/integration
**127/127** (113 prior + 14 new), **133/133** overall. All `bash -n` clean. No
password-in-argv pattern remains in `cli/actools`.

### Documentation updated

- [x] Runtime authority map — CLI-install / Generated-CLI / Doctor / Handoff rows; test count 119→133
- [ ] Generated-file contract — no change to the doc itself (the CLI's "Changed intentionally" status is recorded in the release note, per its rule)
- [x] CLI authority contract — Option A decision recorded + 12-row parity matrix filled + Status: satisfied
- [ ] Operator target docs — none this phase
- [x] Test plan / report — `docs/tests/P0-F-cli-authority.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → P0-F section)
- [x] Release note added — `docs/releases/P0-F-cli-authority.md` (incl. Rollback + "Changed intentionally" justification)
- [x] Test report added — `docs/tests/P0-F-cli-authority.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **CLI is now "Changed intentionally" (not byte-identical).** This is the first
  generated-file behavior change in Phase 0. It is bounded by the parity matrix
  and justified in the release note; the six **non-CLI** generated files remain
  byte-identical (drift 6/6). A reviewer should read the matrix, not just the
  drift result.
- **`INSTALL_DIR` now trusts `ACTOOLS_HOME`.** On an installed host this is set by
  `setup_cli`; if `/etc/environment` is wiped, the CLI falls back to self-location
  which, from `/usr/local/bin`, resolves to `/usr/local` (wrong). The risk is the
  same class the heredoc baked around; mitigated because `setup_cli` always
  (re)writes `ACTOOLS_HOME` at install. Tests pin `ACTOOLS_HOME` for determinism.
- **Dropped `restore-test` S3 reachability chain.** Operators who relied on
  `restore-test` implicitly running `storage-test` must call `actools storage-test`
  explicitly. Documented in the release note.
- **Installed CLI gains `tunnel` and a 2-tier `help`** (previously only in static)
  and the `audit` command. These are additive; documented.
- **`worker-run`** keeps the static `drush queue:run …` (the generated CLI's
  `xelatex --version` anomaly is intentionally dropped). Documented.

### Blockers

None.

### Review Gate decision

Pending — a **separate session (ideally a different model)** renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) the six non-CLI
generated files are byte-identical (drift 6/6) and the CLI's "Changed
intentionally" status matches the parity matrix; (2) only allowed files touched;
(3) `setup_cli` installs by verbatim copy with no heredoc and the installed CLI
equals `cli/actools`; (4) **no** DB password appears in any argv (snapshot uses a
defaults file, root ops use `MYSQL_PWD` in-container) and the temp cnf uses
`umask 077` + trap; (5) the harness range guard is updated (SC_END=1262) and
green, not widened/disabled.

### Next safe task

**P0-G — Host/stack extraction**, or **P0-H — Surface wiring** (the Review Gate
owns sequencing). With the CLI consolidated, the remaining generated-file authority
work (extracting `setup_stack`'s host/stack heredocs into `modules/*` behind the
dispatcher, with golden fixtures) can proceed independently of CLI concerns.

### Forbidden next scope

No host/stack extraction in this phase (that is P0-G); no community-plus feature
commands beyond the existing stubs/gates; no broad rewrite of command behavior
beyond the documented parity matrix; no touching `setup_stack` or the six non-CLI
generators; no widening or disabling the golden harness range guard.

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. P0-F removes the CLI duplication and locks
the CLI to a single safe source, but wires no community-plus feature.

---

## Entry 010 — P0-E · Profile Validation and Resolver Contract

Date: 2026-06-09
Branch: `phase0/P0-E-profile-validation-and-resolver`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-E — Profile Validation and Resolver Contract
Task prompt source: `P0-E-profile-validation-and-resolver.md` + coding-window prompt (filled, archived)

### Objective

Make profile selection **safe at `init` time** and **complete the resolver
contract** to the LOCKED shape — with community behaviour byte-identical and **no
community-plus feature work**. Two pieces: (1) `init` sources `profile.sh`,
validates the `.profile` file exists, and enforces governance flags **before
persisting** `actools.env`; (2) `resolve_feature_handler` becomes 3-tier
path-resolution (alignment §4.1) and a LOCKED-named `resolve_profile_check`
umbrella (alignment §4.2) is added, both as internal primitives still **uncalled
on the live path** (their callers are P0-H).

### Scope note (P0-D handoff superseded by the P0-E spec §1)

The P0-D handoff named the next task as "replace the hardcoded
`source community.profile` in `main()` with `ACTOOLS_PROFILE`-driven selection."
The P0-E spec (and its operationalized prompt §1) explicitly **corrects** that:
`actools.sh` is **not** in P0-E's allowed files and must not be touched; wiring
the install path to the selected profile is **P0-H**. P0-E therefore changes **no
runtime install behaviour** — the only live behavioural change is in the `init`
command. `actools.sh` is byte-identical (`git diff HEAD -- actools.sh` empty).

### Files changed

- `installer/init.sh` — sources `installer/profile.sh` for the chosen profile;
  **validates the `.profile` file exists and fails before persisting**
  `actools.env` (exit 3 when absent); enforces `PROFILE_REQUIRES_ACTOR` /
  `PROFILE_REQUIRES_CHANGE_TICKET` via the existing `profile_requires_actor`
  (`profile.sh:38`) / `profile_requires_change_ticket` (`profile.sh:39`); consumes
  `PROFILE_INIT_FIELDS` via `profile_init_fields` (`profile.sh:40`). Adds
  `--actor-id` / `--change-ticket` (and `=` forms), **validated but not
  persisted** (governance identity recording is P0-H). `ACTOOLS_PROFILE` is
  declared **local** in `run_init` so init never leaks profile identity. All four
  accessors already existed — this is **wiring, not authoring**.
- `installer/dispatch.sh` —
  - `actools::dispatch::resolve_feature_handler` rewritten to **3-tier PATH
    resolution** (alignment §4.1): Tier 1 `profiles.d/${ACTOOLS_PROFILE}/commands/${feature}.sh`
    → Tier 2 `modules/${module}/${feature}.sh` (module the active profile lists
    via the internal `PROFILE_FEATURE_MODULES`, read `+x`-guarded for `set -u`
    safety) → Tier 3 `cli/commands/${feature}.sh`. First existing path wins, else
    empty. **community short-circuits to empty before the search** (byte-identical,
    non-negotiable). Unknown profile → WARN + empty (preserved fail-soft).
  - **new** `actools::dispatch::resolve_profile_check <surface> <check_id>`
    (alignment §4.2) — umbrella delegating to `resolve_preflight_check` /
    `resolve_doctor_check` / `resolve_handoff_section`; unknown surface → WARN +
    empty. The per-surface resolvers are **kept as the internals**.
  - File header updated to document the **return-shape asymmetry** (feature →
    path; preflight/doctor/handoff → token; install-stage → function name;
    profile-check → delegated token).
- `tests/installer/init_profile_test.bats` — **new**, 10 tests (init-time
  validation, governance fire, non-persistence, community preserved).
- `tests/test_d0_dispatch.bats` — **+15 tests** (33 → 48): 3-tier order (Block 9),
  `resolve_profile_check` delegation (Block 10), side-effect-free loading +
  negative control (Block 11). The single community-plus `resolve_feature_handler`
  test was updated from the `plus_doctor_deep` token to the resolved tier-3 path.
- `tests/fixtures/profiles/fake-actor.profile`, `…/fake-ticket.profile` —
  **new test-only fixtures** (never shipped; staged as `profiles/test.profile`).
- `tests/installer/init_test.bats` — setup now stages `dispatch.sh`, `profile.sh`,
  and `community.profile` into the sandbox so the 11 existing tests exercise the
  real (profile-sourcing) init flow under `set -u`.
- `docs/architecture/runtime-authority-map.md` — Init, Profile-loading, and
  Resolver-layer rows updated; test-surface count 88 → 113; Review question
  answered for P0-E.
- `docs/CHANGELOG.md`, `docs/releases/P0-E-profile-validation-and-resolver.md`,
  `docs/tests/P0-E-profile-validation-and-resolver.md`,
  `docs/runbooks/HANDOFF-P0-E.md`, and this ledger entry (Entry 010).

### Files intentionally not changed

- `actools.sh` — **forbidden this phase**; byte-identical (no install-path wiring;
  that is P0-H).
- `profiles/community.profile` — read via the loader; **not modified** (governance
  flags already `false`, `PROFILE_INIT_FIELDS=(domain email site-name)`).
- All generator heredocs, `cli/*`, `modules/*`, `core/*`, `.github/workflows/*`.
- `installer/profile.sh` — **in the allowed set but not edited**: all four
  accessors already existed and were sufficient (wiring only).
- `tests/helpers/capture_golden_outputs.sh` — untouched; golden harness guard not
  widened/disabled.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Init (`installer/init.sh`) | validated profile **list membership** only; never sourced `profile.sh`; `--actor-id`/`--change-ticket` unhandled; wrote `actools.env` for any allowed *name* (incl. `community-plus`, whose file is absent) | sources `profile.sh`; validates **file existence** and **fails before persisting**; enforces actor/ticket via accessors; consumes `PROFILE_INIT_FIELDS`. Community unchanged |
| Resolver — `resolve_feature_handler` | returned a **token** (`community`→`""`; `community-plus`→`plus_<f>`; `test`→`test_<f>`) | returns a **PATH** via 3-tier resolution (override → module → default), first existing wins, else empty; `community`→`""` short-circuit preserved. **No live call sites** → no runtime behaviour change |
| Resolver — `resolve_profile_check` | **absent (0 hits)** | **present** — LOCKED-named umbrella delegating to the per-surface internals |
| Resolver — preflight/doctor/handoff | token-based | **unchanged** (token-based; surfaces wired in P0-H) |
| Install path / `actools.sh` | dispatcher-driven (P0-D) | **unchanged** (P0-E does not touch `actools.sh`) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | no generator edited; golden drift 6/6 |
| Caddyfile | Not touched | no generator edited; golden drift 6/6 |
| my.cnf | Not touched | no generator edited; golden drift 6/6 |
| Dockerfiles | Not touched | no generator edited; golden drift 6/6 |
| CLI | Not touched | `setup_cli` heredoc + `cli/actools` unedited; golden drift 6/6 |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean HEAD, P0-E WIP stashed):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 88/88

# Syntax:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6 (byte-identical)
bats tests/installer/init_profile_test.bats                                 # 10/10 (new)
bats tests/test_d0_dispatch.bats                                            # 48/48 (33 + 15)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113
```

### Test result

PASS — golden drift **6/6** before and after (generated output byte-identical);
**113/113** regression+new; **119/119** overall. `actools.sh` byte-identical.

### Documentation updated

- [x] Runtime authority map — Init / Profile-loading / Resolver-layer rows; test count 88→113; Review question
- [ ] Generated-file contract — no generated-file change
- [ ] CLI authority contract — no CLI-authority change (init is CLI-adjacent but the change is validation, not authority)
- [ ] Operator target docs — none this phase
- [x] Test plan / report — `docs/tests/P0-E-profile-validation-and-resolver.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → P0-E section)
- [x] Release note added — `docs/releases/P0-E-profile-validation-and-resolver.md` (incl. Rollback)
- [x] Test report added — `docs/tests/P0-E-profile-validation-and-resolver.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **Token→path contract change (`resolve_feature_handler`).** This changes the
  resolver's return shape for non-community profiles. It is safe **only** because
  the function has **zero live call sites** (verified — its callers are wired in
  P0-H). When P0-H wires it in, callers must consume a **path** (source/execute),
  not a token. Documented in the CHANGELOG, release note, and authority map.
- **Resolver asymmetry.** `resolve_feature_handler` is path-based while
  preflight/doctor/handoff stay token-based; `resolve_profile_check` therefore
  returns tokens today (it delegates to the token resolvers). Intentional and
  documented; reconciled when the surfaces are wired (P0-H).
- **`PROFILE_FEATURE_MODULES` is an internal resolver convention.** It is not part
  of the public profile contract in `profiles/README.md` and is not set by
  `community.profile`; only profiles shipping feature modules define it. Read
  `+x`-guarded so its absence (the common case) is a no-op under `set -u`.
- **`init` now sources `profile.sh`.** For community this is inert (flags false,
  base fields). A profile that declares `PROFILE_INIT_FIELDS` beyond
  domain/email/site-name has those "extra" fields collected but **not yet
  validated/collected** at init — that surface wiring is P0-H (community declares
  no extras, so this is a no-op today).
- **Governance identity not persisted.** `--actor-id`/`--change-ticket` are
  validated but not written to `actools.env` (P0-H concern). Tests assert
  non-persistence.

### Blockers

None.

### Review Gate decision

Pending — a **separate session (ideally a different model)** renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) golden 6/6 unchanged
and `actools.sh` byte-identical; (2) only allowed files touched; (3)
`resolve_feature_handler` 3-tier order is correct **and community short-circuits
to empty even with a staged override**; (4) `init` fails **before** persisting for
`community-plus`/absent profiles and community is unchanged; (5) the token→path
asymmetry is acceptable for now (reconciled at P0-H).

### Next safe task

**P0-H — Surface wiring.** Wire the completed resolvers into the live surfaces:
route preflight extras via `resolve_profile_check "preflight" …` (fail unknown for
non-default), replace doctor's hard `source doctor_deep.sh` with
`resolve_feature_handler`, replace handoff's silent `*)` with
`resolve_handoff_section`, and wire the install path to the **selected** profile
(the `ACTOOLS_PROFILE`-driven selection the P0-D handoff anticipated, now safe
because `init` validates the profile file). Golden 6/6 must remain green. (The
Review Gate owns final sequencing.)

### Forbidden next scope

No community-plus modules; no deep audit/doctor features; no governance gates
beyond validation scaffolding; no generated-file byte change; no widening or
disabling the golden harness range guard.

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. P0-E adds the init-time safety and the
resolver primitives but wires nothing into the live install path.

---

## Entry 009 — P0-D · Install-Stage Dispatcher Skeleton

Date: 2026-06-08
Branch: `phase0/P0-D-install-stage-dispatcher`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-D — Install-Stage Dispatcher Skeleton
Task prompt source: `P0-D-install-stage-dispatcher.md` + coding-window prompt (filled, archived)

### Objective

Introduce an install-stage dispatcher (`actools::dispatch::resolve_install_stage`
+ `actools::dispatch::run_install_stage`) and route the default `fresh` install
through it by iterating `PROFILE_INSTALL_STAGES`, with **byte-identical generated
output and byte-identical behaviour**. This is the seam that makes install order
profile-driven and append-only (it is what makes LOCKED Decision 3 —
community-plus *appends* `plus_*` — enforceable). No module extraction (P0-G);
no community-plus stages; no CLI-authority change (P0-F).

### Stage → handler mapping decision (the §5 design decision)

The flat community stage list `(host stack db drupal worker)` does not yet map
one-to-one onto the two coarse monoliths (`setup_stack` builds host + stack +
worker; `install_env` does db + Drupal per environment inside a parallel/RAM
loop). Full per-stage decomposition is **P0-G**. For P0-D the minimal
behaviour-preserving wiring is:

| Stage  | Handler                          | Behaviour |
|---|---|---|
| host   | `actools::install::stage_host`   | no-op — folded inside `setup_stack` until P0-G |
| stack  | `actools::install::stage_stack`  | calls `setup_stack` **unchanged** (host + stack + worker) |
| db     | `actools::install::stage_db`     | no-op — folded inside the per-env `install_env` loop until P0-G |
| drupal | `actools::install::stage_drupal` | runs the full per-env `install_env` loop **verbatim** (ENVIRONMENTS split + RAM probe + low-RAM downgrade + parallel/sequential branch) |
| worker | `actools::install::stage_worker` | no-op — worker container built inside `setup_stack` until P0-G |

Iterating host→stack→db→drupal→worker therefore executes
`(no-op)→setup_stack→(no-op)→install_env loop→(no-op)`, byte-for-byte the legacy
sequence. **Judgment call (flagged):** the DB work is anchored under the `drupal`
handler (the `db` handler is a documented no-op) because `install_env` performs
DB creation and Drupal install together; this is trivially flippable and both
arrangements keep the golden net and the stage-order test green.

**Resolver asymmetry (documented):** the existing feature/preflight/doctor/handoff
resolvers echo `""` for community (callers treat empty as "run default inline"),
but an install stage MUST resolve to a concrete, runnable function because
`run_install_stage` calls it. So `resolve_install_stage` returns
`actools::install::stage_<stage>` for community (and as the unknown-profile
fail-soft fallback, after a WARN), never empty. `community-plus`→`plus_<stage>`
and `test`→`test_<stage>` mirror the sibling resolvers as forward-looking
scaffolding (only community runs in P0-D).

### Files changed

- `installer/dispatch.sh` — **append-only** (behind the existing module guard;
  no edits above line 191). Adds `actools::dispatch::resolve_install_stage`,
  `actools::dispatch::run_install_stage`, and the five community base handlers
  `actools::install::stage_{host,stack,db,drupal,worker}`. The `drupal` handler
  contains the per-env install loop copied verbatim from `main()`.
- `actools.sh` — **`main()` only** (fresh mode). Replaced the hardcoded
  `setup_stack` + per-env `install_env` block (old lines 1606–1623) with:
  `source "${INSTALL_DIR}/profiles/community.profile"` then
  `for stage in "${PROFILE_INSTALL_STAGES[@]}"; do actools::dispatch::run_install_stage "$stage"; done`.
  The trailing post-stage steps `setup_backup_cron` / `setup_cli` / `tls_check`
  are unchanged. No function above `main()` was touched, so the harness line
  ranges for `setup_stack` (569–1028) and `setup_cli` (1247–1528) are preserved.
- `tests/installer/dispatch_stages_test.bats` — **new**, 12 BATS tests (stage
  order; real-handler behaviour preservation incl. low-RAM downgrade;
  append-only stage guard; resolver correctness + fail-loud-on-undefined-handler).
- `docs/architecture/runtime-authority-map.md` — dispatcher now wired (see below).
- `docs/CHANGELOG.md`, `docs/releases/P0-D-install-stage-dispatcher.md`,
  `docs/tests/P0-D-install-stage-dispatcher.md`, `docs/runbooks/HANDOFF-P0-D.md`,
  and this ledger entry (Entry 009).

### Files intentionally not changed

- `profiles/community.profile` — `PROFILE_INSTALL_STAGES=(host stack db drupal worker)`
  is already canonical (line 28); the dispatcher reads it, does not redefine it.
- `setup_stack`, `install_env`, `setup_backup_cron`, `setup_cli`, `tls_check`
  bodies — untouched (behaviour provided unchanged).
- All generated-file generators (`actools.sh:595/607/624/634/663/795`, the
  `setup_cli` heredoc) — untouched.
- `tests/helpers/capture_golden_outputs.sh` — untouched; `SS_*/SC_*` ranges
  still valid (the guard was NOT widened, commented, or disabled).
- `.github/workflows/*` (CI guard is P0-I), `modules/*`, `core/*`, `cli/*`.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Install-stage orchestration | `main()` (fresh) ran a hardcoded `setup_stack` then a per-env `install_env` loop | `main()` iterates `PROFILE_INSTALL_STAGES` and calls `actools::dispatch::run_install_stage` per stage; handlers call the same monoliths unchanged |
| Resolver layer (`installer/dispatch.sh`) | 4 resolvers (feature, preflight, doctor, handoff); install stages had no resolver | + `resolve_install_stage` (5th resolver) and `run_install_stage` (runner) + 5 community base stage handlers |
| Profile read in `main()` | `main()` was profile-blind (0 refs to `PROFILE_INSTALL_STAGES`) | `main()` sources `community.profile` to obtain the stage list (profile **selection** by `ACTOOLS_PROFILE` remains P0-E) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator unedited; golden drift 6/6 |
| Caddyfile | Not touched | generator unedited; golden drift 6/6 |
| my.cnf | Not touched | generator unedited; golden drift 6/6 |
| Dockerfiles | Not touched | generators unedited; golden drift 6/6 |
| CLI | Not touched | `setup_cli` heredoc + `cli/actools` unedited; golden drift 6/6 |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE any change — baseline green:
bats tests/generated/golden_drift_test.bats          # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 76/76

# syntax (all shell):
bash -n actools.sh
bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n   # all OK

# AFTER changes — still green:
bats tests/generated/golden_drift_test.bats          # 6/6 (byte-identical)
bats tests/installer/dispatch_stages_test.bats       # 12/12 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats     # 88/88 (76 + 12)
# total across golden + regression + new = 94/94
```

### Test result

PASS — golden drift 6/6 before **and** after (generated bytes unchanged);
12/12 new dispatcher tests; 88/88 regression+new; 94/94 overall. Function line
ranges re-verified unchanged (`setup_stack` 569/1028, `setup_cli` 1247/1528) so
`_assert_fn_range` still holds.

### Documentation updated

- [x] Runtime authority map — install-stage orchestration + resolver rows updated
- [ ] Generated-file contract — no generated-file change
- [ ] CLI authority contract — no CLI-authority change
- [ ] Operator target docs — none this phase
- [x] Test plan / report — `docs/tests/P0-D-install-stage-dispatcher.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → runtime change)
- [x] Release note added — `docs/releases/P0-D-install-stage-dispatcher.md` (incl. Rollback)
- [x] Test report added — `docs/tests/P0-D-install-stage-dispatcher.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **db/drupal anchor (judgment call):** DB creation runs inside the `drupal`
  handler (the `db` handler is a no-op). This preserves current behaviour exactly
  but means the `db`↔`drupal` split is cosmetic until P0-G genuinely separates
  `install_env` into DB and Drupal handlers. Flipping the anchor is trivial and
  test-covered.
- **`PARALLEL_INSTALL` global mutation:** the `drupal` handler intentionally does
  NOT declare `PARALLEL_INSTALL` local, mirroring the legacy in-`main()` mutation
  during the low-RAM downgrade. `ENVS`/`TOTAL_RAM`/`env` ARE local (every other
  use site re-derives them; nothing reads them after the loop), which is
  provably behaviour-neutral.
- **Profile sourced inside `main()`:** P0-D hardcodes `source community.profile`.
  P0-E must replace this with profile-driven selection via `ACTOOLS_PROFILE`
  (using `actools::cli::resolve_profile`), at which point the hardcode is removed.
- **Line-range coupling (unchanged):** the harness still hardcodes `setup_stack`
  569–1028 and `setup_cli` 1247–1528. P0-D did not shift them; any future
  `main()`-above edit must update `SS_*/SC_*` in the same commit.

### Blockers

None.

### Review Gate decision

Pending — a **separate Sonnet window** (scope/diff review) renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) golden 6/6 unchanged,
(2) only allowed files touched, (3) the stage loop reproduces the legacy
sequence exactly, (4) the db/drupal anchor judgment call is acceptable or should
be flipped.

### Next safe task

**P0-E — Profile selection wiring** — replace the hardcoded
`source community.profile` in `main()` with `ACTOOLS_PROFILE`-driven profile
resolution (via `actools::cli::resolve_profile`), so the stage loop runs the
selected profile's `PROFILE_INSTALL_STAGES`. Golden 6/6 must remain green; the
dispatcher seam from P0-D is the foundation. (Final sequencing is the Review
Gate's call.)

### Forbidden next scope

No module extraction / host-stack decomposition (P0-G); no community-plus stage
implementations; no generated-file byte change; no CLI-authority consolidation
(P0-F); no widening/disabling the golden harness range guard.

---

## Entry 008 — P0-C · Golden Behavior Capture

Date: 2026-06-08
Branch: `phase0/P0-C-golden-behavior-capture`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Sonnet)
Phase: P0-C — Golden Behavior Capture
Task prompt source: `P0-C-coding-window-prompt.md` (filled, archived)

### Objective

Capture byte-exact golden fixtures of all generated files across the 5-variant
environment matrix, plus a drift-detecting BATS test suite that FAILS on any
unexplained change.  This is the safety net that must remain green before any
later phase (P0-D / P0-G) touches generation logic.  Zero generator or runtime
byte changes.

### Files changed

New (golden fixtures — 5 variants × 7 files + 1 manifest each = 40 files):

- `tests/fixtures/golden/default/` — my.cnf, Dockerfile.caddy, Dockerfile.php,
  Dockerfile.worker, Caddyfile, docker-compose.yml, actools-cli, SHA256SUMS
- `tests/fixtures/golden/redis-off/` — same 8 files
- `tests/fixtures/golden/s3-on/` — same 8 files (S3 creds populated)
- `tests/fixtures/golden/cadvisor-on/` — same 8 files (cadvisor service added)
- `tests/fixtures/golden/all-in-one/` — same 8 files (dev/stg services + vhosts)

New (test infrastructure):

- `tests/helpers/capture_golden_outputs.sh` — capture helper; extracts
  `setup_stack()` and `setup_cli()` from the live `actools.sh` via
  `sed -n 'X,Yp'` + `eval`, never copies heredoc text; runs each function
  in an isolated subshell with no-op bash function shims for `docker`,
  `chown`, `section`, `log`, `warn`, `error`, `setup_backup_db_user`
- `tests/generated/golden_drift_test.bats` — 6 BATS tests (5 variant drift
  tests + 1 meta test); re-renders each variant and compares sha256 against
  stored fixtures; fails with diff output on mismatch
- `docs/tests/P0-C-golden-behavior-capture.md` — this test report; contains
  the (currently empty) intentional-difference table
- `docs/runbooks/PHASE0_LEDGER.md` — this entry (Entry 008)

### Files intentionally not changed

- `actools.sh` — untouched; zero runtime/generator change
- `installer/*`, `cli/*`, `modules/*`, `profiles/*`, `core/*` — untouched
- `.github/workflows/*` — untouched (CI shellcheck for actools.sh is P0-I)
- `docs/target/phase0/operator/*` — not promoted (remains target-only)
- All other runtime files — untouched

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (all) | as recorded in `docs/architecture/runtime-authority-map.md` | **unchanged** — P0-C is capture-only; no `current` authority moved |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator `actools.sh:795` unedited; golden fixture only captures output |
| Caddyfile | Not touched | generator `actools.sh:663` unedited |
| my.cnf | Not touched | generator `actools.sh:595` unedited |
| Dockerfiles | Not touched | generators `actools.sh:607/624/634` unedited |
| CLI | Not touched | `setup_cli` heredoc `actools.sh:1251-1520` and `cli/actools` unedited |

### Tests run

```bash
# 1. Syntax check
bash -n tests/helpers/capture_golden_outputs.sh       # parses

# 2. Capture all variants
bash tests/helpers/capture_golden_outputs.sh all
# → 5 variants × 7 files = 35 files + 5 SHA256SUMS; all captured

# 3. Determinism check (run capture again; sums must be identical)
bash tests/helpers/capture_golden_outputs.sh default /tmp/golden_verify
diff tests/fixtures/golden/default/SHA256SUMS /tmp/golden_verify/default/SHA256SUMS
# → no diff (deterministic)

# 4. Run drift test suite (all 6 tests must pass)
bats tests/generated/golden_drift_test.bats
# → 6/6 ok

# 5. Verify drift test FAILS on injected change
#    (echo "# DRIFT" >> fixture; bats sees mismatch; restore fixture; bats green)

# 6. Confirm no runtime change
git diff --stat -- ':!docs' ':!tests'
# → empty

# 7. Confirm actools.sh untouched
git diff actools.sh cli/actools installer/ core/ modules/ profiles/
# → empty
```

### Test result

PASS (6/6 bats tests; determinism confirmed; drift detection confirmed)

### Documentation updated

- [x] `docs/tests/P0-C-golden-behavior-capture.md` — test report with captured
  matrix, limitations, and intentional-difference table (currently empty)
- [x] `docs/runbooks/PHASE0_LEDGER.md` — this entry (Entry 008)
- [ ] Runtime authority map — no authority changes this phase
- [ ] Operator target docs — no new docs this phase

### Changelog / release notes

- [ ] CHANGELOG.md — no user-visible change (capture infrastructure only)
- [ ] Release note — n/a
- [x] Test report — `docs/tests/P0-C-golden-behavior-capture.md`
- [ ] Review notes — pending

### Known risks

- **Line-number coupling:** the capture helper uses `sed -n '569,1028p'` and
  `sed -n '1247,1528p'` to extract function bodies.  If `actools.sh` is
  edited in a future phase and the function start lines shift, the helper
  will detect the mismatch via `_assert_fn_range()` and fail loudly before
  producing a wrong capture.  Update `SS_START`/`SS_END`/`SC_START`/`SC_END`
  in the helper at the same time as the actools.sh edit.

- **redis-off depends_on quirk:** With `ENABLE_REDIS=false`, `docker-compose.yml`
  still includes `depends_on: redis: condition: service_started` for php_prod
  and worker_prod (hardcoded in the compose heredoc), even though the redis
  service itself is absent.  This is the current generator behavior; the
  fixture captures it as-is.  P0-G will correct the generator; when it does,
  the `redis-off` fixture must be updated with an intentional-difference entry.

- **Dockerfile.php vs repo copy:** The `Dockerfile.php` fixture captures the
  fallback heredoc generator at actools.sh:624.  In real installs, the repo's
  tracked `Dockerfile.php` is used instead (the heredoc is skipped because the
  file already exists at INSTALL_DIR).  The fixture tests the generator code
  path, not the production path.

### Blockers

None.

### Review Gate decision

Pending — a **separate Opus window** renders APPROVED / NEEDS REVISION / BLOCKED.
Reviewer: confirm the captured variant matrix is complete (both OFF and ON
branches for every toggle appear in the matrix).

### Next safe task

**P0-D — Stage Dispatcher Scaffold** — wire `main()` in `actools.sh` to iterate
`PROFILE_INSTALL_STAGES` via a `run_install_stage`/`resolve_install_stage` loop
(append-only guard, behavior-preserving).  The golden fixtures from P0-C must
remain green after P0-D; any accidental generator change will be caught by
`bats tests/generated/golden_drift_test.bats`.

### Forbidden next scope

No generator/runtime change before Review Gate approval; no promotion of
`docs/target/phase0/operator/`; no CI shellcheck edits (P0-I); no CLI
consolidation (P0-F).

---

## Entry 007 — P0-B · Target Operator Documentation + Documentation Reconciliation

Date: 2026-06-08
Branch: `phase0/P0-B-target-operator-docs`
Commit SHA: (recorded by operator at apply time — see `APPLY-P0-B.md` §4)
Actor / Claude session (model): Coding Window (Sonnet)
Phase: P0-B — Target Operator Documentation
Task prompt source: system prompt P0-B (inline) + `docs/runbooks/HANDOFF-P0-A.md`

### Objective

Write the six operator-facing **target** docs under `docs/target/phase0/operator/`, each
carrying the required `"Phase 0 target contract — not yet released"` status banner. As
documentation reconciliation, correct the stale/false claims recorded by the authority
map in `docs/architecture.md` and `docs/CHANGELOG.md`. Zero runtime change.

### Files changed

New (target operator docs — unreleased behaviour only):

- `docs/target/phase0/operator/README.md` — directory index, promotion gate, cross-links
- `docs/target/phase0/operator/install-community.md` — default `community` install journey
  (5 stages: init → preflight → install → handoff → doctor) with D.0-gap annotations
- `docs/target/phase0/operator/profiles.md` — profile lifecycle, error behaviour, allowed
  profiles, non-bypass rule, community-plus reserved status
- `docs/target/phase0/operator/commands.md` — full command surface as a target contract
  (installer + CLI commands, global flags, profile resolution, out-of-surface list)
- `docs/target/phase0/operator/generated-files.md` — all 6 operator-visible generated
  files with current/target authority, safety rules, golden fixture strategy
- `docs/target/phase0/operator/troubleshooting.md` — symptom-first troubleshooting for
  init, preflight, install, CLI, generated-file, and profile problems

Corrected (documentation reconciliation — no restructure, in-place only):

- `docs/architecture.md` —
  (1) `:3` `v11.2.0+` → `v14.0+` (actual `ACTOOLS_VERSION` per `actools.sh:46`);
  (2) `:9` false "never contains business logic" claim deleted; replaced with accurate
      description: monolithic `actools.sh` is the live spine, `cli/commands/` are the
      operator CLI handlers;
  (3) `:49` `21 bats tests` → `76` (verified: dispatch 33 + init 11 + preflight 6 +
      doctor 5 + validate 11 + secrets 10);
  (4) `:84-89` false `phases_complete` state-machine block replaced with actual
      `init_state()` structure (`{"envs":{}, "db_passes":{}, "backup_user_pass":…}`);
  (5) `:119` `/usr/local/bin/actools-real` example reference corrected to `cli/actools`
      (the canonical CLI source per `docs/architecture/cli-authority-contract.md`)
- `docs/CHANGELOG.md` —
  (1) `:113` false "All Dockerfiles moved to template variables" claim corrected; replaced
      with accurate statement citing live authority `actools.sh:607/624/634` and P0-G
      extraction scope; phrase fully removed (grep gate confirmed clean);
  (2) Added `[Unreleased] / Documentation` section at top recording target docs added
      and architecture reconciliation

Also updated:
- `docs/runbooks/PHASE0_LEDGER.md` — this entry (Entry 007)

### Files intentionally not changed

- `actools.sh` — untouched (zero runtime change)
- `installer/*`, `cli/*`, `modules/*`, `profiles/*`, `core/*` — untouched
- `.github/workflows/*` — untouched
- `docs/architecture/runtime-authority-map.md` — not modified (no authority changes this
  phase; forbidden per P0-B scope)
- `docs/target/phase0/operator/.gitkeep` — remains (directory anchor; not removed)

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (all) | as recorded in `docs/architecture/runtime-authority-map.md` | **unchanged** — P0-B is documentation-only; no `current` authority moved |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator `actools.sh:795` unedited |
| Caddyfile | Not touched | generator `actools.sh:663` unedited |
| my.cnf | Not touched | generator `actools.sh:595` unedited |
| Dockerfiles | Not touched | generators `actools.sh:607/624/634` unedited |
| CLI | Not touched | `setup_cli` heredoc `actools.sh:1251-1520` and `cli/actools` unedited |

### Tests run

```bash
# P0-B is doc-only; checks prove no runtime file was altered and docs are well-formed.
git status --porcelain
    # only docs/ paths appear; actools.sh, installer, core, cli, modules, profiles, tests untouched
grep -rL "Phase 0 target contract" docs/target/phase0/operator/
    # returns only .gitkeep — all authored docs carry the banner
grep -nE '21 bats|never contains business logic|"version": "11\.2|phases_complete' docs/architecture.md
    # empty — no surviving false assertion
grep -n 'moved to template variables' docs/CHANGELOG.md
    # empty
bash -n actools.sh      # parses (untouched)
bash -n cli/actools     # parses (untouched)
```

### Test result

PASS (self-validation): all four grep gates pass. No runtime file changed.

### Documentation updated

- [x] Operator target docs (6 files created under `docs/target/phase0/operator/`)
- [x] `docs/architecture.md` (5 false claims corrected)
- [x] `docs/CHANGELOG.md` (false Dockerfile claim corrected + Unreleased section added)
- [ ] Runtime authority map (not modified — no authority changes this phase)
- [ ] Generated-file contract (not modified — no changes)
- [ ] CLI authority contract (not modified — no changes)
- [ ] Test plan (deferred to P0-C/P0-I)

### Changelog / release notes

- [x] `docs/CHANGELOG.md` — `[Unreleased] / Documentation` section added
- [ ] Release note (n/a — doc-only phase)

### Known risks

- Every target doc is explicitly labelled `unreleased-target`. No doc asserts that
  community-plus is implemented or that target behaviour is currently released.
- The D.0 gap annotations in `install-community.md` and `profiles.md` (P0-E / P0-H scope)
  were written from the authority map's verified evidence; they do not introduce any new
  runtime obligation.
- `docs/architecture.md` was corrected in-place only — no restructuring or expansion.
  The false-claim removal shrinks `:9` but does not alter section order.

### Blockers

None.

### Review Gate decision

Pending — a **separate Sonnet window** renders APPROVED / NEEDS REVISION / BLOCKED.
P0-B is low-risk doc-only; Sonnet is the correct reviewer.

### Next safe task

**P0-C — Golden Fixture Capture** (`06_implementation_phases/P0-C-golden-behavior-capture.md`).
Coding model: **Sonnet**. Render and capture byte-exact golden fixtures for every generated
file across the env matrix (all-in-one, Redis, cAdvisor, S3 on/off). Add `actools.sh` to
CI shellcheck. No generator is touched until the golden net is green.

### Forbidden next scope

- No runtime code change (P0-C is capture-only, not extraction).
- No promotion of `docs/target/phase0/operator/` to `docs/operator/`.
- No community-plus feature work; no `plus_*` module.
- No dispatcher/resolver wiring (that is P0-D/P0-E).
- No generated-file byte change (P0-C captures current bytes; it does not change them).

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. Build-trigger #1 not yet met.

---

## Entry 006 — P0-A · Adopt synthesis + materialize canon and runtime authority map

Date: 2026-06-08  
Branch: `phase0/P0-A-finalise-authority-map`  
Commit SHA: (recorded by operator at apply time — see APPLY-P0-A.md §4)  
Actor / Claude session (model): Phase Conductor (Mode 1), Opus  
Phase: P0-A — Finalise Authority Map  
Task prompt source: `07_prompts/phase-conductor-prompt.md` + `06_implementation_phases/P0-A-finalise-authority-map.md`

> Numbering note: the P0-A phase file's "Done means" predates the planning passes and says
> "ledger has Entry 002"; entries 002–005 were consumed by package-alignment passes, so this
> first *execution* entry is **006**. The intent — "P0-A adds a ledger entry; community-plus
> stays blocked" — is satisfied.

### Objective

Execute **P0-A (doc-only)** together with the **HOW_TO_RUN Step-0 materialization** in one branch/PR:
adopt the verified synthesis (`00_reference/actools-phase0-implementation-plan.md`) **without re-deriving it**;
stand up the in-repo documentation home so every later window's documented read-paths resolve;
record the runtime authority map with **path:line evidence spot-verified read-only** against the repo;
create the **design-canon home** (LOCKED §11 build-trigger #2); and **fold the alignment's five Section-4
tightenings** into the phase prompts they name. No runtime shell/profile/CLI/generated-file change.

### Files changed

New (created on the devbox via quoted heredocs — see APPLY-P0-A.md §2):

- `design/Actools_Drupal_Community_Plus_LOCKED.md` — canon (verbatim) — *build-trigger #2*
- `design/actools-phase0-implementation-plan.md` — adopted synthesis (verbatim) — *build-trigger #2*
- `design/actools-phase0-locked-alignment.md` — alignment errata (verbatim) — *build-trigger #2*
- `design/README.md` — canon-home index; tracker reference note
- `docs/architecture/runtime-authority-map.md` — **filled with verified path:line evidence** (this phase's core artifact)
- `docs/architecture/phase0-seam-contract.md` — materialized (verbatim)
- `docs/architecture/generated-file-contract.md` — materialized (verbatim)
- `docs/architecture/cli-authority-contract.md` — materialized (verbatim)
- `docs/runbooks/PHASE0_LEDGER.md` — **this file**, with Entry 006
- `docs/runbooks/HANDOFF_TEMPLATE.md` — materialized (verbatim)
- `docs/runbooks/HANDOFF-P0-A.md` — the P0-A handoff (next allowed task = P0-B)
- `docs/runbooks/CHANGE_CONTROL.md` — materialized (verbatim)
- `docs/runbooks/DRIFT_PREVENTION_RULES.md` — materialized (verbatim)
- `docs/runbooks/AI_WINDOW_PROTOCOL.md` — materialized (verbatim)
- `docs/runbooks/CLAUDE_EXECUTION_MODEL.md` — materialized (verbatim)
- `docs/target/phase0/README.md` — unreleased-target banner (placeholder; **content authored by P0-B**)
- `docs/target/phase0/operator/.gitkeep` — directory anchor for P0-B
- `docs/reviews/P0-A-pr-body.md` — PR body for this phase

Edited **in the workflow package only** (process docs — not runtime, not in the repo): the alignment
tightenings folded into `06_implementation_phases/P0-D`, `P0-E`, `P0-H`, `P0-I`; this ledger; and
`03_architecture_contracts/runtime-authority-map.md`. Repacked as `actools_phase0_workflow_package_P0A.zip`.

### Files intentionally not changed

- `actools.sh` — untouched (no byte change; remains the live, profile-blind spine)
- `installer/*` (`init.sh`, `preflight.sh`, `handoff.sh`, `dispatch.sh`, `profile.sh`, `output.sh`) — untouched
- `cli/actools`, `cli/commands/*` — untouched (the false `cli/actools:12-15` comment is **left for P0-F**)
- `profiles/*` — untouched (no `profiles/test.profile` added here; that is P0-E/P0-I per S6)
- `modules/*`, `core/*` — untouched
- `.github/workflows/*` — untouched (the "`actools.sh` → shellcheck" edit is **P0-I**, per S2)
- `docs/architecture.md`, `docs/CHANGELOG.md` — the stale/false claims are **left for P0-B/P0-J** (not corrected here)

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (all) | as recorded in `docs/architecture/runtime-authority-map.md` | **unchanged** — P0-A moved no `current` authority; it only *recorded* the map |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator `actools.sh:795` unedited |
| Caddyfile | Not touched | generator `actools.sh:663` unedited |
| my.cnf | Not touched | generator `actools.sh:595` unedited |
| Dockerfiles | Not touched | generators `actools.sh:607/624/634` unedited |
| CLI | Not touched | `setup_cli` heredoc `actools.sh:1251-1520` and `cli/actools` unedited |

### Tests run

````bash
# P0-A is doc-only; the self-checks prove no runtime file was altered and the new docs are well-formed.
# (Conductor self-validated in-sandbox; operator re-runs on the devbox — APPLY-P0-A.md §3.)
bash -n actools.sh                       # still parses (untouched)
bash -n cli/actools                      # still parses (untouched)
git diff --stat -- ':!docs' ':!design'   # MUST be empty: no non-doc change
# markdown link/structure spot-check on the new docs (see APPLY-P0-A.md §3)
````

### Test result

PASS (sandbox self-validation): no runtime/`*.sh`/workflow file changed; new markdown parses and cross-links resolve.

### Documentation updated

- [x] Runtime authority map (filled with verified path:line evidence)
- [ ] Generated-file contract (materialized verbatim; no content change)
- [ ] CLI authority contract (materialized verbatim; no content change)
- [ ] Operator target docs (deferred to P0-B — only the directory + banner placeholder created)
- [ ] Test plan (deferred to P0-C/P0-I)

### Changelog / release notes

- [ ] CHANGELOG.md updated (no — repo `docs/CHANGELOG.md` corrections are P0-B/P0-J scope)
- [ ] Release note added (n/a this phase)
- [ ] Test report added (n/a this phase)
- [x] Review notes prepared (`review/review-gate-P0-A.md` — filled for a separate Sonnet window)

### Known risks

- **Scope-bleed risk:** P0-A bundles HOW_TO_RUN Step-0 materialization with the authority-map record. This is intentional and bounded: every materialized contract/runbook/canon file is a **verbatim** copy of an existing package file (no new authoring); only `runtime-authority-map.md`, this ledger entry, the handoff, and the PR body are authored. The reviewer should confirm no runtime byte moved.
- **Base SHA:** the export carried no `.git`; the operator records the real `main` HEAD at apply time. P0-A is heredoc-only (no `git apply` patch), so it is not base-sensitive.

### Blockers

None.

### Review Gate decision

Pending — a **separate Sonnet window** renders APPROVED / NEEDS REVISION / BLOCKED using `review/review-gate-P0-A.md`. The Conductor prepares the prompt and never renders the verdict.

### Next safe task

**P0-B — Target Operator Documentation** (`06_implementation_phases/P0-B-target-operator-docs.md`). Coding model: **Sonnet**; review: Opus or human. Write the operator-facing target docs under `docs/target/phase0/operator/` (status-banner every file), cross-linking the now-materialized `docs/architecture/*` contracts; correct the false `docs/architecture.md`/`docs/CHANGELOG.md` claims as target-doc reconciliation.

### Forbidden next scope

No runtime code; no tests (beyond doc references); **no promotion to `docs/operator/`**; no `plus_*` / community-plus feature work; no generated-file change; no dispatcher/resolver edits (those begin at P0-D/P0-E).

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. Build-trigger #1 (merged Phase-0 PRs + green CI + fake-profile e2e) not yet met; build-trigger #2 (design-canon home) is **satisfied by this phase** once merged.

---

## Entry 005 — Phase Conductor (Mode 1) + per-phase devbox apply sheet

Date: 2026-06-07  
Phase: Planning  
Actor / Claude session (model): alignment pass

### Objective

Confirmed **Mode 1** (Conductor = sandbox Opus chat window; operator applies on the devbox `~/actoolsDrupal`; no Claude Code; no `nano`). Added `07_prompts/phase-conductor-prompt.md` (the per-phase meta-prompt), `04_runbooks/PHASE_CONDUCTOR_PROTOCOL.md` (four lanes + apply contract + per-phase op map + resolved S1–S8), and `08_changelog_release_templates/DEVBOX_APPLY_SHEET_TEMPLATE.md` (the `APPLY-P0-{X}.md` operator file the Conductor ships at the top of every output.zip: heredoc creates, `git apply --3way` patches, full `git add/commit/push` with an authored commit message, PR command, and the "only you/CI/review can do" + rollback sections). Updated `HOW_TO_RUN.md`/`README.md` to Mode 1; recorded the GitHub remote (`https://github.com/actools-pl/actoolsDrupal`) and devbox path (`/home/veritas/actoolsDrupal`).

### Runtime authority changes

None. Documentation/process only.

### Community-plus status

Still blocked.

---

## Entry 003 — Added operator run-sheet (HOW_TO_RUN.md)

Date: 2026-06-06  
Phase: Planning  
Actor / Claude session (model): alignment pass

### Objective

Added top-level `HOW_TO_RUN.md`: the one-page operating rhythm — Step 0 setup (check out the repo branch; materialize contracts→`docs/architecture/`, runbooks+ledger→`docs/runbooks/`, canon→`design/` which satisfies LOCKED §11 build-trigger #2), the per-phase Claude loop (assign one phase → code → ledger → cross-model Review Gate → approve → next), the phase/model/session map with the P0-C-before-P0-D/P0-G dependency, and closure. Referenced it from `README.md` and `MANIFEST.md`.

### Runtime authority changes

None. Documentation/process only.

### Community-plus status

Still blocked.

---

## Entry 002 — Aligned to Claude execution; reference report swapped

Date: 2026-06-06  
Phase: Planning  
Actor / Claude session (model): alignment pass

### Objective

(1) Align the package to the fact that the whole Phase 0 implementation is executed by **Claude (Opus / Sonnet)**: added `04_runbooks/CLAUDE_EXECUTION_MODEL.md`, specialised `AI_WINDOW_PROTOCOL.md` and the prompts to Claude sessions, and added per-phase model + coding-session assignments to the phase master and each `P0-*` file. (2) Replaced `00_reference/actools_phase0_modularization_deep_review.md` with the verified synthesis `00_reference/actools-phase0-implementation-plan.md` (banner adds the WP-*↔P0-* crosswalk). (3) Added the design-canon-home criterion (LOCKED §11 trigger #2) to the acceptance criteria.

### Runtime authority changes

None. Documentation/process only.

### Community-plus status

Still blocked.

---

## Entry 001 — Package created

Date: 2026-06-06  
Phase: Planning

### Objective

Create a complete workflow package for Phase 0 finalisation, target docs, implementation phases, ledger, prompts, and closure gates.

### Runtime authority changes

None.

### Community-plus status

Still blocked.

