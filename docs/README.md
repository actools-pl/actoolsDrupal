# Actools Drupal Community — Documentation

A guided single-server Drupal installer and operator CLI for Ubuntu 24.04.

## Start here

| Doc | Read when |
|---|---|
| [Quick start](quick-start.md) | First time — install in five staged commands |
| [Operator handbook](operator-handbook.md) | Day-to-day — the five commands you actually use |
| [Command reference](command-reference.md) | Looking up a specific flag |
| [Troubleshooting](troubleshooting.md) | Something is broken |
| [Advanced features](advanced.md) | PITR, DNA, GDPR, AI, previews, tunnels, audit |

## Reference

| Doc | What it covers |
|---|---|
| [Architecture](architecture.md) | How it's built — modules, state, profiles |
| [Configuration](configuration.md) | Environment variables, S3, XeLaTeX modes |
| [Hardening](hardening.md) | TLS, RBAC, audit trail, settings.php |
| [Observability](observability.md) | Prometheus, Grafana, dashboards |
| [Enterprise hardening](enterprise.md) | PITR, DNA resurrection, GDPR tools |
| [Operations](operations.md) | Backups, updates, health, troubleshooting (legacy) |
| [Privacy](privacy.md) | What stays local, what doesn't |
| [Changelog](CHANGELOG.md) | Version history |

## About the project

This is a **single-server Drupal installer**. It is not a managed hosting platform, multi-tenant SaaS, compliance certification, or DrupalFortress. The advanced features in [`advanced.md`](advanced.md) are useful but optional.

A hardened single-tenant platform with optional governance — DrupalFortress — is being developed separately. It reuses this installer's staged operator UX via the profile contract documented in [`../profiles/README.md`](../profiles/README.md).

## Acknowledgements

Development assisted by [Claude](https://claude.ai) (Anthropic). MIT licensed.
