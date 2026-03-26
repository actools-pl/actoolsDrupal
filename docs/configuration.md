# Configuration

> All configuration lives in `actools.env` — never committed to git.  
> Applies to: Actools v11.0+

---

## actools.env reference

### Required

```bash
BASE_DOMAIN=feesix.com            # primary domain — no https://, no trailing slash
DRUPAL_ADMIN_EMAIL=you@example.com
DRUPAL_ADMIN_PASS=changeme
DB_ROOT_PASS=strongpassword
```

### Backup & recovery

```bash
BACKUP_RETENTION_DAYS=7           # how many days of backups to keep locally
RCLONE_REMOTE=b2:my-bucket        # rclone remote for off-site backup upload
                                  # leave empty to skip off-site upload
```

### S3 / file storage

```bash
ENABLE_S3_STORAGE=false           # set true to enable S3 for public files
STORAGE_PROVIDER=backblaze        # aws | backblaze | wasabi | custom
S3_ENDPOINT_URL=https://s3.us-west-000.backblazeb2.com
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_REGION=us-east-1
ASSET_CDN_HOST=                   # optional CDN hostname for public assets
```

Provider is auto-detected from endpoint URL. Credentials are injected via Docker environment — never stored in Drupal config exports.

### XeLaTeX / PDF worker

```bash
XELATEX_MODE=local                # local | remote
XELATEX_ENDPOINT=                 # required if mode=remote
                                  # e.g. https://worker.yourdomain.com
```

In `local` mode the worker container handles all PDF generation. In `remote` mode jobs are dispatched to an external worker (Phase 8 — edge distribution).

### Redis

```bash
REDIS_HOST=actools_redis          # container name on actools_net
                                  # leave default unless running Redis externally
```

### Observability

```bash
GRAFANA_ADMIN_PASS=changeme
PROMETHEUS_RETENTION_DAYS=30
```

---

## S3 provider setup

### Backblaze B2

```bash
STORAGE_PROVIDER=backblaze
S3_ENDPOINT_URL=https://s3.us-west-000.backblazeb2.com
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-keyId
AWS_SECRET_ACCESS_KEY=your-applicationKey
```

### AWS S3

```bash
STORAGE_PROVIDER=aws
AWS_REGION=eu-west-1
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

### Cloudflare R2

```bash
STORAGE_PROVIDER=custom
S3_ENDPOINT_URL=https://ACCOUNT_ID.r2.cloudflarestorage.com
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

### Test your storage config

```bash
actools storage-test              # PUT → GET → DELETE round trip
actools storage-info              # show current config
```

---

## XeLaTeX modes

### Local mode (default)

PDF generation happens inside `actools_worker_prod` on the same server. No external dependencies.

```bash
XELATEX_MODE=local
```

Memory limit for the worker is set in `docker-compose.yml` — default 2GB. Increase if generating large or complex documents.

### Remote mode (Phase 8)

```bash
XELATEX_MODE=remote
XELATEX_ENDPOINT=https://worker.yourdomain.com
```

Jobs are dispatched to a remote worker over HTTPS. The worker is a minimal Docker image with PHP + XeLaTeX + S3 client. Used for distributing PDF load across regions.

---

## Drupal settings.php

Actools automatically injects into `settings.php`:
- Database credentials via `$databases`
- Trusted host patterns for your domain and all preview subdomains
- S3FS credentials via `getenv()` (never hardcoded)
- Redis connection if `REDIS_HOST` is set

For manual settings.php hardening — private files, session security, error handling — see [Hardening](hardening.md).

---

*Back to [docs index](README.md)*
