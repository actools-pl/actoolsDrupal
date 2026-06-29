# Live-verification matrix

This is the **verification view** of the `actools` CLI: for every command, the
precondition to run it, its **class** (read-only / mutating / destructive /
interactive), a stable **output signature** a harness could assert on, its
**exit-code contract**, and whether CI actually exercises it today.

Every row is **derived by static reading of the dispatch arm bodies in
[`../cli/actools`](../cli/actools)** — the single source of truth. This document
does **not** run the commands; **live execution is V2** (the real-install command
harness). A row is therefore a *claim about the arm*, defensible against the arm
body, not an observed result. Where the arm delegates to a script (`doctor` →
`cli/commands/doctor.sh`, `audit` → `modules/audit/audit.sh`), the signature and
exit are read from that script.

For the **"what each command does"** narrative, see
[`command-reference.md`](command-reference.md) and
[`operator-handbook.md`](operator-handbook.md) — this matrix deliberately does not
duplicate that prose. For **file-level wiring** (which files are on the live path),
see the cross-reference at the end.

The command surface is **30 commands**: the 29 registered dispatch arms plus
`help` (the help/fallback arm, now treated as a first-class registered command by
the doc-claim guard).

---

## Class taxonomy

- **read-only** — inspects or reports; makes no persistent change to the database,
  filesystem state, or containers. A transient, self-cleaning test artifact (e.g.
  a temp object written and then deleted in the same run) still counts as
  read-only.
- **mutating** — changes state but is recoverable / non-destructive: container
  restarts, config reloads, additive writes, schema updates.
- **destructive** — can overwrite or delete existing data; irreversible without a
  backup.
- **interactive** — opens a session that waits for input; not safely auto-runnable
  by an unattended harness.

The **read-only** rows are the safe surface a harness can run unattended (subject
to the long-running note below). The **mutating** rows are recoverable but change
state. The **interactive** and **destructive** rows are *not* auto-runnable without
special handling (a TTY, or a confirmation/staging strategy).

> **Long-running read-only commands** (`logs`, `worker-logs`, `stats`) follow their
> stream (`-f` / `docker stats`) and do not return on their own. They are read-only
> but a harness must bound them with a timeout rather than awaiting natural exit.

---

## Command matrix

Exit contracts: where an arm has no explicit `exit`, it returns the status of its
last command (shown below as the default "0 success / non-zero on command
failure"). Arms with an explicit early `exit` are stated precisely.

### read-only (20)

| command | precondition | class | expected output (signature) | exit | CI-coverage |
|---|---|---|---|---|---|
| `doctor` | stack installed (containers up for a full pass) | read-only | `ACTOOLS DOCTOR` title + nine check lines (Site · TLS · Containers · Database · Redis · Disk · Backups · Restore test · Drupal) + a summary line | `0` all-pass · `2` warnings-only · `1` any failure | **e2e** (`e2e.yml` — `actools doctor`, `doctor --deep` gate) |
| `audit` | stack installed; `modules/audit/audit.sh` present | read-only | `=== ACTOOLS DRUPAL AUDIT ===` header + `[PASS]/[WARN]/[FAIL]/[CRITICAL]` lines + health-score report | `0` clean · `1` warn · `2` fail · `3` critical (CI mode; non-CI collapses warn→`0`) · `1` if the audit module is missing | **e2e** (`e2e.yml` — `actools audit ci`) |
| `status` | stack installed | read-only | `docker compose ps` table (per-container name / state / ports) | `0` success / non-zero on compose error | none (install-path only) |
| `logs [svc]` | containers up | read-only | streamed container log lines — **follows (`-f`); long-running** | `0` on clean exit (runs until interrupted) | none (install-path only) |
| `stats` | Docker daemon up | read-only | live `docker stats` table — **streaming; long-running** | `0` on clean exit (streams until interrupted) | none (install-path only) |
| `tls-status` | `BASE_DOMAIN` set; cert reachable on :443 | read-only | `=== TLS Certificate Status ===` + per-domain `notAfter` date or `not available yet` | `0` success | none (install-path only) |
| `worker-status` | `worker_prod` up | read-only | drush `queue:list` table | `0` success / non-zero on exec error | none (install-path only) |
| `worker-logs` | `worker_prod` up | read-only | streamed `worker_prod` logs — **follows (`-f`); long-running** | `0` on clean exit | none (install-path only) |
| `slow-log [env]` | `php_<env>` up | read-only | `=== PHP-FPM slow log for <env> ===` + last 50 lines or `No slow log yet` | `0` success | none (install-path only) |
| `redis-info` | `redis` up | read-only | `redis-cli info memory` block or `Redis not running` | `0` success | none (install-path only) |
| `storage-info` | `actools.env` present | read-only | `=== S3 Storage Configuration ===` + Provider / Bucket / Region·Endpoint + `XeLaTeX mode` | `0` success | none (install-path only) |
| `oom` | host `dmesg` readable | read-only | `=== Recent OOM Events ===` + matching `dmesg` lines or `No OOM events` | `0` success | none (install-path only) |
| `log-dir` | none | read-only | `=== Install Log Directory ===` + log path(s) or `No install logs found.` | `0` success | none (install-path only) |
| `dry-run` | none | read-only | `=== DRY-RUN: Steps actools update will take ===` + five **static** numbered steps (does **not** inspect current state) | `0` success | none (install-path only) |
| `restore-test` | stack up + a `backups/prod_db_*.sql.gz` + its `.sha256` | read-only | `Testing DB restore: <file>` … `Checksum OK` … `DB restore test OK -- <N> tables restored.` (creates **and drops** a transient `actools_restore_test` DB — never touches real data) | `0` success · `1` no-backup or checksum failure | none (install-path only) |
| `health` | `BASE_DOMAIN` set; site reachable | read-only | per-env `<domain>: HTTP=<code>  /health=<code>` — *legacy; prefer `doctor`* | `0` success | none (install-path only) |
| `migrate` | none | read-only | `=== XeLaTeX Migration Guide ===` + current mode + five guide steps — **prints the guide only; performs no migration** | `0` success | none (install-path only) |
| `pdf-test` | `worker_prod` up | read-only | `=== XeLaTeX Test ===` + `XeLaTeX: OK` / `FAILED` + container health (transient `xelatex --version` render) | `0` success | none (install-path only) |
| `storage-test` | `php_prod` up + S3 configured | read-only | `=== S3 Storage Round-Trip Test ===` + `WRITE OK` / `READ OK` / `DELETE OK` + `Round-trip: PASS` — **transient, self-cleaning** (writes then `unlink`s a test object) | `0` success | none (install-path only) |
| `help [advanced\|all]` | none | read-only | usage text — `Actools Drupal Community` + command groups (or the **Full Command Reference** for `advanced`/`all`) | `0` success | none (install-path only) |

### mutating (7)

| command | precondition | class | expected output (signature) | exit | CI-coverage |
|---|---|---|---|---|---|
| `backup` | stack up + `/etc/cron.daily/actools-backup` installed | mutating | runs the backup cron — writes a `*_db_*.sql.gz` artifact (+ checksum); additive | `0` success / non-zero on backup failure | none (install-path only) |
| `update` | stack up + `backup_user_pass` in `.actools-state.json` | mutating | `Taking pre-update prod snapshot...` … `Snapshot: <f>` … `Update complete.` (pull → `drush updb` → `cr` → caddy reload) | `0` success · `1` if `backup_user_pass` missing **or** `drush updb` fails (snapshot retained; prints `Manual rollback: actools restore prod <snap>`) | none (install-path only) |
| `restart [svc]` | stack installed | mutating | restarts container(s) via `docker compose restart` | `0` success / non-zero on compose error | none (install-path only) |
| `caddy-reload` | `actools_caddy` up | mutating | zero-downtime `caddy reload --config /etc/caddy/Caddyfile` | `0` success · non-zero if the reload fails | none (install-path only) |
| `tunnel [status\|restart\|logs]` | `cloudflared` service present | mutating | sub-dispatch — `status` → systemd status (read-only sub) · `restart` → `cloudflared restarted` (**mutates**) · `logs` → journalctl (read-only sub) · default → `Usage: actools tunnel [status\|restart\|logs]` | `0` success / non-zero on `systemctl` failure | none (install-path only) |
| `worker-run` | `worker_prod` up | mutating | `Running queue worker manually on prod...` + `drush queue:run actools_document_export` output — **consumes the queue** | `0` success / non-zero on exec error | none (install-path only) |
| `drush <env> <cmd…>` | `php_<env>` up | mutating *(worst-case; see note)* | passthrough of the drush subcommand's output | passthrough of the drush subcommand's exit | none (install-path only) |

### interactive (2)

| command | precondition | class | expected output (signature) | exit | CI-coverage |
|---|---|---|---|---|---|
| `console <env>` | `php_<env>` up | interactive | opens a `drush php:cli` REPL — **waits for input** | session exit code | none (install-path only) |
| `shell [svc]` | container up (defaults `php_prod`) | interactive | opens `bash` in the container — **waits for input** | session exit code | none (install-path only) |

### destructive (1)

| command | precondition | class | expected output (signature) | exit | CI-coverage |
|---|---|---|---|---|---|
| `restore <env> [file]` | stack up + a `backups/<env>_db_*.sql.gz` exists | **destructive** | `Restoring <env> from: <f>` → `OVERWRITE actools_<env>? [y/N]` (**defaults to abort**) → on `y`: `DROP DATABASE … CREATE DATABASE …` → `Restore complete. Run: actools drush <env> cr` (else `Aborted.` / `No backups found for <env>`) | `0` success-or-abort · `1` no-backup | none (install-path only) |

**Class notes (judgment calls, derived from the arms):**

- **`drush` — mutating (worst-case-bounded).** The arm is a thin passthrough to
  `drush` inside the container; its true class is **user-command-dependent**. The
  common case (`drush status`, `cr`, `updb`, config import) is read-only-to-mutating,
  but a destructive subcommand (e.g. `drush sql-drop`) reaches **destructive**. The
  row shows the arm's safest single defensible class for the everyday case;
  a harness must **not** auto-run an unknown `drush` subcommand.
- **`tunnel` — mutating (by worst case).** The sub-dispatch is mostly read-only
  (`status`, `logs`); only `restart` mutates (`sudo systemctl restart cloudflared`),
  so the command is classed by its worst-case sub-arm.
- **`storage-test`, `restore-test`, `pdf-test` — read-only.** Each produces a
  transient, self-cleaning artifact (an S3 object that is `unlink`ed; a temporary
  `actools_restore_test` DB that is dropped; a one-shot `xelatex --version`); per the
  taxonomy these remain read-only because no persistent state survives the run.

---

## CI-coverage summary

**2 of 30** commands are exercised live in CI today: `audit` (`actools audit ci`)
and `doctor` (`actools doctor`, plus the `doctor --deep` in-development gate), both
in `.github/workflows/e2e.yml`. The other **28** commands have **no** live CI
invocation — they are covered only transitively by the install path (the real-install
e2e builds the stack and installs the CLI, but never runs them).

Closing this gap is the explicit mandate of **V2** (the real-install command
harness): extend the e2e past the `audit`/`doctor` smoke to run the **read-only**
safe surface against the live VM. The **interactive** rows (`console`, `shell`) and
the **destructive** row (`restore`) are not auto-runnable without special handling
(a TTY, or a staging/confirmation strategy), and the long-running read-only commands
(`logs`, `worker-logs`, `stats`) need a timeout bound. V2 must keep the doc-claim
guard's observed behavior in agreement with this matrix.

---

## File-level wiring (cross-reference — not duplicated here)

Which *files* are on the live path is the authoritative subject of
[`architecture/runtime-authority-map.md`](architecture/runtime-authority-map.md).
That map records that the six live modules ship **35 files: 21 wired, 1
documentation, 13 unwired**, and that the registered command set is **derived live
by the doc-claim guard** from the `case "${1:-help}" in` dispatch in `cli/actools`
(deliberately not re-listed there, to avoid drift) — with the not-registered
allowlist held in the `CMD-ALLOWLIST` table. The `audit` arm sources
`modules/audit/audit.sh` (+ `lib/*.sh`); the `doctor` arm sources
`cli/commands/doctor.sh`. Consult that map for the file-by-file wiring behind any
row above; this matrix is the **command-level** verification view, V2 is the
**live-execution** layer, and the runtime-authority map is the **file-level**
wiring inventory.
