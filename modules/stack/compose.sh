#!/usr/bin/env bash
# =============================================================================
# modules/stack/compose.sh — docker-compose.yml Generation
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact docker-compose.yml
# generation, extracted verbatim (byte-for-byte via sed) from actools.sh
# setup_stack(). Sourced by actools.sh and called by setup_stack (and, in tests,
# by the golden-capture harness). Behaviour preserved exactly:
#   - the six mem/toggle locals (WEB_MEM/WORKER_MEM/DB_MEM/REDIS_MEM/CADVISOR/
#     REDIS_ON) and the four heredoc-fragment strings (PHP_ENV_BLOCK,
#     WORKER_ENV_BLOCK, S3_ENV_BLOCK, PHP_SEC_BLOCK), kept NON-local exactly as
#     the monolith declares them;
#   - the UNQUOTED COMPOSE heredoc (so ${...} and the embedded
#     $(... cat <<ALLINONE_SVC/REDIS_SVC/CADVISOR_SVC ...) fragments render);
#   - the php_prod/worker_prod 'depends_on: redis' lines are UNCONDITIONAL while
#     the redis SERVICE block is conditional — so redis-off yields a compose
#     file that names redis in depends_on without defining the service. This is
#     the monolith's existing behaviour and is preserved deliberately.
# Only file GENERATION lives here; `docker compose pull/down/up` stays in
# setup_stack as orchestration.
# =============================================================================

generate_compose() {
  local WEB_MEM="${PHP_MEMORY_LIMIT:-512m}"
  local WORKER_MEM="${WORKER_MEMORY_LIMIT:-2g}"
  local DB_MEM="${DB_MEMORY_LIMIT:-2g}"
  # shellcheck disable=SC2034  # used in the $(...)REDIS_SVC heredoc fragment below; shellcheck can't trace vars through nested heredocs
  local REDIS_MEM="${REDIS_MEMORY_LIMIT:-256m}"
  local CADVISOR="${ENABLE_CADVISOR:-false}"
  local REDIS_ON="${ENABLE_REDIS:-true}"

  PHP_ENV_BLOCK="
      PHP_MEMORY_LIMIT: \"${WEB_MEM}\"
      PHP_UPLOAD_MAX_FILESIZE: \"${PHP_UPLOAD_MAX:-256m}\"
      PHP_MAX_EXECUTION_TIME: \"${PHP_MAX_EXEC:-300}\"
      COMPOSER_PROCESS_TIMEOUT: \"${COMPOSER_PROCESS_TIMEOUT:-600}\"
      PHP_OPCACHE_ENABLE: \"${PHP_OPCACHE_ENABLE:-1}\"
      PHP_OPCACHE_MEMORY_CONSUMPTION: \"${PHP_OPCACHE_MEMORY:-256}\"
      PHP_OPCACHE_MAX_ACCELERATED_FILES: \"${PHP_OPCACHE_MAX_FILES:-20000}\"
      PHP_OPCACHE_VALIDATE_TIMESTAMPS: \"${PHP_OPCACHE_VALIDATE_TIMESTAMPS:-1}\""

  WORKER_ENV_BLOCK="
      PHP_MEMORY_LIMIT: \"${WORKER_MEM}\"
      PHP_UPLOAD_MAX_FILESIZE: \"${PHP_UPLOAD_MAX:-256m}\"
      PHP_MAX_EXECUTION_TIME: \"600\"
      COMPOSER_PROCESS_TIMEOUT: \"${COMPOSER_PROCESS_TIMEOUT:-600}\"
      XELATEX_MODE: \"${XELATEX_MODE:-local}\"
      XELATEX_ENDPOINT: \"${XELATEX_ENDPOINT:-}\"
      AWS_ACCESS_KEY_ID: \"${AWS_ACCESS_KEY_ID:-}\"
      AWS_SECRET_ACCESS_KEY: \"${AWS_SECRET_ACCESS_KEY:-}\"
      S3_BUCKET: \"${S3_BUCKET:-}\"
      STORAGE_PROVIDER: \"${STORAGE_PROVIDER:-}\"
      AWS_REGION: \"${AWS_REGION:-us-east-1}\"
      S3_ENDPOINT_URL: \"${S3_ENDPOINT_URL:-}\"
      ASSET_CDN_HOST: \"${ASSET_CDN_HOST:-}\""

  S3_ENV_BLOCK="
      AWS_ACCESS_KEY_ID: \"${AWS_ACCESS_KEY_ID:-}\"
      AWS_SECRET_ACCESS_KEY: \"${AWS_SECRET_ACCESS_KEY:-}\"
      S3_BUCKET: \"${S3_BUCKET:-}\"
      STORAGE_PROVIDER: \"${STORAGE_PROVIDER:-}\"
      AWS_REGION: \"${AWS_REGION:-us-east-1}\"
      S3_ENDPOINT_URL: \"${S3_ENDPOINT_URL:-}\"
      ASSET_CDN_HOST: \"${ASSET_CDN_HOST:-}\""

  PHP_SEC_BLOCK="
    tmpfs:
      - /tmp:size=256m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - SETUID
      - SETGID
      - DAC_OVERRIDE"

  # [v9.2 fix8] version: removed (obsolete in Compose v2)
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
    image: actools_php:custom
    container_name: actools_php_prod
    restart: unless-stopped
    volumes:
      - ./docroot/prod:/var/www/html/prod
      - ./logs/php_prod:/var/log/php
    environment:${PHP_ENV_BLOCK}${S3_ENV_BLOCK}
    mem_limit: "${WEB_MEM}"${PHP_SEC_BLOCK}
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
    command: ["bash", "-c", "while true; do sleep 60; done"]
    volumes:
      - ./docroot/prod:/var/www/html/prod
      - ./logs/worker:/var/log/worker
    environment:${WORKER_ENV_BLOCK}
    mem_limit: "${WORKER_MEM}"${PHP_SEC_BLOCK}
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

$(if [[ "$ENVIRONMENT_MODE" == "all-in-one" ]]; then
cat <<ALLINONE_SVC
  php_dev:
    image: actools_php:custom
    container_name: actools_php_dev
    restart: unless-stopped
    volumes:
      - ./docroot/dev:/var/www/html/dev
      - ./logs/php_dev:/var/log/php
    environment:${PHP_ENV_BLOCK}
    mem_limit: "${WEB_MEM}"${PHP_SEC_BLOCK}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    depends_on:
      db:
        condition: service_healthy
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  php_stg:
    image: actools_php:custom
    container_name: actools_php_stg
    restart: unless-stopped
    volumes:
      - ./docroot/stg:/var/www/html/stg
      - ./logs/php_stg:/var/log/php
    environment:${PHP_ENV_BLOCK}
    mem_limit: "${WEB_MEM}"${PHP_SEC_BLOCK}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    depends_on:
      db:
        condition: service_healthy
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
ALLINONE_SVC
fi)

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

$(if [[ "${CADVISOR}" == "true" ]]; then
cat <<CADVISOR_SVC
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: actools_cadvisor
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    networks:
      - actools_net
CADVISOR_SVC
fi)
COMPOSE
}
