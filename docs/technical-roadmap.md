# Actools — Technical Roadmap

Enterprise hardening and future phases. This document is the architectural reference for committed work that is not yet enabled in the default install.

> **Document version:** 1.0 — March 2026  
> **Current platform:** Actools v11.0  
> **Status:** All Phases 1–4 complete

---

## Overview

The platform has progressed from a monolithic v9.2 installer to a v11.0 modular platform with 32 modular components, automated tests, CI/CD pipeline, self-healing health checks, observability, preview environments, zero-downtime migrations, and a development assistant.

This document covers two architectural directions:

1. **Phase 4.5** — enterprise hardening work to bring the existing system to a target set of operational guarantees
2. **Future Phases 5–8** — architectural extensions under consideration

---

## Part 1 — Phase 4.5: Enterprise Hardening

### What "Enterprise Grade" Actually Means

Enterprise grade is not a feature list. It is a set of operational guarantees:

- **RTO < 15 minutes** — Recovery Time Objective. If the server dies, you are back online within 15 minutes.
- **RPO < 1 hour** — Recovery Point Objective. You lose at most 1 hour of data.
- **99.9% uptime** — No more than 8.7 hours downtime per year.
- **Audit trail** — Every action is logged, timestamped, and attributable.
- **Multi-user access control** — Team members have appropriate access, not shared root.
- **Compliance-ready** — GDPR, SOC2, ISO27001 requirements met at the infrastructure level.

The current v11.0 system meets about 60% of these requirements. Phase 4.5 closes the remaining 40%.

---

### 5A — High Availability & Disaster Recovery

**Current state:** Single Hetzner server. If it goes down, your site goes down.

**Phase 4.5 target:** Automated failover to a standby server within 5 minutes.

#### Implementation

**Step 1: Automated offsite backups with encryption**

```bash
# Install age encryption
sudo apt-get install -y age

# Generate keypair
age-keygen -o /home/actools/.age-key.txt
cat /home/actools/.age-key.txt | grep "public key:" | awk '{print $3}' \
  > /home/actools/.age-public-key

# Encrypt backups before upload
cat > /home/actools/modules/backup/encrypted_backup.sh << 'EOF'
#!/usr/bin/env bash
BACKUP_FILE="$1"
PUBLIC_KEY=$(cat /home/actools/.age-public-key)
age -r "$PUBLIC_KEY" -o "${BACKUP_FILE}.age" "$BACKUP_FILE"
# Upload encrypted file only
rclone copy "${BACKUP_FILE}.age" "${RCLONE_REMOTE}/"
rm "${BACKUP_FILE}.age"  # Remove local encrypted copy
EOF
```

**Step 2: DNA snapshot for 47-second server resurrection**

```bash
# actools immortalize — captures complete server blueprint
actools ai "Generate a DNA.json that captures complete server state"

cat > /home/actools/modules/dr/immortalize.sh << 'EOF'
#!/usr/bin/env bash
# Creates a complete server blueprint
DNA_FILE="/home/actools/backups/dna-$(date +%F).json"

python3 << PYEOF
import json, subprocess, os

dna = {
  "version": "1.0",
  "created": "$(date -u +%FT%TZ)",
  "server": {
    "os": open('/etc/os-release').read(),
    "docker_version": subprocess.getoutput('docker --version'),
    "compose_version": subprocess.getoutput('docker compose version')
  },
  "env": {line.split('=', 1) for line in open('/home/actools/actools.env') 
         if '=' in line and not line.startswith('#')},
  "containers": json.loads(subprocess.getoutput(
    'docker inspect actools_caddy actools_db actools_php_prod actools_redis actools_worker_prod'
  )),
  "images": json.loads(subprocess.getoutput('docker images --format json')),
  "state": json.load(open('/home/actools/.actools-state.json'))
}

json.dump(dna, open('$DNA_FILE', 'w'), indent=2)
print(f"DNA snapshot: $DNA_FILE")
PYEOF
EOF
```

**Step 3: Hetzner Floating IP for instant failover**

```bash
# Provision a second Hetzner server (standby)
# Install Actools v11.0 on standby
# Configure Hetzner Floating IP to point at primary

# Failover script (manual trigger for now, automatic in Phase 5)
cat > /home/actools/modules/dr/failover.sh << 'EOF'
#!/usr/bin/env bash
FLOATING_IP="your-floating-ip"
STANDBY_SERVER_ID="your-standby-id"
HETZNER_TOKEN="${HETZNER_API_TOKEN}"

echo "Initiating failover to standby server..."

# Reassign floating IP via Hetzner API
curl -s -X POST \
  "https://api.hetzner.cloud/v1/floating_ips/${FLOATING_IP}/actions/assign" \
  -H "Authorization: Bearer ${HETZNER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"server\": ${STANDBY_SERVER_ID}}"

echo "Floating IP reassigned. Standby server is now primary."
echo "RTO: $(( SECONDS / 60 )) minutes"
EOF
```

**New CLI commands:**
```bash
actools immortalize          # Create DNA snapshot
actools resurrect            # Restore from DNA on new server
actools failover             # Trigger standby promotion
actools dr-test              # Test disaster recovery procedure
```

---

### 5B — MariaDB High Availability

**Current state:** Single MariaDB container. No replication.

**Phase 4.5 target:** MariaDB with automated backup verification and point-in-time recovery.

#### Immediate: Binary Logging for Point-in-Time Recovery

```ini
# Add to my.cnf
[mysqld]
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
expire_logs_days = 7
max_binlog_size = 100M
sync_binlog = 1
```

```bash
# Point-in-time restore command
actools migrate --point-in-time "2026-03-26 14:30:00" prod
```

#### Phase 4.5: MariaDB Galera Cluster (3 nodes)

Galera provides synchronous multi-master replication. All 3 nodes accept writes simultaneously.

```yaml
# docker-compose.yml addition for Galera
  db_node2:
    image: mariadb:11.4
    environment:
      MARIADB_ROOT_PASSWORD: "${DB_ROOT_PASS}"
      MARIADB_GALERA_CLUSTER_ADDRESS: "gcomm://actools_db,actools_db_node2,actools_db_node3"
    networks:
      - actools_net
```

---

### 5C — Zero-Trust Networking

**Current state:** UFW allows ports 80/443/22. Drupal admin is public.

**Phase 4.5 target:** Zero open inbound ports. Everything via encrypted tunnel.

#### Cloudflare Tunnel Implementation

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb

# Authenticate and create tunnel
cloudflared tunnel login
cloudflared tunnel create actools-<your-domain>

# Configure tunnel
cat > /home/actools/cloudflared-config.yml << 'EOF'
tunnel: YOUR_TUNNEL_ID
credentials-file: /home/actools/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: <your-domain>
    service: http://localhost:80
  - hostname: "*.<your-domain>"
    service: http://localhost:80
  - service: http_status:404
EOF

# Start tunnel
cloudflared tunnel --config /home/actools/cloudflared-config.yml run

# Remove UFW rules — no inbound ports needed
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
sudo ufw delete allow 443/udp
# Only SSH remains (for management)
```

**New CLI command:**
```bash
actools tunnel --status    # Check Cloudflare tunnel health
actools tunnel --restart   # Restart tunnel
actools tunnel --metrics   # Tunnel traffic metrics
```

---

### 5D — Multi-User Access Control

**Current state:** Single `actools` system user with sudo.

**Phase 4.5 target:** Role-based access with audit trail.

#### Implementation

```bash
# Create role-specific system users
sudo useradd -m -s /bin/bash actools-dev     # Developers
sudo useradd -m -s /bin/bash actools-ops     # Operations
sudo useradd -m -s /bin/bash actools-viewer  # Read-only

# Create sudoers rules
cat > /etc/sudoers.d/actools-roles << 'EOF'
# Developers can: create branches, run drush, view logs
actools-dev ALL=(actools) NOPASSWD: /usr/local/bin/actools branch *
actools-dev ALL=(actools) NOPASSWD: /usr/local/bin/actools drush *
actools-dev ALL=(actools) NOPASSWD: /usr/local/bin/actools logs *

# Ops can: everything except install
actools-ops ALL=(actools) NOPASSWD: /usr/local/bin/actools *
actools-ops ALL=(root) NOPASSWD: /usr/local/bin/actools health *

# Viewers: read-only access
actools-viewer ALL=(actools) NOPASSWD: /usr/local/bin/actools status
actools-viewer ALL=(actools) NOPASSWD: /usr/local/bin/actools health *
actools-viewer ALL=(actools) NOPASSWD: /usr/local/bin/actools logs *
EOF
```

#### Audit Logging

```bash
# Log all actools CLI invocations
cat > /usr/local/bin/actools-audit << 'EOF'
#!/usr/bin/env bash
# Prepend to every actools command
echo "$(date -u +%FT%TZ) $(whoami) actools $*" \
  >> /home/actools/logs/audit.log
/usr/local/bin/actools-real "$@"
EOF
```

---

### 5E — Security Hardening

#### MariaDB SSL Encryption

```bash
# Generate self-signed certificates for MariaDB SSL
mkdir -p /home/actools/certs/mariadb
cd /home/actools/certs/mariadb

openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 3650 \
  -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=Actools MariaDB CA"

openssl req -newkey rsa:2048 -days 3650 -nodes \
  -keyout server-key.pem -out server-req.pem \
  -subj "/CN=actools_db"
openssl x509 -req -in server-req.pem \
  -days 3650 -CA ca-cert.pem -CAkey ca-key.pem \
  -set_serial 01 -out server-cert.pem
```

#### PHP-FPM Process Isolation

```yaml
# docker-compose.yml — add user namespace remapping
security_opt:
  - no-new-privileges:true
  - seccomp:unconfined
userns_mode: "host"
```

#### Automated Security Scanning

```bash
# Add to weekly cron
cat > /etc/cron.weekly/actools-security << 'EOF'
#!/usr/bin/env bash
cd /home/actools

# Drupal security advisories
docker compose exec -T php_prod bash -c \
  "cd /var/www/html/prod && ./vendor/bin/drush pm:security" \
  >> /home/actools/logs/security-$(date +%F).log 2>&1

# Container image vulnerability scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image actools_worker:latest \
  >> /home/actools/logs/security-$(date +%F).log 2>&1

# Send report
cat /home/actools/logs/security-$(date +%F).log \
  | mail -s "Actools Weekly Security Report $(date +%F)" mpal_singh@yahoo.com
EOF
chmod +x /etc/cron.weekly/actools-security
```

---

### 5F — Compliance & Audit Trail

#### GDPR Compliance Module

```bash
cat > /home/actools/modules/compliance/gdpr.sh << 'EOF'
#!/usr/bin/env bash
# GDPR compliance tools

gdpr_export_user() {
  local email="$1"
  # Export all data for a specific user
  docker compose exec -T php_prod bash -c "
    cd /var/www/html/prod
    ./vendor/bin/drush php:eval \"
      \\\$account = user_load_by_mail('${email}');
      if (\\\$account) {
        \\\$data = \\Drupal\\user\\Entity\\User::load(\\\$account->id())->toArray();
        echo json_encode(\\\$data, JSON_PRETTY_PRINT);
      }
    \"
  "
}

gdpr_delete_user() {
  local email="$1"
  echo "Deleting all data for user: ${email}"
  docker compose exec -T php_prod bash -c "
    cd /var/www/html/prod
    ./vendor/bin/drush user:cancel --delete-content --mail='${email}' --yes
  "
}

gdpr_audit_log() {
  # Show all actions taken on user data
  cat /home/actools/logs/audit.log | grep "${1:-}" | tail -100
}
EOF
```

---

### Phase 4.5 Summary

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| Encrypted offsite backups (age) | Critical | 1 day | Disaster recovery |
| Binary logging + PITR | Critical | 1 day | Data protection |
| Cloudflare Tunnel (zero-trust) | High | 2 days | Security posture |
| Multi-user RBAC | High | 2 days | Team enablement |
| MariaDB SSL | Medium | 1 day | Encryption in transit |
| Automated security scanning | Medium | 1 day | Compliance |
| GDPR tools | Medium | 2 days | Regulatory compliance |
| Galera clustering | Low | 1 week | True HA (Phase 5 prep) |
| DNA/resurrection system | High | 3 days | <15min RTO |
| Audit trail | Medium | 1 day | Compliance |

**Phase 4.5 estimated duration:** Several weeks of focused architectural work.

---

## Part 2 — Future Phases 6–9

### Phase 5 — Multi-Tenancy (Month 3–5)

**Goal:** Run multiple independent Drupal sites on one Actools installation.

This is the technical foundation for running multiple isolated sites on shared infrastructure.

#### Architecture

```
/home/actools/
├── tenants/
│   ├── <tenant-name>/   ← Tenant 1
│   │   ├── actools.env
│   │   ├── docroot/
│   │   └── docker-compose.tenant.yml
│   ├── client-alpha/    ← New tenant
│   │   ├── actools.env
│   │   └── ...
│   └── client-beta/
```

#### New CLI Commands

```bash
actools tenant create client-alpha --domain=client-alpha.com
actools tenant list
actools tenant destroy client-alpha
actools tenant migrate client-alpha --from=shared --to=dedicated
```

#### Shared Infrastructure, Isolated Data

```yaml
# Shared: Caddy (one instance handles all domains)
# Shared: Prometheus/Grafana (one observability stack)
# Isolated: MariaDB databases (one per tenant)
# Isolated: PHP-FPM containers (one per tenant)
# Isolated: File storage (one S3 prefix per tenant)
# Isolated: Redis database numbers (0-15, one per tenant)
```

---

### Phase 6 — GitHub Webhook Integration (Month 4–6)

**Goal:** `git push` to main triggers automatic deployment. PR opened creates preview environment. PR merged destroys it.

```bash
# GitHub sends webhook → Actools listens → Executes

# Webhook receiver (lightweight Python service)
cat > /home/actools/modules/webhook/receiver.py << 'EOF'
from flask import Flask, request, abort
import hmac, hashlib, subprocess, os

app = Flask(__name__)
SECRET = os.environ['GITHUB_WEBHOOK_SECRET']

@app.route('/webhook', methods=['POST'])
def webhook():
    sig = request.headers.get('X-Hub-Signature-256')
    if not verify_signature(request.data, sig):
        abort(403)
    
    payload = request.json
    event = request.headers.get('X-GitHub-Event')
    
    if event == 'pull_request':
        if payload['action'] == 'opened':
            branch = payload['pull_request']['head']['ref']
            pr_num = payload['pull_request']['number']
            subprocess.run(['actools', 'branch', f'pr-{pr_num}-{branch}'])
        
        elif payload['action'] in ['closed', 'merged']:
            pr_num = payload['pull_request']['number']
            subprocess.run(['actools', 'branch', '--destroy', f'pr-{pr_num}'])
    
    elif event == 'push' and payload.get('ref') == 'refs/heads/main':
        subprocess.run(['actools', 'update'])
    
    return 'OK', 200
EOF
```

---

### Phase 7 — Content Intelligence Layer (Month 6–9)

**Goal:** Transform the AI assistant from code-aware to content-aware. The platform understands what content is being generated and optimises for it.

This is the vision behind the "content generator" use case.

#### Features

```bash
# Analyse content performance
actools content analyze --last=30d
# Output: Which content types get most traffic
#         Which PDFs get downloaded most
#         Content gaps based on search queries

# Auto-generate content structure
actools content scaffold --type=annual-report
# Creates: Drupal content type, fields, display modes, 
#          XeLaTeX template, workflow, permissions

# Content quality scoring
actools content score --node=123
# Checks: readability, SEO, accessibility, completeness

# Translate content (AI-powered)
actools content translate --node=123 --to=hi,ta,bn
# Uses local Ollama with multilingual model
```

#### Technical Stack Addition

```yaml
# docker-compose.yml additions for Phase 7
  chromadb:
    image: chromadb/chroma:latest
    container_name: actools_chromadb
    volumes:
      - chromadb_data:/chroma/chroma
    networks:
      - actools_actools_net

  ollama_large:
    image: ollama/ollama:latest
    container_name: actools_ollama_large
    volumes:
      - ollama_models:/root/.ollama
    # For content intelligence, use larger model:
    # ollama pull llama3:8b (requires 6GB RAM)
    # or mistral:7b for multilingual
```

---

### Phase 8 — Edge Distribution (Month 9–12)

**Goal:** Distribute XeLaTeX PDF generation and content delivery globally.

#### Distributed XeLaTeX Workers

```bash
# When XELATEX_MODE=remote is set:
# Primary server queues PDF jobs
# Worker servers (any location) pick up jobs
# Completed PDFs returned via S3

actools worker add-node --location=us-east --endpoint=https://worker-us.<your-domain>
actools worker add-node --location=eu-west --endpoint=https://worker-eu.<your-domain>
actools worker list-nodes
actools worker stats
```

#### Fly.io / Hetzner Multi-Region

```bash
# Deploy worker containers to multiple regions
# Each worker is a minimal Docker image with just:
# - PHP
# - XeLaTeX
# - S3 client

# actools.env additions for Phase 8
WORKER_DISTRIBUTED=true
WORKER_ENDPOINTS=https://worker-us.<your-domain>,https://worker-eu.<your-domain>
WORKER_LOAD_BALANCE=round-robin   # or latency-based
```

#### CDN Integration

```bash
# Cloudflare R2 for zero-egress S3 storage
STORAGE_PROVIDER=cloudflare
S3_ENDPOINT_URL=https://ACCOUNT_ID.r2.cloudflarestorage.com

# Cloudflare Pages for static asset delivery
actools cdn enable --provider=cloudflare
```

---

## The Complete Roadmap at a Glance

```
NOW (v11.0)
├── ✅ Phase 1: Modular architecture (32 modules, 21 tests)
├── ✅ Phase 2: Observability (Grafana, health checks, cost-optimize)
├── ✅ Phase 3: Developer platform (preview envs, CI/CD, migrations)
├── ✅ Phase 4: AI-native dev environment (Ollama, code-aware)
│
├── 🔜 Phase 4.5: Enterprise hardening (4-6 weeks)
│   ├── Encrypted backups + PITR
│   ├── Zero-trust networking (Cloudflare Tunnel)
│   ├── Multi-user RBAC + audit trail
│   ├── MariaDB SSL
│   ├── DNA/resurrection system (RTO < 15min)
│   └── GDPR compliance tools
│
├── 🔮 Phase 5: Multi-tenancy (Month 3–5)
│   ├── Multiple Drupal sites per server
│   ├── Tenant isolation (DB, files, PHP-FPM)
│   └── actools tenant CLI
│
├── 🔮 Phase 6: GitHub webhook automation (Month 4–6)
│   ├── PR → preview environment (automatic)
│   ├── Merge → deploy (automatic)
│   └── Webhook receiver service
│
├── 🔮 Phase 7: Content intelligence (Month 6–9)
│   ├── Content performance analytics
│   ├── AI content scaffolding
│   ├── Multilingual AI (local Ollama)
│   └── Content quality scoring
│
└── 🔮 Phase 8: Edge distribution (Month 9–12)
    ├── Distributed XeLaTeX workers
    ├── Multi-region deployment
    ├── Cloudflare R2 + CDN integration
    └── Global load balancing
```

---
