# Claude Execution Model — Phase 0

> **This package assumes the entire Phase 0 implementation is executed by Claude (Opus / Sonnet), not by a human engineering team.** This runbook is the single source of truth for *which Claude model runs which phase*, how the generic "windows" map onto Claude sessions, and how the engineer-day estimates in `00_reference/actools-phase0-implementation-plan.md` translate into Claude work. Everything else in the package (contracts, tests, gates, ledger) is unchanged and applies regardless of who writes the code.

---

## 1. The one thing that does *not* change

Claude compresses the **authoring** of diffs — it does not remove the **gates**. The safety of Phase 0 comes from the golden-file byte checks, `bash -n`/shellcheck, the bats seam tests, the fake-profile e2e, and a cross-model review gate. Those run the same whether a human or Claude wrote the change. So:

- The reference report's **~25–47 engineer-day** band is best read as the **review-and-verification budget** — the slow, careful part — plus the wall-clock of the e2e/provisioning loop. That part barely shrinks.
- What Claude shrinks is the time to produce each reviewable diff. Expect **authoring** to go from days to a session, while **verification cadence** and **CI/e2e latency** become the real pace-setters.

Do not let "Claude is fast" become a reason to widen scope, skip a golden capture, or merge without the review gate. The non-negotiable safety rules in `README.md` and `04_runbooks/DRIFT_PREVENTION_RULES.md` still hold, verbatim.

---

## 2. Windows are Claude sessions

The package's four "windows" (`04_runbooks/AI_WINDOW_PROTOCOL.md`) are **Claude sessions**, each on a chosen model and surface:

| Window | Claude surface | Default model | What it does |
|---|---|---|---|
| Documentation Window | Claude (chat) or Claude Code | **Sonnet** | Writes target operator docs and contracts. No runtime code. |
| Coding Window | **Claude Code** | **Opus or Sonnet — per phase (§3)** | Implements exactly one phase file; runs the required shell checks; commits; produces a handoff. |
| Review Gate Window | Claude (chat) or Claude Code | **a *different* model/session than the coder** | Verifies diff, tests, generated-file impact, docs, ledger; approves / revises / blocks. |
| External Reviewer Window | Claude (chat) | **fresh Opus** on a frozen zip/branch | Independent pass against Phase 0 scope; does not direct coding. |

**Two rules specific to Claude:**

1. **Cross-model review.** The Review Gate should run on a *different Claude session* than the Coding Window, and ideally a *different model* (e.g. Opus coded → Sonnet reviews scope/tests; Sonnet coded → Opus reviews on the dangerous phases). This decorrelates errors — a model is worse at catching its own mistakes than another model's.
2. **Files are the memory, because the context window is not.** A Claude session is fresh and its context can compact mid-task. The ledger (`04_runbooks/PHASE0_LEDGER.md`), the handoff (`04_runbooks/HANDOFF_TEMPLATE.md`), and the architecture contracts are the durable memory that survives session boundaries and compaction. This is exactly why the package forbids chat-memory handoff — that rule is *load-bearing* under Claude, not optional hygiene.

---

## 3. Model assignment per phase

Pick the model by the *kind* of work: **Opus** for high-reasoning, high-blast-radius, byte-sensitive, or judgment phases; **Sonnet** for well-specified, mechanical, high-throughput phases. "Sessions" below are *focused Claude Code coding windows that each end in a reviewable diff + handoff*; a session may span several turns and a compaction.

| Phase | Title | Coding model | Est. coding sessions | Review model | Why this model |
|---|---|---|---|---|---|
| **P0-A** | Finalise authority map | **Opus** | 0–1 | Sonnet | Reasoning/reconciliation — but the synthesis already exists in `00_reference/`, so this is mostly *adopt + record the authority map*. |
| **P0-B** | Target operator docs | **Sonnet** | 1–2 | Opus or human | Well-specified writing from the contracts; throughput task. |
| **P0-C** | Golden behavior capture | **Sonnet** | 1–2 | **Opus** | Mechanical to write; Opus reviews **matrix completeness** (the modes that must be captured). |
| **P0-D** | Install-stage dispatcher | **Opus** | 1–2 | Sonnet | Behaviour-preserving wiring; subtle ordering / `set` interactions. |
| **P0-E** | Profile validation + resolver | **Opus** | 2–3 | **Opus** (diff session) | Resolver semantics + the LOCKED 3-tier resolution order + fail-before-persist logic. |
| **P0-F** | CLI authority | **Opus** (Sonnet for the parity matrix) | 1–2 | **Opus** | The generated CLI's nested, triple-escaped heredoc is the highest escaping-risk surface in the repo. |
| **P0-G** | Extract host/stack | **Opus** | **3–6** | **Opus** (different session) | The 468-line `setup_stack` extraction with byte-identical output — the single hardest, riskiest unit. |
| **P0-H** | Profile-aware surfaces | **Opus** | 2–3 | Opus/Sonnet | Wiring four surfaces through dispatch with fail-on-unknown semantics. |
| **P0-I** | Fake-profile e2e | **Sonnet** | 1–2 | **Opus** | Mechanical to script; Opus reviews that **every** dispatch point is asserted. |
| **P0-J** | Closure review | **Opus** | 1 | **Human + fresh Opus** (External Reviewer) | A go/no-go judgment that unblocks Phases 1–6 — keep a human in the loop here. |

**Totals (planning aid, not a commitment):** roughly **17–25 coding sessions** plus a review session each, the dangerous trio **P0-C / P0-F / P0-G** carrying most of the risk and most of P0-G's session count. Wall-clock is gated by review cadence and the e2e/provisioning loop, *not* by Claude throughput.

---

## 4. How a Coding Window runs under Claude Code

1. Open Claude Code on a clean branch on the chosen model (§3).
2. Feed it the phase prompt from `07_prompts/coding-agent-phase-prompt.md` with the bracketed values filled from the phase file's *Allowed/Forbidden/Objective*.
3. Claude reads the required contracts + the phase file, makes the change, and runs the **required checks** (the prompt's `bash -n` block + the phase's bats/golden/e2e). The golden-file diff is Claude's own feedback loop — it should re-run it until output is byte-identical (or the diff is intentional and release-noted).
4. **Three-attempt rule:** if Claude fails the same check three times, it stops and writes a blocker report instead of widening scope. (Under Claude this matters more, because a capable model will otherwise "helpfully" attempt a broader refactor.)
5. Claude commits with the `phase0:` message format and emits a handoff from `HANDOFF_TEMPLATE.md`.
6. A **separate** Review Gate session (different model) verifies and decides the next phase.

---

## 5. Guardrails that matter more with a capable model

- **Scope is the phase file — nothing else.** Capable models generalize; the phase's *Forbidden scope* list is the leash. Never give Claude a broad "modularize the repo" instruction (`DRIFT_PREVENTION_RULES.md` Rule 6).
- **No community-plus feature modules in Phase 0.** Claude must build only the *seam*; the `plus_*` modules belong to Phases 1–6 and must not be written here.
- **Byte-identity over plausibility.** A model can produce a compose file that *looks* right; only the golden diff proves it is. Trust the diff, not the explanation.
- **The repo's own comments are the map.** `installer/dispatch.sh:19-20` and the four surfaces' "not called in D.0 / lands in D.1+" comments tell Claude exactly where the wiring goes (P0-H). Point Claude at them.
- **Keep the human at the unlock.** P0-J flips a LOCKED gate; the External Reviewer (fresh Opus) plus a human sign-off is the intended check, not Claude self-certifying.

---

*This runbook is the Claude-execution layer over an otherwise model-agnostic process. If execution moves to a human team, ignore §2–§4 and use the engineer-day budget directly; everything else in the package is unchanged.*
