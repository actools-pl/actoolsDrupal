# CLI Authority Contract

## Problem

The project must not have two divergent operator CLIs.

## Target rule

There is exactly one canonical source for `/usr/local/bin/actools`.

Acceptable implementations:

### Option A — Copy static CLI

- canonical source: `cli/actools`
- installer copies it to `/usr/local/bin/actools`
- installer sets executable bit
- tests compare installed copy to source

### Option B — Generate CLI from template

- canonical source: `cli/actools.template`
- installer renders it once
- generated output has golden fixture tests
- no second static implementation exists

## Recommended choice

Prefer **Option A** unless runtime substitution is truly required.

## CLI parity matrix

Before changing CLI authority, complete this table:

| Command | Current generated CLI | Current static CLI | Target behavior | Notes |
|---|---|---|---|---|
| status |  |  |  |  |
| doctor |  |  |  |  |
| audit |  |  |  |  |
| backup |  |  |  |  |
| update |  |  |  |  |
| restore |  |  |  |  |
| restore-test |  |  |  |  |
| logs |  |  |  |  |
| handoff |  |  |  |  |
| storage-info |  |  |  |  |
| tunnel |  |  |  |  |
| worker-run |  |  |  |  |

## Secret safety checks

The CLI must not expose DB passwords in process arguments.

Add a grep/static test for risky patterns such as:

````bash
-p"$DB_PASS"
--password="$DB_PASS"
````

If a temporary defaults file is used, ensure it has restrictive permissions and cleanup.

## Done means

- one CLI source exists,
- installed CLI is derived from it,
- command parity is documented,
- tests cover `bash -n`, help output, and key commands,
- generated/static split is removed or explicitly deprecated.

