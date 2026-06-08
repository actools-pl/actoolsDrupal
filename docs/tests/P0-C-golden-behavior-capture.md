# P0-C Golden Behavior Capture — Test Report

> **Status:** Captured and active — all 5 variants passing drift test.
> Phase: P0-C — Golden Behavior Capture
> Produced by: Coding Window (Sonnet)
> Date: 2026-06-08

---

## Summary

This report documents the golden fixture capture performed in P0-C.  All
generated files (`docker-compose.yml`, `Caddyfile`, `my.cnf`, `Dockerfile.php`,
`Dockerfile.worker`, `Dockerfile.caddy`, `actools-cli`) have been captured as
byte-exact fixtures for the 5-variant environment matrix.  A drift-detecting
BATS test suite validates that any future change to generator logic fails visibly
before it can be merged.

---

## Capture method

The generators in `setup_stack()` (actools.sh:569-1028) and `setup_cli()`
(actools.sh:1247-1528) are heredoc-bearing functions interleaved with
privileged docker build / apt-get / chown calls.  Running a real install was
not possible in the capture sandbox.

**Isolation approach (Attempt 1 — succeeded):** `eval "$(sed -n 'X,Yp' actools.sh)"` 
extracts each function definition from the live source file at runtime (never
a static copy), then calls it in a subshell with bash function shims overriding
`docker`, `chown`, `section`, `log`, `warn`, `error`, and
`setup_backup_db_user`.  All variable-based conditionals in the heredocs (Redis
service, cAdvisor service, all-in-one Caddy blocks, S3 credentials) execute
correctly because the relevant env vars are exported before the call.

`setup_cli()` writes to `/usr/local/bin/actools` (hardcoded path).  Since the
capture runs as root, this write succeeds.  The pre-existing binary is
saved/restored around each call.  The `INSTALL_DIR` baked into the CLI fixture
is pinned to `/opt/actools-golden-test` (not a temp path) to make the sha256
deterministic across runs.

**Three-attempt rule:** Only Attempt 1 was needed.  No refactoring of
actools.sh was performed or required.

---

## Variant matrix captured

| Variant | ENABLE_REDIS | ENABLE_S3_STORAGE | ENABLE_CADVISOR | ENVIRONMENT_MODE | ENVIRONMENTS | Status |
|---|---|---|---|---|---|---|
| `default` | true | false | false | production-isolated | prod | ✓ captured |
| `redis-off` | false | false | false | production-isolated | prod | ✓ captured |
| `s3-on` | true | true | false | production-isolated | prod | ✓ captured |
| `cadvisor-on` | true | false | true | production-isolated | prod | ✓ captured |
| `all-in-one` | true | false | false | all-in-one | dev,stg,prod | ✓ captured |

All 5 planned variants were successfully captured.  No gaps.

### Branch coverage achieved

| Toggle | OFF branch | ON branch |
|---|---|---|
| `ENABLE_REDIS` | `redis-off` | `default`, `s3-on`, `cadvisor-on`, `all-in-one` |
| `ENABLE_S3_STORAGE` | `default`, `redis-off`, `cadvisor-on`, `all-in-one` | `s3-on` |
| `ENABLE_CADVISOR` | `default`, `redis-off`, `s3-on`, `all-in-one` | `cadvisor-on` |
| `ENVIRONMENT_MODE` (production-isolated) | `all-in-one` | `default`, `redis-off`, `s3-on`, `cadvisor-on` |
| `ENVIRONMENT_MODE` (all-in-one) | `default` et al. | `all-in-one` |

---

## Files captured per variant

Each variant directory under `tests/fixtures/golden/<variant>/` contains:

| File | Source generator | Notes |
|---|---|---|
| `my.cnf` | `setup_stack()` heredoc at actools.sh:595 | Identical across all variants (no toggle affects content) |
| `Dockerfile.caddy` | `setup_stack()` single-quoted heredoc at :607 | Identical across all variants |
| `Dockerfile.php` | `setup_stack()` heredoc at :624 | Generated from heredoc (repo's Dockerfile.php is the real-install authority; this captures the fallback generator) |
| `Dockerfile.worker` | `setup_stack()` heredoc at :634 | Identical across all variants |
| `Caddyfile` | `setup_stack()` heredoc at :663 | Differs for `all-in-one` (adds dev/stg vhost blocks) |
| `docker-compose.yml` | `setup_stack()` heredoc at :795 | Varies by all 4 toggles |
| `actools-cli` | `setup_cli()` HELPER heredoc at :1251 | Differs for `s3-on` (ENABLE_S3_STORAGE baked in) and `all-in-one` (ENVIRONMENTS baked in) |
| `SHA256SUMS` | Computed by capture helper | 7 entries per variant |

---

## Key observations captured in fixtures

1. **redis-off quirk:** When `ENABLE_REDIS=false`, the `redis:` service section
   is absent from `docker-compose.yml` but `php_prod` and `worker_prod` still
   carry `depends_on: redis: condition: service_started`.  This is the
   CURRENT generator behavior captured as-is.  P0-G will correct this; when
   it does, the fixture must be updated with an intentional-difference entry.

2. **Dockerfile.php fallback:** The repo ships `Dockerfile.php` at the repo
   root.  In a real install, `INSTALL_DIR` equals the repo root, so the
   heredoc at :624 is skipped (`if [[ ! -f "$INSTALL_DIR/Dockerfile.php" ]]`).
   The capture uses a temp `INSTALL_DIR` to force the heredoc to execute,
   capturing the generator logic.  P0-F/P0-G will unify this.

3. **CLI path baking:** `setup_cli()` bakes `INSTALL_DIR` and `ENVIRONMENTS`
   into the CLI script at generation time.  The fixtures use
   `INSTALL_DIR=/opt/actools-golden-test` and the variant's ENVIRONMENTS.
   Any change to how these are embedded will show as drift.

4. **Empty lines from conditionals:** `docker-compose.yml` contains blank lines
   where the conditional blocks (`$(if [...]; then ... fi)`) produce no output.
   These are part of the current generator output and are captured as-is.

---

## Test suite

**Location:** `tests/generated/golden_drift_test.bats`
**Test count:** 6 tests (5 variant drift tests + 1 meta test)

**Run:**
```bash
bats tests/generated/golden_drift_test.bats
```

**Expected output (green):**
```
1..6
ok 1 variant 'default' matches golden fixture (no drift)
ok 2 variant 'redis-off' matches golden fixture (no drift)
ok 3 variant 's3-on' matches golden fixture (no drift)
ok 4 variant 'cadvisor-on' matches golden fixture (no drift)
ok 5 variant 'all-in-one' matches golden fixture (no drift)
ok 6 fixture directory contains all 5 expected variants
```

### Acceptance rule

A phase that changes generation logic (P0-D, P0-G, etc.) MUST run this test
suite before merging.  The test passes only if:

**(a)** The re-rendered output matches the stored fixture sha256, **OR**

**(b)** The difference is documented in the **intentional-difference table**
below with a release note.  After documenting, update the fixture:
```bash
bash tests/helpers/capture_golden_outputs.sh <variant>
```

---

## Intentional-difference table

*(Currently empty — populated by later phases when they change generation logic)*

| File | Variant | Difference | Reason | Release note | Phase |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

---

## Limitations

- `Dockerfile.php`: captures the fallback heredoc generator, not the repo's
  tracked `Dockerfile.php`.  The repo copy is the real-install authority.
- No `ENVIRONMENTS` with multiple values for non-all-in-one variants (always
  `prod`).  Additional per-environment variants are out of P0-C scope.
- `S3_ENDPOINT_URL` and `ASSET_CDN_HOST` are always empty in the `s3-on`
  variant; Backblaze/Wasabi/custom endpoint branches are not separately
  captured.  Branch coverage for the provider enum is deferred to P0-G tests.
- `Dockerfile.caddy` uses a single-quoted heredoc (no variable expansion),
  so it is identical across all variants.  This is correct.

---

## Cross-references

- Golden capture helper: `tests/helpers/capture_golden_outputs.sh`
- BATS drift test: `tests/generated/golden_drift_test.bats`
- Fixtures: `tests/fixtures/golden/<variant>/`
- Generated-file contract: `docs/architecture/generated-file-contract.md`
- Operator reference: `docs/target/phase0/operator/generated-files.md`
- Ledger entry: `docs/runbooks/PHASE0_LEDGER.md` → Entry 008
