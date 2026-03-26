#!/usr/bin/env bash
# =============================================================================
# modules/stack/caddyfile.sh — Caddyfile Generation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

generate_caddyfile() {
  cat > "$INSTALL_DIR/Caddyfile" <<CADDY
{
    email ${DRUPAL_ADMIN_EMAIL}
    log {
        level INFO
    }
    servers {
        protocols h1 h2 h3
    }
}

(drupal_base) {
    encode zstd gzip

    @static {
        file
        path *.css *.js *.png *.jpg *.jpeg *.gif *.svg *.woff2 *.woff *.ico *.pdf
    }
    header @static Cache-Control "public, max-age=31536000, immutable"

    header {
        Strict-Transport-Security   "max-age=31536000; includeSubDomains"
        X-Content-Type-Options      "nosniff"
        X-Frame-Options             "SAMEORIGIN"
        Referrer-Policy             "strict-origin-when-cross-origin"
        -Server
    }

    handle /health {
        respond "OK" 200
    }

    @login {
        path /user/login /user/password
    }
    rate_limit @login {
        zone login_protect {
            key {remote_host}
            events 5
            window 60s
        }
    }

    file_server
}

${BASE_DOMAIN} {
    root * /var/www/html/prod/web
    php_fastcgi php_prod:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}
CADDY
  log "Caddyfile generated."
}
