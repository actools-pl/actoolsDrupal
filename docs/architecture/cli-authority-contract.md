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

## Decision (P0-F)

**Option A is adopted.** `cli/actools` is the single canonical source. The
installer (`actools.sh` → `setup_cli`) installs the CLI by copying that file
verbatim:

````bash
install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools
````

The previous duplicate generator — a `cat > /usr/local/bin/actools <<HELPER`
heredoc inside `setup_cli` — has been removed. There is no longer a second CLI
implementation to drift.

Option B was rejected because no runtime substitution is actually required:
the CLI reads everything it needs at runtime from `ACTOOLS_HOME`,
`${INSTALL_DIR}/actools.env`, and `${INSTALL_DIR}/.actools-state.json`. The one
value the old heredoc baked in at install time (`INSTALL_DIR`) is now resolved
at runtime via `ACTOOLS_HOME` (written to `/etc/environment` by `setup_cli`),
with a self-location fallback for in-repo execution:

````bash
INSTALL_DIR="${ACTOOLS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
````

Because the installed file is a verbatim copy, the CLI is no longer a *generated*
artifact and is **not** part of the golden-fixture set. Its integrity is proven
directly by `tests/installer/cli_authority_test.bats` (installed == `cli/actools`)
rather than by a rendered golden. The six non-CLI generated files
(`my.cnf`, `Dockerfile.caddy`, `Dockerfile.php`, `Dockerfile.worker`,
`Caddyfile`, `docker-compose.yml`) are produced by `setup_stack`, which was not
touched, and remain byte-identical (golden drift 6/6).

## CLI parity matrix

Completed for P0-F. "Target behavior" is what the single canonical `cli/actools`
now does. Where the two prior CLIs differed, the rule was: adopt the
installed (generated) behavior when the difference was functional **or** a
one-line fix using a variable already in scope; pure-cosmetic ties go to the
existing static text. Differences resolved against the static CLI are called
out as accepted consequences.

| Command | Current generated CLI | Current static CLI | Target behavior | Notes |
|---|---|---|---|---|
| status | `docker compose ps` | `docker compose ps` | identical | no change |
| doctor | sources `cli/commands/doctor.sh`, `run_doctor` | same | identical | no change |
| audit | present: sets `ACTOOLS_HOME`, sources `modules/audit/lib/output.sh`, runs `modules/audit/audit.sh "${@:2}"` | absent | **ported from generated** | community module already ships (`--deep` is the only edition-gated mode); porting preserves parity, not a new feature. Added to help. |
| backup | `/etc/cron.daily/actools-backup` | same | identical | no change |
| update | safe snapshot (`--defaults-extra-file` via stdin→container, umask 077, trap); env-driven `drush updb` loop; `pull db redis`; soft error | risky `-p"$BACKUP_PASS"` snapshot; `for env in prod`; `pull db redis php_prod`; strict exit 1 + rollback hint + `BACKUP_PASS` guard | **merge**: safe snapshot (generated) + `BACKUP_PASS` guard, strict error handling, `php_prod` pull (static) + env-driven loop (generated) | password never in argv |
| restore | root ops via `MYSQL_PWD="$MARIADB_ROOT_PASSWORD"` in container; no `DB_ROOT_PASS` guard | risky `-p"$DB_ROOT_PASS"` root ops + dead guard | **safe root ops (generated)**; keep static confirm/checksum/glob and backtick-escaped DB name; drop dead `DB_ROOT_PASS` guard | `DB_ROOT_PASS` not exported to host → old guard was dead |
| restore-test | safe `MYSQL_PWD` root ops; **omits** `.restore-test-last`; appends an S3 reachability chain | risky `-p` root ops + dead guard; **writes** `.restore-test-last`; no S3 chain | **safe root ops (generated)** + **keep `.restore-test-last` (static)**; drop dead guard; **drop S3 chain** | marker is consumed by `cli/commands/doctor.sh`; generated's omission was a latent bug. S3 chain dropped (accepted consequence: avoids noise on non-S3 installs; no functional dependency). |
| logs | `docker compose logs -f [svc]` | same | identical | no change |
| handoff | absent | absent | N/A — no CLI action | "handoff" is an installer post-install concept (`installer/handoff.sh`); locked vocabulary only. No CLI parity work, no regression. |
| storage-info | reads `${INSTALL_DIR}/actools.env` | hardcoded `/home/actools/actools.env` | **`${INSTALL_DIR}` (generated)** | one-line fix; correct on non-default install dirs |
| tunnel | absent | present (`status\|restart\|logs`) | **keep (static)** | in the contract's vocabulary; installed CLI gains it (documented) |
| worker-run | `xelatex --version` (anomaly) | `drush queue:run actools_document_export` | **keep static** | matches documented intent; generated's xelatex call dropped (documented) |

Two further canonical-CLI cosmetics, outside the 12 rows but recorded for
completeness: `migrate` now prints the live `${XELATEX_MODE:-local}` instead of a
hardcoded `local` (one-line fix, matches generated); `dry-run` and the 2-tier
`help` keep the static wording (cosmetic ties), with the `audit` line added to
help.

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

**Status: satisfied (P0-F).** One source (`cli/actools`); installed CLI is a
verbatim copy of it; the parity matrix above is complete; `bash -n`, help
smoke, byte-identity, secret-safety, and key-command behavior are covered by
`tests/installer/cli_authority_test.bats`; the generated/static split is removed
(the `setup_cli` heredoc generator no longer exists). See ledger Entry 011 and
`docs/releases/P0-F-cli-authority.md`.

