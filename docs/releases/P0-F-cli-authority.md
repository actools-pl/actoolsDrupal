# Release note — P0-F · CLI Authority Consolidation

Phase: P0-F — CLI Authority Consolidation
Branch: `phase0/P0-F-cli-authority`
Date: 2026-06-09
Status: pending Review Gate

## Summary

The project had **two divergent operator CLIs**: one generated at install time by
a `cat > /usr/local/bin/actools <<HELPER` heredoc inside `actools.sh::setup_cli`,
and a static `cli/actools`. P0-F collapses them into **one canonical source**
(**Option A** of the CLI Authority Contract):

- `cli/actools` is the single source of truth.
- `setup_cli` installs the CLI by **copying that file verbatim**
  (`install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools`).
- The duplicate generator heredoc is **deleted**.
- Secret handling is uniformly **safe** (no DB password ever reaches a process
  argument list).
- Every command's behavior is retained per the parity matrix below; where the two
  CLIs differed, the safer/functional behavior was kept and any drop is called out.

This is the **first** Phase-0 change in which a generated file is **Changed
intentionally** rather than held byte-identical. That change is the CLI itself.
The **six non-CLI generated files are byte-identical** (golden drift 6/6).

## Why Option A (not Option B)

No runtime substitution is actually required. The CLI reads everything it needs at
runtime: `ACTOOLS_HOME`, `${INSTALL_DIR}/actools.env`, and
`${INSTALL_DIR}/.actools-state.json`. The only value the heredoc baked in was
`INSTALL_DIR`; it is now resolved at runtime:

```bash
INSTALL_DIR="${ACTOOLS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
```

`setup_cli` already writes `ACTOOLS_HOME` into `/etc/environment`, so the installed
copy resolves correctly; the self-location fallback covers in-repo execution
(tests, `./cli/actools`).

## Generated-file status (generated-file contract)

| File | Status | Evidence |
|---|---|---|
| `my.cnf` | **Unchanged** (byte-identical) | golden drift 6/6; `setup_stack` not touched |
| `Dockerfile.caddy` | **Unchanged** | golden drift 6/6 |
| `Dockerfile.php` | **Unchanged** | golden drift 6/6 |
| `Dockerfile.worker` | **Unchanged** | golden drift 6/6 |
| `Caddyfile` | **Unchanged** | golden drift 6/6 |
| `docker-compose.yml` | **Unchanged** | golden drift 6/6 |
| **CLI (`/usr/local/bin/actools`)** | **Changed intentionally** | CLI authority consolidated to `cli/actools` (Option A); CLI is no longer generated; the `actools-cli` golden fixture is retired and replaced by a direct installed==source test (`tests/installer/cli_authority_test.bats`). Behavior changes are bounded by the parity matrix below. |

## CLI parity matrix

"Target" = what the single canonical `cli/actools` now does. Rule: adopt the
installed (generated) behavior where the difference was functional or a one-line
fix using a variable already in scope; pure-cosmetic ties keep the existing static
text.

| Command | Generated CLI (old, heredoc) | Static CLI (old `cli/actools`) | Target (canonical now) | Disposition |
|---|---|---|---|---|
| status | `docker compose ps` | same | same | unchanged |
| doctor | source `doctor.sh` + `run_doctor` | same | same | unchanged |
| logs | `docker compose logs -f [svc]` | same | same | unchanged |
| backup | `/etc/cron.daily/actools-backup` | same | same | unchanged |
| update | safe snapshot; env-driven loop; `pull db redis`; soft error | risky `-p` snapshot; `for env in prod`; `pull db redis php_prod`; strict exit + guard | safe snapshot **+** guard/strict-error/`php_prod` **+** env-driven loop | merged |
| restore | `MYSQL_PWD` root ops; no guard | risky `-p` root ops; dead guard | safe `MYSQL_PWD` ops; keep confirm/checksum/backtick DB name; drop dead guard | safer wins |
| restore-test | safe `MYSQL_PWD` ops; **no** `.restore-test-last`; **+ S3 chain** | risky `-p` ops; **writes** `.restore-test-last`; no S3 chain | safe `MYSQL_PWD` ops **+ keep `.restore-test-last`**; **drop S3 chain** | safer wins; marker kept; S3 chain dropped |
| storage-info | `${INSTALL_DIR}/actools.env` | hardcoded `/home/actools/actools.env` | `${INSTALL_DIR}` | fix |
| migrate | `${XELATEX_MODE:-local}` | hardcoded `local` | `${XELATEX_MODE:-local}` | fix |
| health | env-driven loop | `for env in prod` | env-driven loop | fix (identical for community) |
| audit | present | **absent** | **ported** (present) | parity restored |
| tunnel | **absent** | present | **kept** | additive on installed host |
| worker-run | `xelatex --version` (anomaly) | `drush queue:run actools_document_export` | keep static | anomaly dropped |
| dry-run | cosmetic wording | cosmetic wording | static text | cosmetic tie |
| help | flat list | 2-tier (basic/advanced) | 2-tier **+ `audit`** | static + audit |
| handoff | absent | absent | N/A (installer concept) | no CLI action |

## Secret safety

- **No DB password is ever passed on a command line.** A static test greps for
  `-p"$…"` / `-p$…` / `--password=` and fails the build if any appears.
- **Snapshot (`update`)** writes a temporary MariaDB defaults file **inside the db
  container** with `umask 077` and a `trap` that removes it on exit; the password
  is piped in over stdin.
- **Root operations (`restore`, `restore-test`)** use
  `MYSQL_PWD="$MARIADB_ROOT_PASSWORD"` sourced from the db container's own
  environment (set by the compose generator at `actools.sh` → `MARIADB_ROOT_PASSWORD`),
  so the secret is never in `ps`/argv on host or container.

## Operator impact

- **`actools restore-test` no longer runs an implicit S3 round-trip.** Run
  `actools storage-test` explicitly when you want it. This avoids spurious failures
  on non-S3 installs.
- **The installed CLI now also offers `actools tunnel` and a 2-tier `actools help`
  (`actools help advanced`), plus `actools audit`.** These are additive.
- **No change for the common path.** For a community install (`ENVIRONMENTS=prod`),
  `update`/`health` behave exactly as before; `storage-info`/`migrate` now display
  the correct configured values.
- **No data migration. No change to the six generated stack files.**

## Verification

```bash
export PATH="$HOME/.npm-global/bin:$PATH"
bats tests/generated/golden_drift_test.bats                                 # 6/6 (six non-CLI files byte-identical)
bats tests/installer/cli_authority_test.bats                                # 14/14 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
grep -nE '(-p"?\$|--password=)' cli/actools                                 # no matches
```

133/133 overall (golden 6 + unit/integration 127). The installed CLI is proven a
byte-for-byte copy of `cli/actools` by extracting `setup_cli`, redirecting its two
root-only host writes to temp paths, running it rootless, and diffing the result
against `cli/actools` (empty diff).

## Rollback

Revert the P0-F commit(s) `<sha>`. No data migration is expected. The change is
confined to `cli/actools`, the `setup_cli` section of `actools.sh`, the golden
capture harness, the golden fixtures (`actools-cli` removal + manifest entry
counts), `tests/installer/cli_authority_test.bats`, `tests/generated/golden_drift_test.bats`,
and docs.

Reverting restores the prior dual-CLI arrangement (the `HELPER` heredoc generator
and the unmodified static `cli/actools`), the 7-entry golden manifests with the
`actools-cli` fixture, and the harness `SC_END=1528` / CLI-render phase.

Operational notes for a rollback:
- **Already-installed hosts are unaffected by a code revert** — the installed
  `/usr/local/bin/actools` is whatever was last installed. To return an installed
  host to the pre-P0-F CLI, re-run the installer's CLI step (or reinstall) after
  reverting.
- The six non-CLI generated files are byte-identical before and after P0-F, so a
  revert has **no effect** on `my.cnf`, the Dockerfiles, the `Caddyfile`, or
  `docker-compose.yml`, nor on container state.
- `ACTOOLS_HOME` in `/etc/environment` is written by both the old and new
  `setup_cli`, so no env-file fixup is needed on revert.
