# Release note — P0-N · CLI DB-Layer Convergence (live `doctor.sh`)

Phase: P0-N (post-closure track) · Date: 2026-06-12 · `ACTOOLS_VERSION` unchanged at `14.0`

## What shipped

1. **The live `doctor` command resolves its DB layer from the P0-M
   authority.** `cli/commands/doctor.sh` carried its own copy of
   `db_exec_root` (`:27`) — byte-identical to `modules/db/core.sh:45`
   *today* (re-verified, including the explanatory comment), but a second
   truth: a future fix to the module's `db_exec_root` would silently not
   reach `doctor`. The local def + comment (`:24-29`) are replaced **in
   place, 6-for-6 lines**, by a pointer comment + a best-effort source of
   the authority, so the one call site stays byte-untouched at `:160` and
   `db_exec_root` keeps its old source-time definition timing. The six DB
   functions are now defined **only in `modules/db/core.sh` across both
   runtimes** (installer and CLI); the five `doctor` doesn't call arrive
   inert (the module is pure function defs — nothing runs at source time).

2. **A live-CLI-path guard** (`tests/guards/cli_db_authority_guard_test.bats`,
   7 arms). The live CLI path — `cli/actools` plus every
   `cli/commands/*.sh` it sources (today: `doctor.sh`) — must define none
   of the six canonical DB names; the authority is excluded by
   construction. Non-vacuity is permanent (fixture arms for an injected
   definition on a live command file, on `cli/actools` itself, and for a
   missing source target) and was additionally demonstrated live:
   re-adding the old def to `doctor.sh` fails the main arm at the exact
   line; reverted byte-identical (sha-verified). The eight dead-twin
   command files (P0-O scope) are naturally excluded — `cli/actools`
   sources none of them — so the guard is green before and after their
   deletion.

3. **A focused authority test** (`tests/cli/doctor_db_authority_test.bats`,
   7, + a small loader). Pins the convergence from the resolution side:
   no local def remains; the source line is present; sourcing `doctor.sh`
   is inert; the resolved `db_exec_root`'s `declare -f` body is
   **byte-equal** to the canonical `core.sh` body; without the module on
   disk the function is *not* defined (the definition provably travels
   `${INSTALL_DIR}/modules/db/core.sh` — a typo'd path goes red here);
   and under the P0-M mock `docker` the resolved function issues the
   exact canonical container command.

## One flagged deviation

The spec snippet showed a bare `source`; the landed line is best-effort
(`2>/dev/null || true`). `doctor.sh` must stay sourceable in a **minimal
sandbox** — its own header documents that contract for the `dispatch.sh`
and env-file sources, and the deep-gate test suites stage `INSTALL_DIR`s
without `modules/` (a bare source broke 9 existing tests). The risk a
silent `|| true` could mask (a mis-pathed module) is pinned red by the
focused test's resolution arms; the real-install backstop is the existing
e2e doctor-smoke.

## Operator impact

None. `doctor`'s behavior and output are unchanged (verbatim-equivalent
swap — the resolved function is byte-identical to the deleted copy);
`cli/actools` is byte-unchanged; nothing generated changed (drift 6/6 +
cron 3/3, no fixture modified).

## Gate status

**No new e2e gate** — P0-N is not a behavior change (unlike P0-M's
`wait_db`). The existing doctor-smoke (`e2e.yml:126`: `actools doctor` +
`--deep` on a real install) is the integration backstop; dispatching
`e2e.yml` on the branch is recommended but not required for approval.
P0-M's Entry 018 was ratified in this phase: merge SHA `cd0d0d9` (#47)
stamped; the `wait_db:510` risk **CLOSED — e2e-confirmed** (run #75
reached `MariaDB ready.`).
