# Handoff — P0-A · Finalise Authority Map (adopt synthesis + materialize canon)

## Repository state

Branch: `phase0/P0-A-finalise-authority-map`  
Commit SHA: recorded by the operator at apply time (see `APPLY-P0-A.md` §4); base = current `main` HEAD (plan reference `839d3c8`; export carried no `.git`)  
Working tree clean? yes (after the single P0-A commit)  
Zip/package name if applicable: `actools_phase0_workflow_package_P0A.zip`

## Task completed

Executed **P0-A (doc-only)** + the **HOW_TO_RUN Step-0 materialization** in one branch/PR:

- **Adopted** the verified synthesis `00_reference/actools-phase0-implementation-plan.md` (did not re-derive).
- **Stood up the in-repo doc home** so later windows' documented read-paths resolve: `docs/architecture/*` (the four contracts), `docs/runbooks/*` (ledger, handoff template, change-control, drift rules, AI-window protocol, Claude execution model).
- **Recorded `docs/architecture/runtime-authority-map.md`** with `path:line` evidence **spot-verified read-only** against the repo (bootstrap, init, profile load, install-stage orchestration, host/stack/db/drupal/worker, CLI install, preflight, doctor, handoff, the resolver seam, every generated file). Each authority is marked `current` / `parallel` / `orphan` / `target`.
- **Created the design-canon home** `design/` (LOCKED + adopted plan + alignment + index) — **LOCKED §11 build-trigger #2**.
- **Folded the alignment's five §4 tightenings** into the phase prompts they name (in the package): 3-tier resolver + `resolve_profile_check` umbrella + `init` file-existence → **P0-E** and **P0-H**; append-only stage guard → **P0-D** (test) and **P0-I** (CI); resolver-bypass guard → **P0-I**.
- Added the ledger **Entry 006**, this handoff, the PR body, and the filled review-gate prompt.

No runtime shell/profile/CLI/generated-file byte was changed.

## Files changed

New in the repo (heredoc-created on the devbox — `APPLY-P0-A.md` §2):

- `design/Actools_Drupal_Community_Plus_LOCKED.md`, `design/actools-phase0-implementation-plan.md`, `design/actools-phase0-locked-alignment.md`, `design/README.md`
- `docs/architecture/runtime-authority-map.md` (**filled, verified**), `docs/architecture/phase0-seam-contract.md`, `docs/architecture/generated-file-contract.md`, `docs/architecture/cli-authority-contract.md`
- `docs/runbooks/PHASE0_LEDGER.md` (**Entry 006**), `docs/runbooks/HANDOFF_TEMPLATE.md`, `docs/runbooks/HANDOFF-P0-A.md`, `docs/runbooks/CHANGE_CONTROL.md`, `docs/runbooks/DRIFT_PREVENTION_RULES.md`, `docs/runbooks/AI_WINDOW_PROTOCOL.md`, `docs/runbooks/CLAUDE_EXECUTION_MODEL.md`
- `docs/target/phase0/README.md`, `docs/target/phase0/operator/.gitkeep` (placeholders — content is **P0-B**)
- `docs/reviews/P0-A-pr-body.md`

Changed in the workflow package only (process docs, not the repo): `04_runbooks/PHASE0_LEDGER.md`, `03_architecture_contracts/runtime-authority-map.md`, and the tightening fold-ins in `06_implementation_phases/P0-D|E|H|I`.

## Files not changed but relevant

- `actools.sh` (live spine; profile-blind: 0 refs to `ACTOOLS_PROFILE`/`PROFILE_INSTALL_STAGES`/`resolve_`/`dispatch::`) — untouched.
- `installer/{init,preflight,handoff,dispatch,profile,output}.sh`, `cli/actools`, `cli/commands/*`, `profiles/*`, `modules/*`, `core/*`, `.github/workflows/*` — untouched.
- The false `cli/actools:12-15` comment, the stale `docs/architecture.md`/`docs/CHANGELOG.md` claims — **left in place** (P0-F / P0-B·J scope), recorded in the authority map.

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | None — recorded only (`current` = `actools.sh`; `core/bootstrap.sh` = orphan v9.2) |
| Init | None — recorded only (partial; gaps to P0-E/P0-H) |
| Profile loading | None — recorded only (loader + accessors present) |
| Install stages | None — recorded only (dispatcher absent → P0-D) |
| CLI | None — recorded only (parallel: `setup_cli` heredoc vs `cli/actools` → P0-F) |
| Generated files | None — recorded only (all monolithic in `actools.sh`; orphan twins in `modules/stack/*`) |
| Preflight | None — recorded only (partial → P0-H) |
| Doctor | None — recorded only (split + hard-sourced → P0-F/P0-H) |
| Handoff | None — recorded only (partial → P0-H) |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | not touched |
| Caddyfile | not touched |
| my.cnf | not touched |
| Dockerfiles | not touched |
| CLI | not touched |

## Tests run

````bash
bash -n actools.sh                       # parses (untouched)
bash -n cli/actools                      # parses (untouched)
git diff --stat -- ':!docs' ':!design'   # empty: no non-doc change
# markdown link/structure spot-check on new docs (APPLY-P0-A.md §3)
````

## Test result

PASS (sandbox self-validation). No runtime/`*.sh`/workflow byte changed; new markdown parses and cross-links resolve. Authoritative runtime tests are not applicable to a doc-only phase; CI must still be green on the PR.

## Docs updated

`docs/architecture/runtime-authority-map.md` (filled). The other contracts/runbooks/canon are materialized verbatim. Operator target docs and `architecture.md`/`CHANGELOG.md` corrections are deferred to **P0-B**.

## Changelog / release notes updated

None this phase (doc-only). Review notes prepared at `review/review-gate-P0-A.md`.

## Ledger entry

Entry number: **006**

## Known risks

- P0-A intentionally bundles Step-0 materialization with the authority-map record; every materialized contract/runbook/canon file is a **verbatim** copy (no new authoring). Reviewer should confirm **no runtime byte moved** (`git diff --stat -- ':!docs' ':!design'` empty).
- Base SHA recorded at apply time; P0-A is heredoc-only (no patch), so not base-sensitive.

## Blockers

None.

## Exact next allowed task

**P0-B — Target Operator Documentation** — `06_implementation_phases/P0-B-target-operator-docs.md`.
Coding model **Sonnet**; review Opus or human. Write the operator-facing target docs under
`docs/target/phase0/operator/*` with an "unreleased target behaviour" **status banner on every file**:
the default `community` install journey, the profile lifecycle + error behaviour, the command surface as
a *target contract*, generated-file safety expectations, and troubleshooting language; **cross-link** the
now-materialized `docs/architecture/{phase0-seam-contract,generated-file-contract,cli-authority-contract}.md`.
As doc reconciliation, correct the false claims this phase recorded (`docs/architecture.md` v11.2/business-logic/
21-tests/`phases_complete`/`actools-real`; `docs/CHANGELOG.md:113` Dockerfile claim). Add ledger Entry 007.

## Explicitly forbidden scope for next task

- No runtime code; no tests except documentation references.
- **No promotion to `docs/operator/`** (target docs stay under `docs/target/phase0/`).
- No `plus_*` / community-plus feature work; no new community-plus CLI commands.
- No generated-file change; no dispatcher/resolver/profile edits (those begin at P0-D/P0-E).
- Do not claim any target behaviour is currently released (grep gate: no `currently supports community-plus` unless true).

## Review Gate notes

Use `review/review-gate-P0-A.md` in a **separate Sonnet window** (P0-A is low-risk doc-only; Sonnet is the default reviewer). The Conductor prepared the prompt and does **not** render the verdict. Expect APPROVED / NEEDS REVISION / BLOCKED; on NEEDS REVISION, start a fresh Conductor with the notes + current HEAD (stay within P0-A scope).
