#!/usr/bin/env bash
# =============================================================================
# modules/stack/compose.sh — docker-compose.yml Generation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

generate_compose() {
  local WEB_MEM="${PHP_MEMORY_LIMIT:-512m}"
  local WORKER_MEM="${WORKER_MEMORY_LIMIT:-2g}"
  local DB_MEM="${DB_MEMORY_LIMIT:-2g}"
  local REDIS_MEM="${REDIS_MEMORY_LIMIT:-256m}"
  local REDIS_ON="${ENABLE_REDIS:-true}"

  cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
networks:
  actools_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
  db_data:

services:

  caddy:
    image: actools_caddy:custom
    pull_policy: never
    container_name: actools_caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./docroot:/var/www/html:ro
      - ./caddy/data:/data
      - ./caddy/config:/config
      - ./logs/caddy:/var/log/caddy
    depends_on:
      - php_prod
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  php_prod:
    image: drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm
    container_name: actools_php_prod
    restart: unless-stopped
    volumes:
      - ./docroot/prod:/var/www/html/prod
      - ./logs/php_prod:/var/log/php
    environment:
      PHP_MEMORY_LIMIT: "${WEB_MEM}"
      PHP_UPLOAD_MAX_FILESIZE: "${PHP_UPLOAD_MAX:-256m}"
      PHP_MAX_EXECUTION_TIME: "${PHP_MAX_EXEC:-300}"
      AWS_ACCESS_KEY_ID: "${AWS_ACCESS_KEY_ID:-}"
      AWS_SECRET_ACCESS_KEY: "${AWS_SECRET_ACCESS_KEY:-}"
      S3_BUCKET: "${S3_BUCKET:-}"
      STORAGE_PROVIDER: "${STORAGE_PROVIDER:-}"
      AWS_REGION: "${AWS_REGION:-us-east-1}"
      S3_ENDPOINT_URL: "${S3_ENDPOINT_URL:-}"
      ASSET_CDN_HOST: "${ASSET_CDN_HOST:-}"
    mem_limit: "${WEB_MEM}"
    tmpfs:
      - /tmp:size=256m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - SETUID
      - SETGID
      - DAC_OVERRIDE
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  worker_prod:
    image: actools_worker:latest
    pull_policy: never
    container_name: actools_worker_prod
    restart: unless-stopped
    command: ["bash", "-c", "cd /var/www/html/prod && ./vendor/bin/drush queue:run actools_document_export --time-limit=600"]
    volumes:
      - ./docroot/prod:/var/www/html/prod
      - ./logs/worker:/var/log/worker
    environment:
      PHP_MEMORY_LIMIT: "${WORKER_MEM}"
      XELATEX_MODE: "${XELATEX_MODE:-local}"
      XELATEX_ENDPOINT: "${XELATEX_ENDPOINT:-}"
      AWS_ACCESS_KEY_ID: "${AWS_ACCESS_KEY_ID:-}"
      AWS_SECRET_ACCESS_KEY: "${AWS_SECRET_ACCESS_KEY:-}"
      S3_BUCKET: "${S3_BUCKET:-}"
      STORAGE_PROVIDER: "${STORAGE_PROVIDER:-}"
      AWS_REGION: "${AWS_REGION:-us-east-1}"
      S3_ENDPOINT_URL: "${S3_ENDPOINT_URL:-}"
      ASSET_CDN_HOST: "${ASSET_CDN_HOST:-}"
    mem_limit: "${WORKER_MEM}"
    tmpfs:
      - /tmp:size=256m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - SETUID
      - SETGID
      - DAC_OVERRIDE
    healthcheck:
      test: ["CMD-SHELL", "php -v && xelatex --version > /dev/null 2>&1"]
      interval: 60s
      timeout: 15s
      retries: 3
      start_period: 60s
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  db:
    image: mariadb:${MARIADB_VERSION}
    container_name: actools_db
    restart: unless-stopped
    stop_grace_period: 2m
    environment:
      MARIADB_ROOT_PASSWORD: "${DB_ROOT_PASS}"
      MARIADB_AUTO_UPGRADE: "1"
    volumes:
      - db_data:/var/lib/mysql
      - ./logs/db:/var/log/mysql
      - ./my.cnf:/etc/mysql/conf.d/actools.cnf:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 8
      start_period: 30s
    networks:
      - actools_net
    mem_limit: "${DB_MEM}"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

$(if [[ "${REDIS_ON}" == "true" ]]; then
cat <<REDIS_SVC
  redis:
    image: redis:7-alpine
    container_name: actools_redis
    restart: unless-stopped
    command: redis-server --maxmemory ${REDIS_MEM} --maxmemory-policy allkeys-lru
    mem_limit: "${REDIS_MEM}"
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"
REDIS_SVC
fi)
COMPOSE
  log "docker-compose.yml generated."
}
