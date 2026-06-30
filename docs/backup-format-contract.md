# Backup-format contract

> Applies to: Actools v11.2.0+ · Drupal 11 · MariaDB 11.4
> Status of this document: the **live (A)** format below is the current, in-effect
> contract, pinned by a guard (see "What the guard enforces"). The **encrypted (B)**
> and **PITR (C)** clauses are the **target** that the draft scripts in
> `modules/backup/` are *not yet wired to*; they are marked **TARGET / NOT YET LIVE**
> throughout and describe what E2 and E3 must build, not shipped behavior.

---

## Why this document exists

`modules/backup/` carries the live daily backup generator (`cron.sh`) alongside a
ten-file draft cluster for encrypted backups and point-in-time recovery
(`encrypted_backup.sh`, `db-full-backup.sh`, `pitr-restore.sh`, and their
supporting `.cnf`/compose/cron files). Across the live code and those drafts there
are three different ways a backup artifact gets named, located, time-stamped,
encrypted, and checksummed. Left unreconciled, wiring the encrypted backup (E2) and
the binlog/PITR path (E3) would cement three incompatible dialects into production.

This contract fixes one canonical artifact shape, pins the live producer-and-consumer
agreement so it cannot silently drift, and records exactly where each draft diverges
and what its E-phase must do to conform. It changes no behavior: it does not touch the
live cron, it does not wire the drafts, and it introduces no new feature. It is a
reference document plus a guard.

The three dialects, in brief:

- **Live (A)** — the daily cron in `modules/backup/cron.sh`, consumed by the `backup`
  and `restore` arms of `cli/actools`. Plaintext, gzipped, daily timestamp, flat
  directory. This is what ships today.
- **Encrypted (B)** — `modules/backup/encrypted_backup.sh`. The same filename stem and
  location as A, plus an Age-encrypted `.age` layer and a per-second timestamp. A draft;
  E2 wires it.
- **PITR (C)** — `modules/backup/db-full-backup.sh` and `pitr-restore.sh`, with
  `binlog-rotate.sh`. A nested directory layout under `backups/db/<date>/`, a separate
  binlog archive, and a base dump taken with `--master-data=2` to embed the binlog
  coordinate. Drafts; E3 wires them.

The encryption key infrastructure is already live and idle: `modules/host/age.sh`
generates a per-deployment Age keypair at install (`.age-key.txt`, mode 600; the
derived `.age-public-key`, mode 644), so the key material the encrypted and PITR
variants need already exists — it is simply not consumed yet. No `ENABLE_PITR` or
`ENABLE_BINLOG` flag exists in the tree; E3 introduces one.

---

## The live format (A), pinned exactly

This section transcribes the format the installer ships today, from
`modules/backup/cron.sh` (the generator of `/etc/cron.daily/actools-backup`) and the
`restore` arm at `cli/actools:241`. It is the current contract.

Root directory. All standard artifacts live directly under `${INSTALL_DIR}/backups/`
(the generator sets `BACKUP_DIR="$INSTALL_DIR/backups"`). The layout is flat — no
per-date subdirectories.

Database dump. For each environment the daily cron writes:

```
${INSTALL_DIR}/backups/<env>_db_<YYYY-MM-DD>.sql.gz
```

Its content is `gzip(mariadb-dump --single-transaction --quick actools_<env>)`. Each
dump is paired with a checksum sidecar named `<dump>.sha256`, written with
`sha256sum "<dump>" > "<dump>.sha256"` and verified immediately with `sha256sum -c`.

Files archive (only when S3 is off). When `ENABLE_S3_STORAGE` is not `true`, the cron
archives the site's files directory
(`${INSTALL_DIR}/docroot/<env>/web/sites/default/files`) as:

```
${INSTALL_DIR}/backups/<env>_files_<YYYY-MM-DD>.tar.gz
```

with its own `<archive>.sha256` sidecar and the same integrity check. When S3 *is* on,
files are not archived locally; instead the cron runs a Drupal `s3fs:refresh-cache`
reachability check and logs whether the bucket is reachable.

Timestamp granularity. The timestamp is `date +%F`, i.e. a calendar day
(`YYYY-MM-DD`). A known and intentional consequence: a second backup run on the same
calendar day overwrites that day's artifact, because the filename has no finer
component. The standard backup therefore provides one restore point per day; finer
recovery granularity is the job of point-in-time recovery (see the PITR target below),
not the daily cron. E1 only records this property; it does not change it.

Integrity-or-delete. A dump or archive that fails its `sha256sum -c` is deleted along
with its sidecar. The invariant that follows is relied on by consumers: if an artifact
is present on disk, it passed its integrity check at creation time.

Retention. Artifacts older than `BACKUP_RETENTION_DAYS` (default `7`) are pruned by the
same daily cron, which deletes aged `*.sql.gz`, `*.sql.gz.sha256`, `*.tar.gz`, and
`*.tar.gz.sha256` files.

Off-host copy. When `RCLONE_REMOTE` is set and `rclone` is available, the cron copies
`*.sql.gz` and `*.tar.gz` artifacts to the remote.

Security shape. The MariaDB password is never placed on the command line. At cron
runtime the password is read from `${INSTALL_DIR}/.actools-state.json`
(`jq -r '.backup_user_pass // empty'`) and written, together with `[mariadb-dump]` and
`user=backup`, into a `umask 077` temporary file created *inside* the `actools_db`
container; `mariadb-dump --defaults-extra-file="<tmpfile>"` then reads the credential
from that file. The password is therefore never visible to `ps` and no secret is baked
into the generated script. This shape is locked by
`tests/guards/cron_security_shape_guard_test.bats`. **Every backup producer — standard,
encrypted, and PITR — must use this shape.**

Consumer (restore). The `restore` arm of `cli/actools` (`cli/actools:241`), when given
no explicit file, selects the most recent default backup with the glob:

```
ls -t "${INSTALL_DIR}/backups"/"<env>"_db_*.sql.gz | head -1
```

It then verifies the artifact with `sha256sum -c "<file>.sha256"` before decompressing
and loading it. Producer and consumer thus agree on the same root
(`${INSTALL_DIR}/backups`), the same filename stem (`_db_`), the same extension
(`.sql.gz`), and the same checksum-sidecar convention (`<artifact>.sha256`). That
agreement — that the producer and the consumer name the same artifact — is the core
invariant the §guard pins.

---

## The canonical scheme (X)

X is the single shape all producers and consumers conform to. The live format (A)
already conforms; the encrypted (B) and PITR (C) variants conform to X once their
E-phase wires them.

Naming grammar.

```
<env>_<kind>_<timestamp>.<ext>[.age][.sha256]
```

where `<kind>` is `db` or `files` for the standard and encrypted backups; `<ext>` is
`sql.gz` for a database dump and `tar.gz` for a files archive; and `<timestamp>` is
`YYYY-MM-DD` for the daily standard cron and `YYYY-MM-DD_HHMMSS` for encrypted, PITR,
and ad-hoc producers. The finer granularity exists so that multiple backups on the same
day never clobber one another. Because both granularities are valid, a consumer glob
must match both — for example `"<env>"_db_*.sql.gz` matches `prod_db_2026-06-29.sql.gz`
and `prod_db_2026-06-29_140322.sql.gz` alike.

Encryption (Age). An encrypted artifact appends `.age` to the otherwise-identical name
(`<env>_db_<timestamp>.sql.gz.age`). The recipient is the contents of
`${INSTALL_DIR}/.age-public-key`; the private key used to decrypt is
`${INSTALL_DIR}/.age-key.txt` (mode 600); both come from `modules/host/age.sh`. The
`.sha256` sidecar is computed over the **ciphertext** — the final `.age` bytes — so
integrity can be verified without the private key. A consumer must detect a `.age`
suffix and decrypt before decompressing.

PITR layout. Point-in-time recovery uses a nested layout rooted under the same
`${INSTALL_DIR}/backups/` tree:

```
${INSTALL_DIR}/backups/db/<YYYY-MM-DD>/full-dump-<HHMMSS>.sql.gz[.age]   (+ manifest.txt, + .sha256)
${INSTALL_DIR}/backups/binlogs/mysql-bin.<NNNNNN>.gz[.age]               (+ .sha256)
```

The base dump is taken with `--master-data=2`, which embeds the binlog file and
position the dump corresponds to; binlog replay starts from that coordinate. The PITR
tree is rooted **under** `${INSTALL_DIR}/backups/`, which reconciles the drafts' use of
`${ACTOOLS_HOME}/backups/...` (the two are equal when `INSTALL_DIR=/home/actools`). The
whole PITR path is gated by a future `ENABLE_PITR` flag that E3 introduces.

Checksum and integrity. Every artifact — plaintext or encrypted, standard or PITR —
carries a verified `.sha256` sidecar computed over its **final** bytes (the ciphertext
when the artifact is encrypted). A failed integrity check deletes the artifact together
with its sidecar, so presence on disk implies integrity at creation.

Retention. The standard and encrypted backups use `BACKUP_RETENTION_DAYS` (default
`7`). PITR base dumps and binlogs get their own retention window, which E3 defines; the
binlog chain must reach back at least to the oldest retained base dump, or PITR cannot
replay from that dump forward.

Security shape. Every producer reads the DB password from
`${INSTALL_DIR}/.actools-state.json` at runtime and feeds it to the dump client through
a `umask 077` `--defaults-extra-file` inside the DB container, exactly as the live cron
does. No producer may place a password on argv. This is the same shape pinned by
`tests/guards/cron_security_shape_guard_test.bats`.

---

## Divergence ledger and conformance actions

For each dialect: where it stands relative to X, and what its E-phase must do.

### A — live daily cron — CONFORMS (pinned; no change)

A already matches X: daily `db`/`files` artifacts under a flat `${INSTALL_DIR}/backups/`,
each with a verified `.sha256`, produced with the secure `--defaults-extra-file`
password shape, and consumed by a `restore` glob that names the same artifact. E1 pins
this agreement with the guard and changes nothing.

### B — `encrypted_backup.sh` → E2 — TARGET / NOT YET LIVE

What B already gets right: the DB dump stem and location match A
(`${INSTALL_DIR}/backups/<env>_db_<timestamp>.sql.gz`); it appends `.age` and writes the
`.sha256` over the ciphertext (`<name>.sql.gz.age` with `<name>.sql.gz.age.sha256`); it
recovers the recipient from `${INSTALL_DIR}/.age-public-key`; and it removes the
plaintext dump after encrypting. Its per-second timestamp differs from A's daily
timestamp, but that difference is *allowed* by X's grammar and absorbed by the
matching glob, so it is not a divergence.

Where B diverges from X, and what E2 must do:

- **Password shape.** B's draft dumps with `mariadb-dump -uroot -p"${DB_ROOT_PASS}"` —
  the password on argv, as root. This is the insecure form that
  `cron_security_shape_guard_test.bats` forbids. E2 must convert B to the secure
  `umask 077` `--defaults-extra-file` shape inside the DB container, reading the
  password from `.actools-state.json` at runtime, matching A.
- **Consumer does not yet understand `.age`.** The live `restore` arm decompresses with
  `gunzip` and has no `.age` branch, so it cannot consume B's output. E2 must extend the
  `restore` consumer to detect a `.age` suffix and decrypt (with the private key at
  `${INSTALL_DIR}/.age-key.txt`) before decompressing. The `<name>.sql.gz.age` filename
  and the ciphertext `.sha256` sidecar are canonical and must be preserved.

E2 extends the guard to pin B's producer-and-consumer agreement once B is wired.

### C — `db-full-backup.sh` / `pitr-restore.sh` (with `binlog-rotate.sh`) → E3 — TARGET / NOT YET LIVE

What C already gets right: the nested `backups/db/<YYYY-MM-DD>/full-dump-<HHMMSS>.sql.gz.age`
layout with a `manifest.txt` and a per-artifact `.sha256`; the binlog archive
`backups/binlogs/mysql-bin.<NNNNNN>.gz.age` with its `.sha256` over the ciphertext; the
base dump taken with `--master-data=2`; and a restore path that reads the manifest,
decrypts with the private key, and replays binlogs from the embedded coordinate.

Where C diverges from X, and what E3 must do:

- **Root variable.** C's drafts root their tree at `${ACTOOLS_HOME}/backups/...` rather
  than `${INSTALL_DIR}/backups/...`. The two resolve to the same path when
  `INSTALL_DIR=/home/actools`, but E3 must root the PITR tree under
  `${INSTALL_DIR}/backups/db/` and `${INSTALL_DIR}/backups/binlogs/` per X so the
  variable, not the default, is authoritative.
- **Password shape.** C's drafts dump and replay with `--user=root --password="${DB_ROOT_PASS}"`
  on argv. E3 must use the secure `--defaults-extra-file` shape, matching A.
- **Gating.** PITR must be opt-in. E3 introduces the `ENABLE_PITR` flag and the binlog
  generation it depends on (the `my.cnf`/compose changes), and defines the PITR
  retention window described under X.

C keeps its nested layout, `manifest.txt`, per-artifact `.sha256`, and `--master-data=2`
base dump unchanged. E3 extends the guard to pin C once C is wired.

---

## What the guard enforces now vs later

`tests/guards/backup_format_contract_guard_test.bats` pins **only the live (A)
agreement** at this baseline. Concretely it renders the live cron through the existing
`tests/helpers/capture_backup_cron.sh` helper and asserts: the producer writes
`<env>_db_<…>.sql.gz` under a `…/backups/` path; the producer writes a `<dump>.sha256`
sidecar and runs `sha256sum -c`; the `restore` consumer's default glob shares the
producer's stem (`_db_`), extension (`.sql.gz`), and `${INSTALL_DIR}/backups` root; and
the consumer reads the same `<file>.sha256` sidecar convention. Two non-vacuity arms
prove the guard bites: doctoring the producer's filename stem, or doctoring the restore
glob, each makes the agreement assertion fail.

The guard does **not** assert anything about the encrypted (B) or PITR (C) variants.
Those clauses of this document are the **target** the drafts are not yet wired to. E2
extends the guard to pin B's agreement when E2 wires encrypted backups, and E3 extends
it to pin C's agreement when E3 wires binlog/PITR. Until then, treat every B and C
statement here as a specification of intended behavior, not a description of shipped
behavior.
