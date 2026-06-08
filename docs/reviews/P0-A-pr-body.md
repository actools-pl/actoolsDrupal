# phase0(P0-A): adopt synthesis, materialize canon + authority map

**Phase:** P0-A — Finalise Authority Map (doc-only) · **Risk:** low (no runtime byte changes)

## What this PR does

Bootstraps the in-repo Phase-0 documentation home and records the runtime authority map, executing
**HOW_TO_RUN Step-0 materialization** + **P0-A** in one commit.

- **Adopts** the verified synthesis (`design/actools-phase0-implementation-plan.md`) — not re-derived.
- **Materializes** the package's living docs into the repo so every later window's read-paths resolve:
  `docs/architecture/*` (seam / generated-file / CLI contracts + the authority map) and
  `docs/runbooks/*` (ledger, handoff template, change-control, drift rules, AI-window protocol, Claude execution model).
- **Records `docs/architecture/runtime-authority-map.md`** with `path:line` evidence spot-verified
  read-only against this repo, marking each concern `current` / `parallel` / `orphan` / `target`.
- **Creates the design-canon home** `design/` (LOCKED + adopted plan + alignment + index) — **LOCKED §11 build-trigger #2**.
- **Folds** the alignment's five §4 tightenings into the phase prompts (in the workflow package):
  3-tier resolver + `resolve_profile_check` umbrella + `init` file-existence → P0-E/P0-H;
  append-only stage guard → P0-D/P0-I; resolver-bypass guard → P0-I.

## What this PR explicitly does NOT change

- **No runtime byte.** `actools.sh`, `installer/*`, `cli/*`, `profiles/*`, `modules/*`, `core/*`, and
  `.github/workflows/*` are untouched. `git diff --stat -- ':!docs' ':!design'` is empty.
- **No generated-file change** (compose / Caddyfile / my.cnf / Dockerfiles / CLI generators all unedited).
- **No `plus_*` / community-plus feature work**; no `profiles/test.profile` or `community-plus.profile`.
- Stale/false claims recorded but **left for their owning phases**: false `cli/actools:12-15` comment → P0-F;
  `docs/architecture.md` (v11.2 / "never contains business logic" / 21-tests / `phases_complete` / `actools-real`)
  and `docs/CHANGELOG.md:113` Dockerfile claim → P0-B/P0-J; `actools.sh`→shellcheck and fake-profile e2e → P0-I.

## Verification

- Doc-only diff confirmed (`git diff --stat -- ':!docs' ':!design'` empty).
- `bash -n actools.sh` and `bash -n cli/actools` still parse (proving they were untouched).
- Authority-map `path:line` citations spot-verified read-only against the repo.

## Review

Cross-model review in a separate **Sonnet** window using `review/review-gate-P0-A.md` (this is a low-risk
doc-only phase; Sonnet is the default reviewer). Ledger **Entry 006** records the full impact; community-plus
remains **BLOCKED** and Phase 0 is not closed. Next task: **P0-B** (target operator docs).

Deferred / recorded: see the ledger Entry 006 "Files intentionally not changed" and the authority map's
"Verified secondary facts".
