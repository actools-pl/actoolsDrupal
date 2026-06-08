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

