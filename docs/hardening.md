# Hardening

> Applies to: Actools v11.2.0+ · Drupal 11 · MariaDB 11.4

---

## settings.php

Actools auto-injects database credentials, trusted host patterns, S3FS config, Redis connection, and session cookie security flags. The following you add manually.

### Private files

All XeLaTeX-generated PDFs must use private files — not public. Private files are served through Drupal's access control, not directly by the web server.

```php
// settings.php
$settings['file_private_path'] = '/home/actools/docroot/prod/private';
```

```bash
mkdir -p /home/actools/docroot/prod/private
chmod 750 /home/actools/docroot/prod/private
chown www-data:www-data /home/actools/docroot/prod/private
```

Then set in Drupal: **Admin → Configuration → Media → File system → Private file system path**

### Session security (auto-applied)

```php
ini_set('session.cookie_secure', TRUE);      // HTTPS only
ini_set('session.cookie_httponly', TRUE);    // no JavaScript access
ini_set('session.cookie_samesite', 'Strict'); // CSRF protection
ini_set('session.use_strict_mode', TRUE);    // reject uninitialized IDs
ini_set('session.use_only_cookies', TRUE);   // no session ID in URL
```

### Production error handling

```php
// Never show errors to users
$config['system.logging']['error_level'] = 'hide';
$settings['rebuild_access'] = FALSE;
ini_set('display_errors', FALSE);
ini_set('log_errors', TRUE);
ini_set('error_log', '/var/log/php/drupal-error.log');
```

### Database connection hardening

```php
$databases['default']['default']['pdo'] = [
  PDO::ATTR_TIMEOUT         => 5,
  PDO::ATTR_PERSISTENT      => FALSE,
  PDO::MYSQL_ATTR_COMPRESS  => TRUE,
];
```

### Trusted host patterns

```php
// Already injected by Actools — verify it's present
$settings['trusted_host_patterns'] = [
  '^example\.com$',
  '^.*\.example\.com$',   // covers all preview environments
];
```

If you add Cloudflare in front of the server:

```php
$settings['reverse_proxy'] = TRUE;
$settings['reverse_proxy_addresses'] = ['103.21.244.0/22', /* Cloudflare ranges */];
$settings['reverse_proxy_trusted_headers'] =
  \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_FOR |
  \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_PROTO;
```

### Permissions checklist

```bash
# settings.php — read-only to web server
chmod 440 /home/actools/docroot/prod/sites/default/settings.php
chown www-data:www-data /home/actools/docroot/prod/sites/default/settings.php

# Public files
chmod 755 /home/actools/docroot/prod/sites/default/files
chown -R www-data:www-data /home/actools/docroot/prod/sites/default/files

# Private files
chmod 750 /home/actools/docroot/prod/private
chown -R www-data:www-data /home/actools/docroot/prod/private
```

---

## MariaDB TLS — Not enabled by default

A MariaDB TLS configuration template is provided at `certs/mariadb/99-ssl.cnf` for operators who want to enable encryption-in-transit between Drupal and MariaDB.

The template is NOT mounted into the database container by default. To enable MariaDB TLS, operators must:

1. Generate a server private key (`server-key.pem`) and a matching server certificate signed by the provided CA (or by a per-deployment CA — recommended)
2. Mount `certs/mariadb/` into the db service at `/etc/mysql/certs/`
3. Mount `99-ssl.cnf` at `/etc/mysql/mariadb.conf.d/99-ssl.cnf`
4. Configure Drupal's database connection to use SSL

Per-deployment certificate generation (replacing the shared CA template currently shipped) is planned work. Until then, the templates exist as scaffolding; enabling them requires manual operator setup.

### Regenerate certificates

```bash
cd /home/actools/certs/mariadb

openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=Actools MariaDB CA/O=Actools/C=PL"

openssl req -newkey rsa:2048 -days 3650 -nodes \
  -keyout server-key.pem -out server-req.pem \
  -subj "/CN=actools_db/O=Actools/C=PL"
openssl x509 -req -in server-req.pem -days 3650 \
  -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
rm server-req.pem

chmod 644 server-key.pem ca-key.pem
docker compose restart db
```

Private keys (`*-key.pem`) are gitignored. Keep them in secure off-server storage.

---

## RBAC

Three system users with scoped access to `actools` CLI commands:

| Role | User | Permitted commands |
|---|---|---|
| Developer | `actools-dev` | `branch`, `drush`, `logs`, `status`, `health`, `shell`, `worker-*` |
| Operations | `actools-ops` | All `actools` commands |
| Viewer | `actools-viewer` | `status`, `health`, `logs`, `worker-status`, `tls-status` |

### Add a new team member

```bash
sudo useradd -m -s /bin/bash actools-dev
sudo passwd actools-dev

# SSH key
sudo mkdir -p /home/actools-dev/.ssh
echo "ssh-ed25519 AAAA..." | sudo tee -a /home/actools-dev/.ssh/authorized_keys
sudo chmod 700 /home/actools-dev/.ssh
sudo chmod 600 /home/actools-dev/.ssh/authorized_keys
sudo chown -R actools-dev:actools-dev /home/actools-dev/.ssh
```

The team member runs `actools` commands as:
```bash
sudo -u actools actools branch feature-123
sudo -u actools actools drush prod cache:rebuild
```

### Sudoers rules

Rules are in `modules/security/sudoers-roles`. Deploy with:

```bash
sudo cp modules/security/sudoers-roles /etc/sudoers.d/actools-roles
sudo chmod 440 /etc/sudoers.d/actools-roles
sudo visudo -c -f /etc/sudoers.d/actools-roles  # validate before use
```

---

## Audit trail

Every `actools` invocation is logged before execution:

```
2026-03-26T21:37:18Z user=actools euid=1000 args=status
2026-03-26T22:13:00Z user=actools-ops euid=1002 args=backup db
2026-03-26T22:25:52Z user=actools euid=1000 args=gdpr export user@example.com
```

Log: `/home/actools/logs/audit.log`

The audit wrapper (`/usr/local/bin/actools-audit`) is the symlink target of `/usr/local/bin/actools`. It appends to the log then calls `/usr/local/bin/actools-real`.

**Scope of this log.** This is best-effort append logging suitable for after-the-fact operator visibility: who ran which command, when. The wrapper tolerates write failures (`|| true`) and the log file has no cryptographic integrity protection — entries can be silently modified, deleted, or lost without detection. This audit trail is appropriate for operational review and incident investigation; it is not suitable for compliance attestation, non-repudiation, or any context requiring tamper-evidence. Strengthening this to a tamper-resistant audit surface (signed entries, integrity files, append-only enforcement) is a future hardening item.

---

## Firewall

Current UFW rules:

```bash
sudo ufw status numbered
# [ 1] 22/tcp   LIMIT IN   Anywhere   # SSH rate-limited
# [ 2] 80/tcp   ALLOW IN   Anywhere   # HTTP (Caddy ACME)
# [ 3] 443/tcp  ALLOW IN   Anywhere   # HTTPS
# [ 4] 443/udp  ALLOW IN   Anywhere   # HTTP/3 QUIC
```

When Cloudflare Tunnel is configured, ports 2–4 will be removed — the server will make no inbound connections on those ports.

---

## Security scanning

```bash
# Drupal security advisories
actools drush prod pm:security
```

Weekly automated scan via cron (installs via `modules/security/`):

```bash
# /etc/cron.weekly/actools-security
# Runs: drush pm:security + trivy container scan + emails report
```

---

*Back to [docs index](README.md)*
