#!/usr/bin/env bash
# =============================================================================
# modules/stack/caddyfile.sh — Caddyfile Generation
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact Caddyfile generation,
# extracted verbatim (byte-for-byte via sed) from actools.sh setup_stack().
# Sourced by actools.sh and called by setup_stack (and, in tests, by the
# golden-capture harness). The CADDY heredoc is UNQUOTED, so ${DRUPAL_ADMIN_EMAIL}
# and ${BASE_DOMAIN} expand and the embedded
#   $(if [[ "$ENVIRONMENT_MODE" == "all-in-one" ]]; then cat <<ALLINONE ... fi)
# command substitution renders the dev/stg server blocks only in all-in-one
# mode — exactly as in the monolith.
# =============================================================================

generate_caddyfile() {
  # [v9.2 fix5] log block expanded to multi-line to avoid Caddy 2.8 parse error.
  cat > "$INSTALL_DIR/Caddyfile" <<CADDY
{
    email ${DRUPAL_ADMIN_EMAIL}
    log {
        level INFO
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
        Strict-Transport-Security        "max-age=31536000; includeSubDomains"
        X-Content-Type-Options           "nosniff"
        X-Frame-Options                  "SAMEORIGIN"
        Referrer-Policy                  "strict-origin-when-cross-origin"
        Permissions-Policy               "camera=(), microphone=(), geolocation=()"
        Content-Security-Policy-Report-Only "default-src \'self\' \'unsafe-inline\' \'unsafe-eval\' https:; report-uri /csp-violations"
        -Server
        -X-Powered-By
        -X-Generator
    }

    handle /health {
        respond "OK" 200
    }

    handle /csp-violations {
        respond "logged" 204
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

$(if [[ "$ENVIRONMENT_MODE" == "all-in-one" ]]; then
cat <<ALLINONE
dev.${BASE_DOMAIN} {
    root * /var/www/html/dev/web
    php_fastcgi php_dev:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}

stg.${BASE_DOMAIN} {
    root * /var/www/html/stg/web
    php_fastcgi php_stg:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}
ALLINONE
fi)

${BASE_DOMAIN} {
    root * /var/www/html/prod/web
    php_fastcgi php_prod:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}
CADDY
}
