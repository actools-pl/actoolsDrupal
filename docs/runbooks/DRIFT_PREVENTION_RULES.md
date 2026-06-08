# Drift Prevention Rules

## Rule 1 — Code is ground truth for current state

Docs may describe target behavior only when labelled as target/unreleased.

## Rule 2 — One source of truth per runtime concern

If two files implement the same runtime behavior, the authority map must identify which one runs and what will happen to the other.

## Rule 3 — No silent generated-file drift

Generated file bytes must be compared or intentionally explained.

## Rule 4 — No hardcoded plus paths

Community-plus paths must be resolved through the resolver.

## Rule 5 — No chat-memory handoff

Every phase produces a ledger entry and handoff note.

## Rule 6 — No broad prompts

Never ask a coding agent to “modularize the repo.” Assign one phase file.

## Rule 7 — No feature work during seam hardening

Phase 0 creates seams. It does not implement community-plus feature modules.

## Rule 8 — No docs promotion before proof

Target docs move from `docs/target/phase0/operator/` to `docs/operator/` only after implementation and tests prove them.

## Rule 9 — Tests must follow live authority

If `actools.sh` is live authority, tests must exercise or at least parse it. Testing only extracted modules is insufficient.

## Rule 10 — Review Gate owns sequencing

The Coding Window should not decide the next phase after completing a task. It should provide a blocker/ready report to the Review Gate.

