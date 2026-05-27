# Quick start

Install Drupal 11 on a fresh Ubuntu 24.04 VPS in five staged commands.

> **Before you start:** point a DNS A record for your domain to the server's IP. Caddy cannot issue TLS certificates until DNS resolves. You can run `preflight` before DNS propagates — it will warn, not block — but `install` will leave the site on HTTP until the A record is live.

---

## Step 1 — Provision the server

Any Ubuntu 24.04 VPS with 2 GB RAM, 20 GB disk, and a sudo user. A Hetzner CAX21 (4 vCPU ARM, 8 GB RAM, ~€8.49/month) or CPX21 (3 vCPU AMD, 4 GB RAM, ~€12.49/month) gives comfortable headroom for XeLaTeX or Grafana.

If you're starting from root only, create a sudo user first (the repo includes a `setup_user.sh` helper for this; root SSH is disabled after it runs).

## Step 2 — Clone the repo

```bash
ssh sysadmin@<your-server-ip>
git clone https://github.com/actools-pl/actoolsDrupal.git
cd actoolsDrupal
```

## Step 3 — Init

```bash
sudo ./actools.sh init \
  --domain example.com \
  --email admin@example.com \
  --site-name "Example Site"
```

This creates `actools.env` and patches three operator-facing fields. Everything else uses sensible defaults — secrets auto-generate during install.

Expected output:

```
ACTOOLS INIT

  OK     actools.env        created
  OK     Domain             example.com
  OK     Admin email        admin@example.com
  OK     Site name          Example Site
  OK     Secrets            will auto-generate during install

Next:
  sudo ./actools.sh preflight
```

If you need to override defaults (memory limits, S3 storage, parallel install), edit `actools.env` directly after `init`. Settings are documented inline.

## Step 4 — Preflight

```bash
sudo ./actools.sh preflight
```

Eight readiness checks. Each shows OK / WARN / FAIL with a concrete next action on anything actionable.

Expected output:

```
ACTOOLS PREFLIGHT

  OK     OS                 Ubuntu 24.04.4 LTS
  OK     actools.env        found
  OK     BASE_DOMAIN        example.com
  OK     DRUPAL_ADMIN_EMAIL admin@example.com
  OK     RAM                4003 MB
  OK     Disk               42 GB free
  OK     Ports              80 and 443 free
  OK     DNS                example.com → 1.2.3.4
  OK     Install state      fresh server

Ready to install.

Next:
  sudo ./actools.sh install
```

Exit codes: `0` ready, `2` warnings only (proceed anyway), `1` failures (fix and re-run).

## Step 5 — Install

```bash
sudo ./actools.sh install
```

Takes about 20 minutes on a CX22. The script installs host packages, Docker, Caddy, MariaDB, Redis, PHP-FPM, the XeLaTeX worker, and Drupal 11. It runs `drush site:install` and writes the admin password to `~/.actools-admin-pass`.

The legacy mode name `fresh` still works and runs the same flow — a deprecation hint is printed to stderr.

## Step 6 — Handoff

The installer ends with a clean summary panel:

```
ACTOOLS HANDOFF

Site:
  https://example.com

Drupal admin:
  https://example.com/user/login

Admin credential file:
  /home/sysadmin/.actools-admin-pass

Useful commands:
  actools doctor
  actools status
  actools logs
  actools backup
  actools update

Install log:
  /home/actools/logs/install/actools-2026-05-24_120000.log
```

You can re-print the handoff anytime with `sudo ./actools.sh handoff`.

## Step 7 — Verify

After reconnecting (so the docker group activates), run:

```bash
actools doctor
```

This is your daily operational command from here on. It runs nine checks and gives you a one-page summary with suggested next actions on anything that isn't green.

---

## What's next

| If you want to | Read |
|---|---|
| Use the platform day-to-day | [`operator-handbook.md`](operator-handbook.md) |
| Look up a specific command | [`command-reference.md`](command-reference.md) |
| Solve a specific problem | [`troubleshooting.md`](troubleshooting.md) |
| Enable PITR, DNA, GDPR, AI, previews, tunnels | [`advanced.md`](advanced.md) |
