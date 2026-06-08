# AI Window Protocol

## Purpose

Prevent drift when work moves between AI windows.

> **Execution note:** every window in this protocol is a **Claude session (Opus or Sonnet)**. Per-phase model assignment and the engineer-day→session translation live in `04_runbooks/CLAUDE_EXECUTION_MODEL.md`. Two Claude-specific rules apply throughout: (1) the Review Gate runs on a **different session — ideally a different model** — than the Coding Window, to decorrelate errors; (2) **files are the memory** (ledger, handoff, contracts), because a Claude session is fresh and its context can compact mid-task. The no-chat-memory rule below is therefore load-bearing, not optional.

## Roles

### Documentation Window — *Claude (Sonnet)*

Writes target docs and contracts. Does not change runtime code unless explicitly asked.

### Coding Window — *Claude Code (Opus or Sonnet, per phase — see `CLAUDE_EXECUTION_MODEL.md` §3)*

Implements one narrow phase. Does not interpret broad architecture beyond the phase file. Use **Opus** for the byte-sensitive / high-reasoning phases (P0-D, P0-E, P0-F, P0-G, P0-H) and **Sonnet** for the well-specified throughput phases (P0-B, P0-C, P0-I).

### Review Gate Window — *Claude on a different model/session than the coder*

Verifies diffs, tests, docs, changelog, and ledger. It decides whether the next phase can be assigned. On the dangerous phases (P0-C, P0-F, P0-G), prefer **Opus** as the reviewer.

### External Reviewer Window — *fresh Claude (Opus) on a frozen branch/zip*

Reviews a frozen branch or zip against a specific prompt. Does not direct coding directly.

## Golden rule

No AI window continues from chat memory alone.

Every handoff must include:

- branch,
- commit SHA,
- changed files,
- tests run,
- test results,
- docs changed,
- changelog/release note status,
- ledger entry number,
- unresolved risks,
- next allowed task,
- forbidden scope.

## Three-attempt rule

If the Coding Window fails the same task three times, it must stop and produce a blocker report for the Review Gate. It must not improvise a broader redesign.

## Scope discipline

Every coding prompt must say:

- allowed files,
- forbidden files,
- exact objective,
- exact tests,
- exact docs to update,
- exact ledger entry required.

## Review Gate acceptance

The Review Gate may approve a phase only if:

- diff matches scope,
- tests pass or failures are explained,
- generated-file impact is recorded,
- docs/changelog/ledger are updated,
- next task is narrow.

