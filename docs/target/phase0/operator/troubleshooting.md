# Troubleshooting

> **Status:** Phase 0 target contract — not yet released. This document describes intended
> behavior after Phase 0 seam hardening. It must not be treated as current released behavior
> until Phase 0 closure.

This document provides symptom-first troubleshooting for operators running the `community`
profile. Symptoms and fixes are identical before and after Phase 0 seam hardening unless
explicitly noted.

---

## Init problems

### "Unknown profile" error

```
FAIL  --profile  unknown profile 'foobar'
      Allowed profiles: community community-plus test
```

**Cause:** A `--profile` value was given that is not in the allowed list.

**Fix:** Omit `--profile` to use the default `community`, or use `--profile community`.
`community-plus` is a reserved name not yet implemented; `test` is for the bats test suite
only and must not be used on real deployments.

### "actools.env already exists" error

```
FAIL  actools.env  already exists at /home/actools/actools.env
Fix:  Re-run with --force to overwrite, or delete the file first.
```

**Cause:** `actools.env` already exists. `init` is safe-by-default and will not clobber it.

**Fix:** If this is a fresh provisioning and you want to overwrite: `sudo ./actools.sh init --force [flags]`. If Drupal is already installed, use `actools update` instead of re-running install.

### "actools.env.example missing" error

```
FAIL  actools.env.example  missing from repository
Fix:  Re-clone the repository — the template is required.
```

**Cause:** The template file was deleted or the clone is incomplete.

**Fix:** Re-clone the repository: `git clone https://github.com/actools-pl/actoolsDrupal`.

---

## Preflight failures

### FAIL: OS not Ubuntu

```
FAIL  OS  not Ubuntu — installer is Ubuntu 24.04 only
Fix:  Re-provision the VPS with Ubuntu 24.04.
```

**Cause:** The server is not running Ubuntu.

**Fix:** Provision a fresh Ubuntu 24.04 VPS. Ubuntu 22.04 is accepted with a warning; other distributions are not supported.

### FAIL: BASE_DOMAIN not set or placeholder

```
FAIL  BASE_DOMAIN  not set or still placeholder
Fix:  Edit /home/actools/actools.env or re-run init with --domain
```

**Cause:** `actools.env` was hand-edited or `init` was not run with `--domain`.

**Fix:** Re-run `sudo ./actools.sh init --domain example.com --email admin@example.com --force`.

### FAIL: RAM below minimum

```
FAIL  RAM  1400 MB — 2 GB minimum
Fix:  Resize the VPS to at least 2 GB.
```

**Fix:** Resize the VPS to at least 2 GB RAM. 4 GB is recommended for a production Drupal stack.

### FAIL: Disk below 20 GB

```
FAIL  Disk  12 GB free — 20 GB required
Fix:  Free space or resize the VPS.
```

**Fix:** Add storage or free space. 40 GB is recommended.

### WARN: Ports 80/443 in use

```
WARN  Ports  in use: 80 443 — another service will conflict with Caddy
Fix:  Stop the service holding those ports before installing.
```

**Cause:** Another web server (Apache, nginx, another Caddy) is listening on the HTTP/HTTPS ports.

**Fix:** Stop the conflicting service. Find it with: `sudo ss -lntp sport = :80 or sport = :443`.

### WARN: DNS not pointing to this server

```
WARN  DNS  example.com → 1.2.3.4 (this server is 5.6.7.8)
Fix:  Update the A record to 5.6.7.8 before TLS will issue.
```

**Cause:** The domain's A record does not point to this server. Caddy cannot obtain a TLS certificate without correct DNS.

**Fix:** Update the A record at your DNS provider. DNS propagation takes up to a few minutes for TTL-compliant resolvers. You can proceed with install (exit code `2` = warnings only), but HTTPS will not work until DNS is correct.

### WARN: Drupal already installed

```
WARN  Install state  Drupal already installed
Fix:  Use 'sudo ./actools.sh update' instead of install.
```

**Fix:** Use `actools update` for routine updates. Use `sudo ./actools.sh install` only for a fresh server.

---

## Install failures

### Docker build fails

```
[actools] ERROR: PHP image build failed
```

**Cause:** Docker image build failure, typically a network issue downloading base images or packages.

**Fix:** Check network connectivity. Inspect the Docker build log: `tail -50 ~/logs/install/actools-*.log`. Retry: `sudo ./actools.sh install` (idempotent — it skips completed stages).

### MariaDB does not become healthy

The installer waits for MariaDB to report healthy before proceeding to the `db` stage. If it times out, the installer errors out.

**Fix:** Check the MariaDB container logs: `docker compose logs db`. Common causes: insufficient RAM (MariaDB requires ~512 MB), disk full, or a port 3306 conflict. Resolve the underlying issue and re-run install.

### Drupal provision fails

```
[actools] ERROR: drush site-install failed for prod
```

**Fix:** Check the PHP container logs: `docker compose logs php_prod`. Common causes: database not ready, `BASE_DOMAIN` incorrect, network issue contacting Composer or Drupal.org. The install is idempotent; fix the cause and re-run.

### TLS certificate does not issue

The `tls_check` step at the end of install waits for Caddy to obtain a certificate.

**Cause:** DNS A record does not point to this server, port 443 is blocked by a firewall, or the domain is not accessible from the internet.

**Fix:** Verify DNS with `dig +short example.com`. Check port 443 is reachable from outside: `curl -I https://example.com`. Verify the firewall allows 80 and 443: `sudo ufw status`.

---

## Post-install CLI problems

### `actools: command not found`

**Cause:** `/usr/local/bin/actools` was not installed, or the `$PATH` does not include `/usr/local/bin`.

**Fix:**
- Verify install completed: `ls -la /usr/local/bin/actools`
- If missing: re-run `sudo ./actools.sh install` (it is idempotent)
- Check path: `echo $PATH | grep /usr/local/bin`

### `actools doctor` reports failures

Run `actools doctor` and address each `FAIL` line individually. Common failures:

| `doctor` FAIL | Likely cause | Fix |
|---|---|---|
| Site not responding | Container down | `docker compose ps`; `docker compose up -d` |
| TLS expired | Certificate renewal failed | Check Caddy logs: `docker compose logs caddy` |
| Container not running | OOM kill or crash | `actools oom`; `docker compose up -d` |
| DB not responding | MariaDB unhealthy | `docker compose restart db`; check disk space |
| Redis not responding | Redis crashed | `docker compose restart redis` |
| Disk critical | Low disk | Free space or expand volume |
| Backup old | Cron not running | `ls -la /etc/cron.daily/actools-backup`; `sudo run-parts /etc/cron.daily` |
| Restore-test old | Test not run | `actools restore-test` |

### `--profile` conflict error

```
ERROR: --profile='community-plus' conflicts with actools.env (ACTOOLS_PROFILE='community')
```

**Cause:** You passed `--profile` on the CLI and it disagrees with `ACTOOLS_PROFILE` in `actools.env`.

**Fix:** Profile selection is deployment-defining. Either edit `actools.env` to match, or remove the CLI `--profile` flag to use the pinned profile.

### `actools update` fails at drush updb

```
ERROR: drush updb failed for prod — update aborted before caddy reload
Pre-update snapshot retained at: /home/actools/backups/pre_update_prod_<timestamp>.sql.gz
Manual rollback: actools restore prod <snapshot>
```

**Cause:** A Drupal update failed (hook, schema migration, or connection issue).

**Fix:** Check the Drupal logs: `actools drush prod watchdog:show`. Restore from the pre-update snapshot if needed: `actools restore prod /home/actools/backups/pre_update_prod_<timestamp>.sql.gz`.

---

## Generated file problems

### Caddyfile changed unexpectedly

**Cause:** Re-running `actools.sh install` regenerates the `Caddyfile` from the heredoc template.

**Fix:** In Phase 0 target state, `Caddyfile` generation is behind the golden fixture harness (P0-C). Any unexpected change is caught by the CI golden diff. Hand-edits to the `Caddyfile` are overwritten on re-install — use `actools caddy-reload` after manual edits.

### `docker-compose.yml` shows wrong domain

**Cause:** `BASE_DOMAIN` in `actools.env` has a different value than when the compose file was generated.

**Fix:** If the domain has changed legitimately: update `actools.env`, then re-run `sudo ./actools.sh install` (idempotent). For TLS: allow Caddy to re-issue for the new domain.

### Empty `DB_ROOT_PASS` in docker-compose.yml

An empty root password would allow the database container to start unsecured. The
installer guards against this through a **generate-before-render** ordering: `gen_if_empty
DB_ROOT_PASS` runs before the `docker-compose.yml` heredoc is rendered. If `DB_ROOT_PASS`
is blank, it is auto-generated; if it contains the literal string `CHANGEME`, the installer
aborts with:

```
ERROR: DB_ROOT_PASS contains 'CHANGEME' -- set a real value.
```

There is no separate runtime refusal at render time — the protection is the secret-generation
ordering itself, which is a tested invariant (`[fix4]/[fix7]` scars in `actools.sh`).

**Cause:** You manually set `DB_ROOT_PASS=CHANGEME` in `actools.env` without replacing it.

**Fix:** Delete or blank the `DB_ROOT_PASS` line in `actools.env` (an empty value triggers
auto-generation). Never set it to the placeholder string. Re-run `sudo ./actools.sh install`
(idempotent).

---

## Profile-related problems

### Install behaves differently after profile change

Profile selection is deployment-defining. Changing `ACTOOLS_PROFILE` in `actools.env`
on an existing install and re-running install may produce inconsistent state.

**Fix:** If you need a different profile, provision a fresh server with the correct `--profile` at `init` time. Profile changes on live deployments are not supported in Phase 0.

### Profile file missing

**Phase 0 target (P0-E):** If `profiles/<name>.profile` does not exist, `init` fails
before writing `actools.env`. In the current D.0 codebase, `installer/profile.sh`
produces exit code `1` at install time (not at init time).

**Fix:** Use only `community` as the profile. `community-plus` is reserved but not yet
implemented; `test` is for the bats suite only.

---

## Logs and diagnostics

| Log | Location | Command |
|---|---|---|
| Install log | `~/logs/install/actools-<timestamp>.log` | `actools log-dir` |
| Main install log | `/home/actools/actools-install.log` | `tail -f /home/actools/actools-install.log` |
| Caddy logs | Container | `docker compose logs caddy` |
| PHP/Drupal logs | Container | `docker compose logs php_prod` |
| MariaDB logs | Container | `docker compose logs db` |
| Worker logs | Container | `actools worker-logs` |
| Drupal watchdog | Drush | `actools drush prod watchdog:show --count=50` |
| OOM events | Kernel | `actools oom` |

---

## Cross-references

- Install journey: [`install-community.md`](install-community.md)
- Commands reference: [`commands.md`](commands.md)
- Generated files: [`generated-files.md`](generated-files.md)
- Seam contract:
  [`docs/architecture/phase0-seam-contract.md`](../../architecture/phase0-seam-contract.md)
