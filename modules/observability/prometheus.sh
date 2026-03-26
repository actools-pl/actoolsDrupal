#!/usr/bin/env bash
# =============================================================================
# modules/observability/prometheus.sh — Prometheus + Grafana Stack
# Phase 2: Optional observability — enable with ENABLE_OBSERVABILITY=true
# =============================================================================

start_observability() {
  local install_dir="${INSTALL_DIR:-/home/actools}"

  echo "=== Starting Observability Stack ==="
  echo "Prometheus + Grafana + exporters"
  echo ""

  # Create data directories
  mkdir -p "${install_dir}/observability/prometheus"
  mkdir -p "${install_dir}/observability/grafana"
  chown -R 472:472 "${install_dir}/observability/grafana" 2>/dev/null || true

  # Copy prometheus config
  cp "${install_dir}/templates/grafana/prometheus.yml" \
     "${install_dir}/observability/prometheus/prometheus.yml"

  # Generate observability compose file
  cat > "${install_dir}/docker-compose.observability.yml" << OBSCOMPOSE
networks:
  actools_actools_net:
    external: true

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: actools_prometheus
    restart: unless-stopped
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - ./observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./observability/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    networks:
      - actools_actools_net

  grafana:
    image: grafana/grafana:latest
    container_name: actools_grafana
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - ./observability/grafana:/var/lib/grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_PASS:-actools_grafana}"
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_SERVER_ROOT_URL: "https://${BASE_DOMAIN}/grafana"
    networks:
      - actools_actools_net

  node_exporter:
    image: prom/node-exporter:latest
    container_name: actools_node_exporter
    restart: unless-stopped
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - actools_actools_net

  redis_exporter:
    image: oliver006/redis_exporter:latest
    container_name: actools_redis_exporter
    restart: unless-stopped
    environment:
      REDIS_ADDR: "redis://actools_redis:6379"
    networks:
      - actools_actools_net

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: actools_cadvisor
    restart: unless-stopped
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    networks:
      - actools_actools_net
OBSCOMPOSE

  echo "Starting observability containers..."
  docker compose -f "${install_dir}/docker-compose.observability.yml" up -d

  echo ""
  echo "=== Observability Stack Started ==="
  echo "Prometheus : http://localhost:9090"
  echo "Grafana    : http://localhost:3000"
  echo "Login      : admin / ${GRAFANA_PASS:-actools_grafana}"
  echo ""
  echo "To access from your browser, run on your local machine:"
  echo "  ssh -L 3000:localhost:3000 actools@${BASE_DOMAIN}"
  echo "Then open: http://localhost:3000"
}

stop_observability() {
  local install_dir="${INSTALL_DIR:-/home/actools}"
  docker compose -f "${install_dir}/docker-compose.observability.yml" down
  echo "Observability stack stopped."
}

status_observability() {
  local install_dir="${INSTALL_DIR:-/home/actools}"
  docker compose -f "${install_dir}/docker-compose.observability.yml" ps 2>/dev/null \
    || echo "Observability stack not running."
}
