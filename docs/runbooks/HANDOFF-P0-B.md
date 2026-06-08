# Handoff — P0-B · Target Operator Documentation + Documentation Reconciliation

## Repository state

Branch: `phase0/P0-B-target-operator-docs`
Commit SHA: (recorded by operator at apply time — see `APPLY-P0-B.md` §4)
Working tree clean? yes (after the single P0-B commit)
Zip/package name if applicable: `actools_phase0_workflow_package_P0B.zip`

## Task completed

Executed **P0-B (doc-only)** in one branch/PR:

- **Created** 6 operator-facing target docs under `docs/target/phase0/operator/`,
  every file labelled `unreleased-target` with the required verbatim status banner.
  Content covers: the default `community` install journey (all 5 stages with D.0-gap
  annotations); the profile lifecycle and error behaviour; the full command surface as a
  target contract; every operator-visible generated file with safety expectations; and a
  symptom-first troubleshooting guide. Each doc cross-links the three
  `docs/architecture/` contracts.
- **Corrected** `docs/architecture.md` in-place (5 false claims):
  `v11.2.0+` → `v14.0+`; removed "never contains business logic" claim about the CLI;
  `21 bats` → `76`; replaced false `phases_complete` state-machine with actual
  `init_state()` structure; replaced `/usr/local/bin/actools-real` with `cli/actools`.
- **Corrected** `docs/CHANGELOG.md` in-place: removed the false
  `v10.0.0` Dockerfile heredoc claim; replaced with accurate statement citing
  `actools.sh:607/624/634` as the live generators and P0-G as the extraction scope.
- **Added** `[Unreleased] / Documentation` section to `docs/CHANGELOG.md` recording the
  target docs and the reconciliation.
- **Added** ledger Entry 007 to `docs/runbooks/PHASE0_LEDGER.md`.

No runtime shell/profile/CLI/generated-file byte was changed.

## Files changed

New under `docs/target/phase0/operator/`:

- `docs/target/phase0/operator/README.md`
- `docs/target/phase0/operator/install-community.md`
- `docs/target/phase0/operator/profiles.md`
- `docs/target/phase0/operator/commands.md`
- `docs/target/phase0/operator/generated-files.md`
- `docs/target/phase0/operator/troubleshooting.md`

Corrected:

- `docs/architecture.md` (5 false claims corrected in-place; no restructure)
- `docs/CHANGELOG.md` (false Dockerfile claim corrected; `[Unreleased]` section added)
- `docs/runbooks/PHASE0_LEDGER.md` (Entry 007 added)

## Files not changed but relevant

- `actools.sh` — live spine (untouched; version confirmed `14.0` at `:46`)
- `installer/dispatch.sh` — resolver seam (untouched; sourced-but-uncalled on live path)
- `installer/init.sh`, `installer/preflight.sh`, `installer/handoff.sh` — untouched
- `installer/profile.sh` — untouched (loader + accessors present, not yet consumed by init)
- `cli/actools` — untouched (the canonical-elect static CLI)
- `profiles/community.profile` — untouched (default profile definition)
- `docs/architecture/runtime-authority-map.md` — untouched (no authority change this phase)
- The three architecture contracts — untouched (materialized at P0-A; correct as-is)

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | None — documented only |
| Init | None — documented only (D.0 gaps annotated in target docs → P0-E) |
| Profile loading | None — documented only |
| Install stages | None — documented only |
| CLI | None — documented only |
| Generated files | None — documented only |
| Preflight | None — documented only |
| Doctor | None — documented only |
| Handoff | None — documented only |

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
# P0-B is doc-only; checks prove no runtime file changed and docs meet the gates.
git status --porcelain
    # only docs/ paths appear; actools.sh, installer, core, cli, modules,
    # profiles, tests are untouched

grep -rL "Phase 0 target contract" docs/target/phase0/operator/
    # returns only .gitkeep — every authored doc carries the banner

grep -nE '21 bats|never contains business logic|"version": "11\.2|phases_complete' docs/architecture.md
    # empty — all false assertions removed

grep -n 'moved to template variables' docs/CHANGELOG.md
    # empty — false claim removed

bash -n actools.sh       # parses (untouched)
bash -n cli/actools      # parses (untouched)
```

## Test result

PASS (self-validation): all four grep gates pass; no runtime file touched. CI must still
be green on the PR.

## Docs updated

- [x] `docs/target/phase0/operator/` — 6 target docs created
- [x] `docs/architecture.md` — 5 false claims corrected
- [x] `docs/CHANGELOG.md` — false claim corrected + Unreleased section added
- [x] `docs/runbooks/PHASE0_LEDGER.md` — Entry 007 added
- [ ] `docs/architecture/runtime-authority-map.md` — not modified (no authority changes)

## Changelog / release notes updated

`docs/CHANGELOG.md` — `[Unreleased] / Documentation` section added at top.

## Ledger entry

Entry number: **007**

## Known risks

- The D.0 gap annotations in `install-community.md` and `profiles.md` reference the P0-E
  and P0-H phase scope. These are read from the verified authority map and do not introduce
  new obligations; they document known gaps that already appear in the ledger.
- `docs/architecture.md` corrections are in-place only — no restructuring. The paragraph
  describing `actools.sh` now correctly describes the monolith; the doc still reflects an
  aspirational "modular platform" framing in its tree diagram (the tree is accurate for
  `modules/` layout but implies those modules are live when many are orphans). This
  residual framing tension is P0-J scope (doc flip at Phase 0 closure) — not a P0-B gate.
- `docs/CHANGELOG.md` v10.0.0 Architecture section still lists "install_env() split into
  3 independent stages" — this claim is accurate (prepare/provision/secure in
  `modules/drupal/provision.sh`) and was not corrected.

## Blockers

None.

## Exact next allowed task

**P0-C — Golden Fixture Capture** (`06_implementation_phases/P0-C-golden-behavior-capture.md`).
Coding model: **Sonnet**; review: Sonnet (or human for extra safety on the golden net).

Render and byte-capture golden fixtures for all generated files across the environment
matrix (all-in-one, Redis, cAdvisor, S3 on/off). Add `actools.sh` to CI shellcheck
(closes the gap recorded in the authority map at "CI gaps"). No generator byte is changed;
this is the universal safety net that must be green before P0-D/P0-G can touch generation
logic.

## Explicitly forbidden scope for next task

- No runtime code change of any kind (P0-C is capture-only; generators are not touched).
- No promotion of `docs/target/phase0/operator/` to `docs/operator/`.
- No community-plus / `plus_*` feature work.
- No dispatcher, resolver, or profile wiring (those begin at P0-D/P0-E).
- No generated-file byte change (P0-C reads and captures current bytes, never changes them).

## Review Gate notes

Use a **separate Sonnet window** to render APPROVED / NEEDS REVISION / BLOCKED.

Key things to verify in the review:
1. **Scope — doc-only.** `git diff --stat -- ':!docs'` is EMPTY: `actools.sh`, `installer/*`,
   `cli/*`, `profiles/*`, `modules/*`, `core/*`, `.github/workflows/*` all untouched.
2. **No community-plus feature work** — no `plus_*` module, no `profiles/community-plus.profile`.
3. **Banner on every operator doc** — `grep -rL "Phase 0 target contract" docs/target/phase0/operator/`
   returns only `.gitkeep`.
4. **No surviving false assertion** — `grep -nE '21 bats|never contains business logic|"version": "11\.2|phases_complete' docs/architecture.md` returns empty.
5. **CHANGELOG false claim gone** — `grep -n 'moved to template variables' docs/CHANGELOG.md` returns empty.
6. **No doc asserts current-released or community-plus implemented** — spot-check each
   target doc for prohibited claims.
7. **Ledger Entry 007 complete** — records files changed, no runtime change, Review Gate Pending, next task P0-C.
8. **Cross-links resolve** — each target doc links to `docs/architecture/{phase0-seam-contract,generated-file-contract,cli-authority-contract}.md`.
