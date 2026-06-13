# Handoff — P0-O · Orphan Disposition + Doc-Authority Lock

## Repository state

Branch: `phase0/P0-O-orphan-disposition` (sandbox; operator applies onto `main` @ `6a6671c`)
Commit SHA: three implementation commits + one docs commit (sandbox sequence: `55ece86` delete the eight twins → `1f046ca` tighten the CLI DB guard to repo-wide → `c7891b0` doc reconciliation → docs). Sandbox baseline `4e2f620` = the import of `main` @ `6a6671c` (P0-N merged, PR #48); substitute `6a6671c` when reproducing against the real repo.
Working tree clean? yes (each commit left the P0-O-relevant suites green; full suite 231 at HEAD — see the jq caveat below).
Zip/package name if applicable: n/a (work done in-tree on the imported zip; baseline had no `.git`, so the sandbox was `git init`'d at the import).

## Task completed

P0-O per `P0-O-orphan-disposition.md`: the **eight dead twin command files**
under `cli/commands/` —
`{backup,ci_generate,cost_optimize,health,restore,storage,update,worker}.sh`
(425 lines) — are **deleted**. They were the original per-file CLI design that
`cli/actools` superseded by **inlining** every user-facing command; their
`cmd_*`/`run_*` functions are called **0×** in `cli/actools`, the profile
resolver only ever resolves `doctor_deep`, and three of them carried inert
byte-identical copies of the P0-M DB functions (`cost_optimize.sh:10`,
`restore.sh:9`+`:15`, `update.sh:10`) — copies that never ran because the files
were never sourced. The P0-N CLI DB-authority guard is **tightened** from a
live-path-scoped check to a **repo-wide-CLI** invariant
(`tests/guards/cli_db_authority_guard_test.bats`): the `DEAD_TWINS` allow-list
is gone, replaced by a list-free oracle that fails on any DB-fn definition in
**any** `cli/commands/` file. The narrow operator/architecture doc surface is
reconciled so nothing points at a deleted file. Dead-code removal — **no
behavior change**, no new e2e gate; `cli/actools` is **byte-identical** to
baseline (SHA-256 `d2c64c9…`).

This is the CLI analog of P0-M's `modules/db` twin purge: the same orphan
dual-truth (an inert duplicate of a canonical function), removed at the root by
deleting the files that carried it.

### No flagged deviations

Unlike P0-N (whose `|| true` source deviation needed a Review-Gate decision),
P0-O landed within the spec's allowed-files list with no deviation to flag. The
one judgment call — **leaving `modules/ai` in place** — is the spec's own
boundary (`modules/ai` is a separate future pass), recorded under Known risks so
it is not forgotten, not a deviation from the ask.

## Files changed

- **DELETED (8):** `cli/commands/{backup,ci_generate,cost_optimize,health,restore,storage,update,worker}.sh` (425 lines; `git rm`)
- `tests/guards/cli_db_authority_guard_test.bats` — tightened to repo-wide-CLI (release-noted in the header; −1 arm / +2 arms, 7 → 8; the P0-N live-CLI machinery retained)
- `docs/advanced.md` — the CI/CD blockquote no longer presents the deleted `cli/commands/ci_generate.sh` as where "the code lives" (restated as planned, no implementation; placeholder removed in P0-O)
- `docs/architecture/runtime-authority-map.md` — the Worker-provisioning row repointed from the deleted `cli/commands/worker.sh` to the inline `cli/actools` command (`worker-logs` `:103`); one command-authority blockquote added before "Verified secondary facts"; history left verbatim
- `docs/runbooks/PHASE0_LEDGER.md` — Entry 020 (decision **Pending**) + Entry 019 ratified (merge SHA `6a6671c`/#48 stamped; decision flipped to **APPROVED**; the original pending text preserved inline for the record — the same house-style as the P0-N ratification of Entry 018)
- `docs/CHANGELOG.md` — P0-O Unreleased section (+ the Entry-019 ratification note)
- `docs/releases/P0-O-orphan-disposition.md`, `docs/tests/P0-O-orphan-disposition.md`, this handoff

## Files not changed but relevant

- **`cli/actools`** — **byte-identical** to baseline (SHA-256 `d2c64c9…`). The inline `backup` (`:197`), `storage-test` (`:117`), `worker-logs` (`:103`), `health` (`:199`), `update` (`:163`), `restore` (`:241`) commands are **untouched** — only their dead duplicate *files* were deleted.
- **`modules/ai/`** — dead (no `ai` branch in `cli/actools`; nothing live sources it). Left in place; its disposition is a deliberate **future pass** (its own orphan-removal). Only confirmed it does not make the deletion unsafe: its `cli/commands/*.sh` glob (`assistant.sh:30`) is dead code and now resolves to the two live handlers. The one surviving textual reference to the old `cli/commands/` shape.
- `modules/db/core.sh` — the P0-M authority (defines all six DB names); **no edits** (P0-M contracts 13/13 and both P0-M guards green, untouched).
- `cli/commands/doctor.sh`, `cli/commands/doctor_deep.sh` — the two live handlers; **untouched** (forbidden scope). `doctor` still resolves its DB layer from `modules/db/core.sh` (P0-N holds — `tests/cli/` 7/7).
- `actools.sh`, `main()`, `installer/`, `profiles/`, `.github/workflows/` (recursive bats auto-discovers the suites — no workflow edit needed), golden fixtures (none modified).
- Historical phase records — `HANDOFF-P0-*` / `LEDGER` 001–019 bodies / `tests/P0-*` docs: left **verbatim** (only Entry 020 added + Entry 019 ratified).

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | none |
| Install stages | none |
| CLI | the eight dead twin *files* removed; every user-facing command stays **inline** in `cli/actools` (byte-unchanged); behavior identical |
| Generated files | none |
| Preflight | none |
| Doctor | none — `doctor.sh`/`doctor_deep.sh` untouched; DB layer still resolves from `modules/db/core.sh` |
| Handoff | none |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | not touched (drift 6/6) |
| Caddyfile | not touched (drift 6/6) |
| my.cnf | not touched (drift 6/6) |
| Dockerfiles | not touched (drift 6/6) |
| CLI | not touched (`cli/actools` byte-identical `d2c64c9…`; `cli_authority`/`doctor` arms green) |
| /etc/cron.daily/actools-backup | not touched (cron drift 3/3) |

## Tests run

```bash
$ bash -n cli/actools && echo SYNTAX_OK
SYNTAX_OK

$ ls cli/commands/
doctor.sh
doctor_deep.sh

$ for f in backup ci_generate cost_optimize health restore storage update worker; do
    grep -rIn "cli/commands/$f\.sh\|/$f\.sh" . --include='*.sh' --include='*.yml' --include='*.bats' | grep -v '\.git/'
  done
(no output — empty; no live reference to any deleted twin)

$ sha256sum cli/actools
d2c64c94526b2347da93a390baa293ee4abd4fe5e987b16900744c19355a3ebf  cli/actools

$ bats tests/guards/
1..21        # 13 sibling guards + 8 tightened cli_db_authority — all ok (full listing: test report §6)

$ bats tests/cli/
1..7         # all ok — the P0-N focused doctor test unaffected (full listing: test report §6)

$ bats tests/db/
1..13        # all ok — P0-M contracts unaffected

$ bats tests/generated/
1..9         # all ok — drift 6/6 + cron 3/3, no fixture modified

$ bats -r tests/
1..231       # 219 ok + 12 jq-environmental not-ok (see "Test result" + test report §10); CI is 231/231

$ git diff 4e2f620 --stat -- cli/commands/
 ... 8 files changed, 425 deletions(-)
```

The full per-test listings, the deadness proof, the guard-tightening arm diff,
the inject-and-revert guard demo (both oracles biting at `:258`, reverted
sha-verified), the doc-reconciliation diffs, and the jq-environmental A/B
(baseline vs HEAD, same 12) are pasted verbatim in
`docs/tests/P0-O-orphan-disposition.md`.

## Test result

PASS — P0-O-relevant suites green: `tests/guards/` 21/21, `tests/cli/` 7/7,
`tests/db/` 13/13, `tests/generated/` 9/9 (drift 6/6 + cron 3/3); the tightened
guard is non-vacuous (the permanent repo-wide rogue-fixture arm + the captured
live inject-and-revert demo that bites **both** the live-CLI and repo-wide arms
at `cli/commands/doctor.sh:258`, reverted byte-identical to sha `ac5eda8c…`).
Full recursive suite **230 → 231** (the intended delta: −1 dead-twin arm, +2
repo-wide arms).

**jq caveat (review-sandbox honesty).** This sandbox could not install `jq`
(apt 404; the GitHub-releases CDN 403; `node-jq` postinstall 403), so **12
jq-dependent `tests/core/` tests** (state/secrets JSON round-trips — tests
27–32, 37–45) report `not ok`. A git-worktree A/B in the same jq-less env proves
they pre-exist P0-O **identically**: baseline `4e2f620` = 230 plan / 218 ok / 12
not-ok; HEAD = 231 plan / 219 ok / **the same 12** not-ok. They are outside P0-O
scope; P0-O adds exactly +1 passing test. On CI (jq provisioned) the suite is
**231/231 green**.

## Docs updated

Ledger (Entry 020 + Entry 019 ratification), runtime-authority-map (Worker row
repointed + command-authority blockquote; history verbatim), advanced.md (CI/CD
section reconciled), CHANGELOG, release note, test report, this handoff.

## Changelog / release notes updated

Yes — `docs/CHANGELOG.md` (P0-O Unreleased + Entry-019 ratification note),
`docs/releases/P0-O-orphan-disposition.md`.

## Ledger entry

Entry number: **020** (decision: **Pending** — the Review Gate's call, not
marked Approved here, per the spec). Entry **019** ratified per the spec (merge
SHA stamp + decision flip only; the original pending text preserved inline for
the record, matching how Entry 018 was ratified at P0-N).

## Known risks

1. **`modules/ai` left in place (dead).** Its `cli/commands/*.sh` glob
   (`assistant.sh:30`) is now the only surviving reference to the directory's
   old per-file shape; it resolves to the two live handlers and is harmless.
   `modules/ai`'s disposition is a deliberate **future pass** (its own
   orphan-removal), explicitly out of P0-O scope — flagged so it is not
   forgotten.
2. **The repo-wide arm is `cli/commands`-scoped.** A DB-fn copy introduced
   **elsewhere** on a future live path (a newly-sourced directory) is not caught
   by *that* arm — but the **retained live-CLI arm** covers `cli/actools` and
   every file it sources, and any new wiring pattern is the Review Gate of that
   phase's responsibility (the live arm's missing-target arm fails loudly on
   half-wired states).
3. **No new e2e was run in the sandbox** (no docker daemon / cloud token). The
   post-merge doctor/install smoke is the recommended backstop; because the
   eight files are provably dead it is **not gating** (no behavior-change gate).
   Flagged, not guessed.

## Blockers

None.

## Exact next allowed task

**P0-P — profile-selected install** — **GATED** until a second profile exists
(likely deferred). `main()`'s hardcoded `community.profile` source is the last
resolver-blind spot on the install spine; with only one profile there is nothing
to select. `modules/ai` and any remaining standalone-feature orphans are
**separate future passes**.

## Explicitly forbidden scope for next task

No wiring of any deleted-twin behavior back onto a command file (the guard's
repo-wide **and** live arms both bite); no edits to `modules/db/core.sh` or the
P0-M contracts/guards without an explicit release note; no `modules/ai` changes
(its own future pass); no generated-file change; `main()`'s hardcoded profile
source stays until P0-P.

## Review Gate notes

In the order the spec lists — verify offline:

1. **The eight files are gone and no live reference survives.**
   `ls cli/commands/` → `doctor.sh  doctor_deep.sh` only;
   `for f in backup ci_generate cost_optimize health restore storage update
   worker; do grep -rIn "cli/commands/$f\.sh\|/$f\.sh" . --include='*.sh'
   --include='*.yml' --include='*.bats' | grep -v '\.git/'; done` → **empty**.
   The only conceptual survivor is the `modules/ai/assistant.sh:30` dead glob
   (out of scope) and historical doc lines (left verbatim).
   `git diff 6a6671c --stat -- cli/commands/` shows only the 8 deletions
   (425 lines).
2. **`cli/actools` is byte-identical.** `sha256sum cli/actools` →
   `d2c64c9…` (the recorded baseline). The inline commands are untouched — only
   the dead duplicate files were deleted.
3. **The tightened guard is non-vacuous and bites.** Reproduce the demo: append
   a `db_exec_root() { …; }` definition to a `cli/commands/` file →
   `bats tests/guards/cli_db_authority_guard_test.bats` fails **both** the
   live-CLI arm (3) and the repo-wide arm (7), each naming the file:line
   (`:258` in the captured run); revert (sha-verified, test report §8). The
   repo-wide rogue-fixture arm (8) and the three live fixture arms (4–6) bite on
   every CI run.
4. **Drift 6/6 + cron 3/3** — `bats tests/generated/` → 9/9, no fixture modified
   (`git diff 6a6671c -- tests/fixtures/` empty).
5. **The doc reconciliation is minimal and rewrites no history** —
   `git diff 6a6671c -- docs/advanced.md` is one blockquote line;
   `git diff 6a6671c -- docs/architecture/runtime-authority-map.md` is the
   Worker row + one added blockquote; the P0-N narrative lines, `HANDOFF-P0-L`,
   older `LEDGER` entries, and `tests/P0-N`/`tests/P0-L` are untouched.
6. **The install still works with the twins gone** — branch e2e dispatch
   recommended (not gating; P0-O adds no new e2e gate): install reaches
   `MariaDB ready.` and `actools doctor` works on a real install, unchanged
   (every command is inline in the byte-identical `cli/actools`). Not run in the
   sandbox (no docker daemon / cloud token) — flagged, not guessed.

Plus the flagged item: `modules/ai` left in place (Known risk 1) — a recorded
future pass, not a P0-O deviation. The patch reproduces the tree from `6a6671c`
+ the four commits. **APPROVE on green** per the spec.
