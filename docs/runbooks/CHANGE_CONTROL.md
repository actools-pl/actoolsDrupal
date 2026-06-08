# Change Control

## Purpose

Every Phase 0 change must be small enough to review and safe enough to roll back.

## Change categories

### Documentation-only

Allowed changes:

- target docs,
- architecture contracts,
- runbooks,
- prompts,
- test plans.

Required checks:

- links valid,
- status banners correct,
- no current-state false claims.

### Test-only

Allowed changes:

- new failing tests,
- fixtures,
- CI checks.

Required checks:

- tests fail for the right reason before implementation, where practical,
- tests target live authority, not orphan code.

### Runtime seam

Allowed changes:

- resolver,
- dispatcher,
- profile validation,
- CLI authority,
- module extraction.

Required checks:

- `bash -n`,
- shellcheck if available,
- bats if available,
- golden-output checks where generated files are affected,
- e2e when install path changes.

## Change size limit

A runtime change should normally be one of:

- add dispatcher but call old function,
- move one generated file path,
- reconcile one CLI command group,
- add one profile validation rule,
- wire one surface through resolver.

Avoid mixed changes such as:

- CLI consolidation + stack extraction + profile validation in one commit.

## Commit message format

````text
phase0: <short imperative summary>

- What changed
- Why
- Tests run
- Generated-file impact
- Docs/ledger updated
````

## Rollback note requirement

Every release note must include:

````markdown
## Rollback

Revert commit <sha>. No data migration is expected / Data migration notes: ...
````

