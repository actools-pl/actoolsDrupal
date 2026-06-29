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
| `audit` | stack installed; `modules/audit/audit.sh` present | read-only | **default mode** (`audit` / `audit ci`): `=== ACTOOLS DRUPAL AUDIT ===` banner + per-check `PASS`/`WARN`/`FAIL`/`CRITICAL` lines + health-score report. **CI mode** (`audit --ci`): banner **suppressed**, PASS lines suppressed, non-PASS as `STATUS [PRIORITY] msg [id]`, plus a machine summary line `PASS=N WARN=N FAIL=N CRITICAL=N` | **CI mode** (`--ci`): `0` clean · `1` warn · `2` fail · `3` critical · `1` if the audit module is missing. **Default mode** (`audit ci`, the existing gate): warn collapses to `0` (only fail→`2`/critical→`3`) | **e2e** (`e2e.yml`: the `audit ci` gate runs **default** mode [banner shown; `grep PASS≥10`]; Step C pins `audit --ci` **CI mode** [banner suppressed; `PASS=` summary]) |
| `status` | stack installed | read-only | `docker compose ps` table (per-container name / state / ports) | `0` success / non-zero on compose error | **e2e** (`e2e.yml` Step A — asserts `actools_`) |
| `logs [svc]` | containers up | read-only | streamed container log lines — **follows (`-f`); long-running** | `0` on clean exit (runs until interrupted) | **e2e** (`e2e.yml` Step B — timeout-bounded; exit `124`≡streaming) |
| `stats` | Docker daemon up | read-only | live `docker stats` table — **streaming; long-running** | `0` on clean exit (streams until interrupted) | **e2e** (`e2e.yml` Step B — timeout-bounded; asserts `CONTAINER`) |
| `tls-status` | `BASE_DOMAIN` set; cert reachable on :443 | read-only | `=== TLS Certificate Status ===` + per-domain `notAfter` date or `not available yet` | `0` success | **e2e** (`e2e.yml` Step A — asserts `TLS Certificate Status`; **tentative**: no-DNS env, branch e2e is arbiter) |
| `worker-status` | `worker_prod` up | read-only | drush `queue:list` table | `0` success / non-zero on exec error | **e2e** (`e2e.yml` Step A — asserts exit `0`; no stable cross-version drush token) |
| `worker-logs` | `worker_prod` up | read-only | streamed `worker_prod` logs — **follows (`-f`); long-running** | `0` on clean exit | **e2e** (`e2e.yml` Step B — timeout-bounded; exit `124`≡streaming) |
| `slow-log [env]` | `php_<env>` up | read-only | `=== PHP-FPM slow log for <env> ===` + last 50 lines or `No slow log yet` | `0` success | **e2e** (`e2e.yml` Step A — asserts `PHP-FPM slow log`) |
| `redis-info` | `redis` up | read-only | `redis-cli info memory` block or `Redis not running` | `0` success | **e2e** (`e2e.yml` Step A — asserts `used_memory`; redis up) |
| `storage-info` | `actools.env` present | read-only | `=== S3 Storage Configuration ===` + Provider / Bucket / Region·Endpoint + `XeLaTeX mode` | `0` success | **e2e** (`e2e.yml` Step A — asserts `S3 Storage Configuration`) |
| `oom` | host `dmesg` readable | read-only | `=== Recent OOM Events ===` + matching `dmesg` lines or `No OOM events` | `0` success | **e2e** (`e2e.yml` Step A — asserts `Recent OOM Events`; **tentative**: dmesg access, branch e2e is arbiter) |
| `log-dir` | none | read-only | `=== Install Log Directory ===` + log path(s) or `No install logs found.` | `0` success | **e2e** (`e2e.yml` Step A — asserts `Install Log Directory`) |
| `dry-run` | none | read-only | `=== DRY-RUN: Steps actools update will take ===` + five **static** numbered steps (does **not** inspect current state) | `0` success | **e2e** (`e2e.yml` Step A — asserts `DRY-RUN`) |
| `restore-test` | stack up + a `backups/prod_db_*.sql.gz` + its `.sha256` | read-only | `Testing DB restore: <file>` … `Checksum OK` … `DB restore test OK -- <N> tables restored.` (creates **and drops** a transient `actools_restore_test` DB — never touches real data) | `0` success · `1` no-backup or checksum failure | none — **skipped** (fresh install has no backup; `doctor` Restore-test check covers it) |
| `health` | `BASE_DOMAIN` set; site reachable | read-only | per-env `<domain>: HTTP=<code>  /health=<code>` — *legacy; prefer `doctor`* | `0` success | none — **skipped** (external HTTPS to the fake domain is unreliable; `doctor` Site check covers the local path) |
| `migrate` | none | read-only | `=== XeLaTeX Migration Guide ===` + current mode + five guide steps — **prints the guide only; performs no migration** | `0` success | **e2e** (`e2e.yml` Step A — asserts `XeLaTeX Migration Guide`) |
| `pdf-test` | `worker_prod` up | read-only | `=== XeLaTeX Test ===` + `XeLaTeX: OK` / `FAILED` + container health (transient `xelatex --version` render) | `0` success | **e2e** (`e2e.yml` Step A — asserts `XeLaTeX Test`) |
| `storage-test` | `php_prod` up + S3 configured | read-only | `=== S3 Storage Round-Trip Test ===` + `WRITE OK` / `READ OK` / `DELETE OK` + `Round-trip: PASS` — **transient, self-cleaning** (writes then `unlink`s a test object) | `0` success | none — **skipped** (`ENABLE_S3_STORAGE=false`; round-trip needs a bucket) |
| `help [advanced\|all]` | none | read-only | usage text — `Actools Drupal Community` + command groups (or the **Full Command Reference** for `advanced`/`all`) | `0` success | **e2e** (`e2e.yml` Step A — asserts `Actools Drupal Community`) |

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
- **`audit ci` ≠ `audit --ci` (parser finding, V1 doc-check; pinned by V2 Step C).**
  `audit.sh` selects CI mode only on the flag `--ci`; the bare word `ci` matches
  **none** of its cases (`--complete`/`--security`/`--json`/`--ci`/`--deep`/
  `--security-active`), so `actools audit ci` — the invocation the existing e2e gate
  and cron use — runs in **default** mode (banner shown; the gate's `grep PASS≥10`
  counts the default-mode `PASS` lines, so it is sound). The dedicated CI-mode path
  is `actools audit --ci`: banner suppressed, PASS lines suppressed, and a single
  `PASS=N WARN=N FAIL=N CRITICAL=N` machine summary emitted (`lib/report.sh`). V2
  **records and pins** this distinction (e2e Step C asserts banner-absent + `PASS=`);
  it does **not** re-wire the gate — changing the gate's invocation is a separate,
  deliberate decision.

---

## CI-coverage summary

**17 of 30** commands are exercised live in CI after **V2** (the real-install
command harness in `.github/workflows/e2e.yml`):

- **doctor, audit** — the pre-existing smoke (`actools doctor` + `doctor --deep`
  gate; `actools audit ci`). V2 additively pins `audit --ci` CI mode (Step C).
- **Step A — deterministic read-only (10):** `status`, `log-dir`, `dry-run`,
  `migrate`, `help`, `storage-info`, `redis-info`, `slow-log`, `pdf-test`
  (each asserts a stable header/token), and `worker-status` (asserts exit `0` —
  no stable cross-version drush token).
- **Step A — tentative (2):** `tls-status`, `oom` — their headers are emitted
  before the degrading lookup, so they are expected green in the no-DNS env, but
  the **branch e2e is the arbiter**; if either hard-fails it is demoted to the
  skip list as a declared deviation (and its row flips back to *none*).
- **Step B — streaming (3):** `logs`, `stats`, `worker-logs` — long-running, so
  bounded by a remote `timeout`; exit `124` (timeout fired) ≡ clean stream.

The remaining **13** commands are **not** harnessed, by class:

- **mutating (7)** — `backup`, `update`, `restart`, `caddy-reload`, `tunnel`,
  `worker-run`, `drush` — a fresh-install e2e must stay re-runnable and unattended.
  (`tunnel` is **also** unmet on the external-dependency axis — no Cloudflare in CI —
  but its class is mutating: the `restart` sub-arm runs `systemctl restart cloudflared`.)
- **interactive (2)** — `console`, `shell` — would hang an unattended runner.
- **destructive (1)** — `restore` — overwrites a database.
- **read-only with an external dependency unmet in CI (3)** — `storage-test`
  (no S3 bucket; `ENABLE_S3_STORAGE=false`), `health` (external HTTPS to the fake
  domain; `doctor` covers the local path), `restore-test` (a fresh install has no
  backup; `doctor` covers it).

These omissions are encoded as a comment block in the harness so they are
intentional, not forgotten. V2 keeps the doc-claim guard's observed behavior in
agreement with this matrix (all command references here stay inline `code`, so the
guard extracts 0 fenced invocations from this file).

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
