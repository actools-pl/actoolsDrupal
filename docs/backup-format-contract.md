# Backup-format contract

> Applies to: Actools v11.2.0+ · Drupal 11 · MariaDB 11.4
> Status of this document: the **live (A)** format below is the current, in-effect
> contract, pinned by a guard (see "What the guard enforces"). The **encrypted (B)**
> variant is now **LIVE** — wired into the daily cron (`modules/backup/cron.sh`) and
> gated by `ENABLE_ENCRYPTED_BACKUP` (**default off**, so enabling it is opt-in) — and
> is pinned by the same guard. The **PITR (C)** path is now **partially live**: binary
> logging — the binlog *foundation* — is **LIVE** as of E3a, gated by `ENABLE_PITR`
> (**default off**), via the standalone `99-binlog.cnf` config and the dedicated
> `mariadb_binlogs` volume folded into the canonical compose db service. The C
> **full-backup producer and the PITR restore remain TARGET / NOT YET LIVE** (E3b / E5);
> the remaining draft scripts in `modules/backup/` are *not yet wired to* them, and
> those clauses describe what the later E3 phases must build, not shipped behavior.

---

## Why this document exists

`modules/backup/` carries the live daily backup generator (`cron.sh`) — which now
performs Age encryption at rest behind the `ENABLE_ENCRYPTED_BACKUP` flag (E2) —
alongside a six-file draft cluster for point-in-time recovery (`db-full-backup.sh`,
`pitr-restore.sh`, `binlog-rotate.sh`, `cli-pitr.sh`, `deploy-pitr.sh`, and the
`actools-db-backup.cron` schedule). Across the live code and those drafts there are
three different ways a backup artifact gets named, located, time-stamped, encrypted,
and checksummed. Left unreconciled, the encrypted backup (E2) and the binlog/PITR path
(E3) would each cement an incompatible dialect into production; this contract is the
single shape they conform to. E2 is now live and conforms; E3's binlog foundation is
now live (gated `ENABLE_PITR`, default off) and the remaining PITR producer/restore
stay drafts.

This contract fixes one canonical artifact shape, pins the live producer-and-consumer
agreement so it cannot silently drift, and records exactly where each draft diverges
and what its E-phase must do to conform. It changes no behavior: it does not touch the
live cron, it does not wire the drafts, and it introduces no new feature. It is a
reference document plus a guard.

The three dialects, in brief:

- **Live (A)** — the daily cron in `modules/backup/cron.sh`, consumed by the `backup`
  and `restore` arms of `cli/actools`. Plaintext, gzipped, daily timestamp, flat
  directory. This is what ships today.
- **Encrypted (B)** — now part of `modules/backup/cron.sh`, gated by
  `ENABLE_ENCRYPTED_BACKUP` (default off). The same filename stem, location, and
  **daily** timestamp as A, plus an Age-encrypted `.age` layer over the gzip. Live as
  of E2; consumed by the same `restore` arm, which detects `.age` and decrypts.
- **PITR (C)** — `modules/backup/db-full-backup.sh` and `pitr-restore.sh`, with
  `binlog-rotate.sh`. A nested directory layout under `backups/db/<date>/`, a separate
  binlog archive, and a base dump taken with `--master-data=2` to embed the binlog
  coordinate. The binlog *foundation* (binary logging via `99-binlog.cnf` + the
  `mariadb_binlogs` volume, gated `ENABLE_PITR`, default off) is **live as of E3a**; the
  full-backup producer and restore remain drafts (E3b / E5).

The encryption key infrastructure is already live: `modules/host/age.sh`
generates a per-deployment Age keypair at install (`.age-key.txt`, mode 600; the
derived `.age-public-key`, mode 644). The encrypted variant (B) now consumes that key
material on the live path (gated by `ENABLE_ENCRYPTED_BACKUP`); the PITR full-backup
producer (C) does not consume it yet. The `ENABLE_PITR` flag now exists in the tree
(introduced by E3a, **default off**); it currently gates binary logging only — the
full-backup producer and restore that will also consume it remain drafts.

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
`YYYY-MM-DD` for the daily standard cron (including its gated encrypted variant, B) and
`YYYY-MM-DD_HHMMSS` for PITR and ad-hoc producers. The finer granularity exists so that
multiple backups on the same day never clobber one another. Because both granularities
are valid, a consumer glob must match both — for example `"<env>"_db_*.sql.gz` matches
`prod_db_2026-06-29.sql.gz` and `prod_db_2026-06-29_140322.sql.gz` alike.

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
whole PITR path is gated by the `ENABLE_PITR` flag (introduced by E3a, **default off**);
E3a's binary logging consumes it now, and the full-backup producer and restore conform
to the same gate as they land (E3b / E5).

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

### B — encrypted daily backup in `cron.sh` (gated by `ENABLE_ENCRYPTED_BACKUP`) — LIVE (E2)

B is the daily DB dump and (S3-off) files archive, Age-encrypted at rest. It is produced
by `modules/backup/cron.sh` itself — the standalone `encrypted_backup.sh` draft was
absorbed and removed — and is gated by `ENABLE_ENCRYPTED_BACKUP` (default off, threaded
into the render exactly as `ENABLE_S3_STORAGE` is). When the flag is off the cron behaves
exactly as A; when on, an encryption stage runs after each artifact's dump + checksum +
integrity check.

What B does (shipped):

- **Naming and timestamp.** The encrypted artifact is `<env>_db_<YYYY-MM-DD>.sql.gz.age`
  (and `<env>_files_<YYYY-MM-DD>.tar.gz.age` for the files archive) — the **daily**
  timestamp, identical to A's, with `.age` appended. Per-second timestamps remain the
  PITR/ad-hoc case (C), not this daily cron.
- **Encryption.** `age -r "$(cat ${INSTALL_DIR}/.age-public-key)" -o "<artifact>.age" "<artifact>"`
  — the recipient is the public key from `modules/host/age.sh`. The matching private key
  for decryption is `${INSTALL_DIR}/.age-key.txt` (mode 600).
- **Checksum over ciphertext.** The sidecar is `sha256sum "<artifact>.age" > "<artifact>.age.sha256"`,
  computed over the **ciphertext**, then verified — so integrity is checkable without the
  private key, per X.
- **Plaintext removal / integrity-or-delete.** On a successful encrypt+verify the plaintext
  artifact and its `.sha256` are removed, leaving only the `.age` + `.age.sha256`. If the
  encrypt or its checksum fails, the partial `.age`/`.age.sha256` are deleted, so a failed
  encrypted backup leaves no encrypted artifact (the integrity-or-delete invariant).
- **Secure password shape — by construction.** The DB dump is unchanged: it remains the
  in-container `mariadb-dump --defaults-extra-file=<umask-077 temp>` form, reading the
  password from `.actools-state.json` at runtime. Encryption is a post-dump host-side step
  that touches no credential, so the draft's old argv-password flaw
  (`encrypted_backup.sh:30`, `-p"${DB_ROOT_PASS}"`) never shipped — it was fixed by
  construction, not ported. No password appears on argv in either the encryption-on or
  encryption-off rendering.
- **Retention and off-host copy.** The prune globs also delete aged `*.sql.gz.age`,
  `*.sql.gz.age.sha256`, `*.tar.gz.age`, and `*.tar.gz.age.sha256`; the rclone `--include`
  set also pushes `*.age` and `*.age.sha256`. Encrypted artifacts are retained and
  off-hosted exactly like plaintext.
- **Consumer.** The `restore` arm of `cli/actools` selects the newest of
  `<env>_db_*.sql.gz` or `<env>_db_*.sql.gz.age`; if the selected file ends in `.age` it
  requires `${INSTALL_DIR}/.age-key.txt` and decrypts with
  `age --decrypt -i "${INSTALL_DIR}/.age-key.txt"` before `gunzip | mariadb`. A
  present-but-failing `<file>.sha256` now **aborts** before any `DROP DATABASE` (a missing
  sidecar still only warns). Off-host, an operator decrypts a `.age` artifact manually with
  `age --decrypt -i ~/.age-key.txt <file>.age`.

The guard (`backup_format_contract_guard_test.bats`) now pins B's producer-and-consumer
agreement: it renders `cron.sh` with `ENABLE_ENCRYPTED_BACKUP=true` and asserts the `.age`
artifact, the ciphertext checksum, and the plaintext removal on the producer side, and the
`.age`-detecting decrypt path on the consumer side, with new non-vacuity arms.

### C — `db-full-backup.sh` / `pitr-restore.sh` (with `binlog-rotate.sh`) → E3b / E3c / E5 — TARGET / NOT YET LIVE

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
- **Gating.** PITR must be opt-in. E3a introduced the `ENABLE_PITR` flag (default off)
  and the binlog generation it depends on (the gated `compose.sh` volume/config wiring
  plus the standalone `99-binlog.cnf` the installer places); the remaining E3 phases gate
  the full-backup producer and restore behind the same flag and define the PITR retention
  window described under X.

C keeps its nested layout, `manifest.txt`, per-artifact `.sha256`, and `--master-data=2`
base dump unchanged. The binlog foundation is already pinned by
`tests/guards/binlog_enablement_guard_test.bats` (E3a); the later E3 phases extend the
contract guard to pin the C producer/restore once they are wired.

---

## What the guard enforces now vs later

`tests/guards/backup_format_contract_guard_test.bats` pins both the live (A) agreement
and the now-live encrypted (B) agreement. For A it renders the live cron through the
existing `tests/helpers/capture_backup_cron.sh` helper and asserts: the producer writes
`<env>_db_<…>.sql.gz` under a `…/backups/` path; the producer writes a `<dump>.sha256`
sidecar and runs `sha256sum -c`; the `restore` consumer's default glob shares the
producer's stem (`_db_`), extension (`.sql.gz`), and `${INSTALL_DIR}/backups` root (the
root assertion is anchored to the closing quote, so a `backups`-prefixed sibling does not
pass); and the consumer reads the same `<file>.sha256` sidecar convention. For B it
renders the cron with `ENABLE_ENCRYPTED_BACKUP=true` and asserts the producer emits
`<env>_db_<…>.sql.gz.age`, checksums the **ciphertext** (`<dump>.sql.gz.age.sha256`), and
removes the plaintext; and that the `restore` consumer selects `*.sql.gz.age` and decrypts
with the private key before load. Several non-vacuity arms prove the guard bites:
doctoring the producer's filename stem, doctoring the restore glob, rooting the consumer
glob at a `backups`-prefixed sibling, and checksumming the plaintext instead of the
ciphertext each make the relevant assertion fail.

The contract guard now asserts A and B. It does **not** yet assert the PITR (C)
producer/restore artifact shapes: those clauses remain the **target** the C drafts are
not yet wired to, and the later E3 phases extend this guard to pin C's agreement once
they wire the producer/restore. The binlog *foundation* of C, by contrast, is shipped
(gated `ENABLE_PITR`, **default off**) and is pinned separately by
`tests/guards/binlog_enablement_guard_test.bats`. Until the producer/restore land, treat
the C **producer/restore** statements here as a specification of intended behavior, not a
description of shipped behavior; A, B, and the C binlog foundation describe shipped
behavior.
