#!/usr/bin/env bash
# /home/actools/modules/dr/immortalize.sh
# Phase 4.5 — DNA snapshot: complete server blueprint
# Usage: ./immortalize.sh [--upload]

set -euo pipefail

ACTOOLS_HOME="/home/actools"
COMPOSE_FILE="${ACTOOLS_HOME}/docker-compose.yml"
ENV_FILE="${ACTOOLS_HOME}/actools.env"
AGE_KEY_FILE="${ACTOOLS_HOME}/.age-public-key"
DNA_DIR="${ACTOOLS_HOME}/backups/dna"
LOG_FILE="${ACTOOLS_HOME}/logs/immortalize.log"

source "${ENV_FILE}"

log() { echo "$(date -u +%FT%TZ) [immortalize] $*" | tee -a "${LOG_FILE}"; }

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

mkdir -p "${DNA_DIR}"
DATE=$(date +%F)
TIME=$(date +%H%M%S)
DNA_FILE="${DNA_DIR}/dna-${DATE}-${TIME}.json"
ENCRYPTED_FILE="${DNA_FILE}.age"

log "Starting DNA snapshot..."

# ── Collect all state ─────────────────────────────────────────────────────────
python3 << PYEOF
import json, subprocess, os, re

def run(cmd):
    try:
        return subprocess.getoutput(cmd)
    except:
        return ""

def run_json(cmd):
    try:
        return json.loads(subprocess.getoutput(cmd))
    except:
        return {}

# Redact sensitive values from env
def redact_env(path):
    result = {}
    try:
        for line in open(path):
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, val = line.split('=', 1)
            sensitive = any(x in key.upper() for x in [
                'PASS', 'SECRET', 'KEY', 'TOKEN', 'PRIVATE', 'CREDENTIAL'
            ])
            result[key] = '***REDACTED***' if sensitive else val
    except:
        pass
    return result

dna = {
    "version": "2.0",
    "created": run("date -u +%FT%TZ"),
    "actools_version": "v11.0",

    "server": {
        "hostname": run("hostname"),
        "os": run("cat /etc/os-release"),
        "kernel": run("uname -r"),
        "arch": run("uname -m"),
        "cpu_cores": run("nproc"),
        "ram_mb": run("free -m | awk '/^Mem:/{print \$2}'"),
        "disk": run("df -h / | tail -1"),
        "ip": run("curl -s --max-time 3 https://api.ipify.org || hostname -I | awk '{print \$1}'"),
        "hetzner_server_type": run("curl -s --max-time 3 http://169.254.169.254/hetzner/v1/metadata/instance-id 2>/dev/null || echo 'unknown'"),
    },

    "software": {
        "docker_version": run("docker --version"),
        "compose_version": run("docker compose version"),
        "python_version": run("python3 --version"),
        "age_version": run("age --version 2>/dev/null || echo 'not installed'"),
        "rclone_version": run("rclone --version 2>/dev/null | head -1 || echo 'not installed'"),
        "ufw_status": run("sudo ufw status 2>/dev/null || echo 'unavailable'"),
    },

    "docker": {
        "images": run_json("docker images --format json | head -50") or
                  [l for l in run("docker images --format '{{.Repository}}:{{.Tag}}'").splitlines()],
        "volumes": run_json("docker volume ls --format json") or
                   run("docker volume ls --format '{{.Name}}'").splitlines(),
        "networks": run("docker network ls --format '{{.Name}}'").splitlines(),
    },

    "containers": {},
    "env": redact_env("${ACTOOLS_HOME}/actools.env"),

    "modules": {
        "installed": [d for d in os.listdir("${ACTOOLS_HOME}/modules")
                      if os.path.isdir(f"${ACTOOLS_HOME}/modules/{d}")],
        "backup": {
            "binlog_position": run(
                "docker compose -f ${COMPOSE_FILE} exec -T db "
                "mariadb -uroot -p\${DB_ROOT_PASS} --batch --skip-column-names "
                "-e 'SHOW MASTER STATUS;' 2>/dev/null | awk '{print \$1, \$2}'"
            ),
            "latest_dump": run(
                "find ${ACTOOLS_HOME}/backups/db -name '*.sql.gz.age' 2>/dev/null | sort | tail -1"
            ),
        },
    },

    "ssl": {
        "mariadb_cert_expiry": run(
            "openssl x509 -in ${ACTOOLS_HOME}/certs/mariadb/server-cert.pem "
            "-noout -enddate 2>/dev/null || echo 'unknown'"
        ),
        "caddy_cert_expiry": run(
            "echo | openssl s_client -connect localhost:443 -servername feesix.com 2>/dev/null "
            "| openssl x509 -noout -enddate 2>/dev/null || echo 'check manually'"
        ),
    },

    "cron": run("crontab -l -u actools 2>/dev/null || echo 'none'"),
    "cron_d": run("ls /etc/cron.d/"),

    "resurrection_steps": [
        "1. Provision Hetzner CX22 Ubuntu 24.04",
        "2. Create actools user: useradd -m -s /bin/bash actools",
        "3. Install Docker: curl -fsSL https://get.docker.com | sh",
        "4. Add actools to docker group: usermod -aG docker actools",
        "5. Install age: apt-get install -y age",
        "6. Clone repo: git clone https://github.com/actools-pl/actoolsDrupal /home/actools",
        "7. Restore actools.env from secure backup",
        "8. Restore age private key to /home/actools/.age-key.txt",
        "9. Decrypt and restore latest DB dump: actools migrate --point-in-time <datetime>",
        "10. Start stack: docker compose up -d",
        "11. Verify: actools health --verbose",
    ],
}

# Container inspection (running containers only)
try:
    containers = json.loads(subprocess.getoutput(
        "docker inspect \$(docker ps -q) 2>/dev/null"
    ))
    for c in containers:
        name = c.get('Name', '').lstrip('/')
        dna['containers'][name] = {
            'image': c.get('Config', {}).get('Image', ''),
            'status': c.get('State', {}).get('Status', ''),
            'restart_policy': c.get('HostConfig', {}).get('RestartPolicy', {}).get('Name', ''),
            'mounts': [m.get('Source', '') for m in c.get('Mounts', [])],
            'env_keys': [e.split('=')[0] for e in c.get('Config', {}).get('Env', [])],
        }
except:
    pass

with open('${DNA_FILE}', 'w') as f:
    json.dump(dna, f, indent=2)

print(f"DNA snapshot written: ${DNA_FILE}")
size = os.path.getsize('${DNA_FILE}')
print(f"Size: {size} bytes")
PYEOF

log "Encrypting DNA snapshot..."
AGE_PUBLIC_KEY=$(cat "${AGE_KEY_FILE}")
age -r "${AGE_PUBLIC_KEY}" -o "${ENCRYPTED_FILE}" "${DNA_FILE}"
rm "${DNA_FILE}"

SNAPSHOT_SIZE=$(du -sh "${ENCRYPTED_FILE}" | cut -f1)
log "DNA snapshot complete — ${ENCRYPTED_FILE} (${SNAPSHOT_SIZE})"

# Keep only last 7 DNA snapshots locally
find "${DNA_DIR}" -name "dna-*.json.age" | sort | head -n -7 | xargs rm -f 2>/dev/null || true

if [[ "${UPLOAD}" == "true" ]] && command -v rclone &>/dev/null && [[ -n "${RCLONE_REMOTE:-}" ]]; then
    log "Uploading to ${RCLONE_REMOTE}/dna/..."
    rclone copy "${ENCRYPTED_FILE}" "${RCLONE_REMOTE}/dna/" 2>>"${LOG_FILE}"
    log "Upload complete"
fi

log "Immortalization complete"
echo ""
echo "  Decrypt with: age --decrypt -i ~/.age-key.txt ${ENCRYPTED_FILE}"
