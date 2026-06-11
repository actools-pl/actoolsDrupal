# Privacy & Data Policy

## AI Assistant *(experimental — not shipped)*

> The `actools ai` command is **not** registered in the CLI today; the code under `modules/ai/` is not wired in. The properties below describe the **intended** design for if/when it ships.

The planned Actools AI assistant (`actools ai`) is designed to run entirely on your server.

- **Local only** — powered by [Ollama](https://ollama.ai) running inside Docker
- **No external calls** — zero data sent to any external API
- **No telemetry** — no usage data, no analytics, no phone-home
- **No cloud dependency** — works without internet after initial model download
- **Your code stays on your server** — always

The assistant would have read access to your codebase context only — no file modification, command execution, or credential access.

## Installer

The `actools.sh` installer script:

- Makes outbound calls only to: GitHub, packages.drupal.org, hub.docker.com
  (standard package downloads during install), and ifconfig.me
  (one-time public-IP lookup for DNS preflight check)
- Does not send server configuration, credentials, or site data to any maintainer or external server
- Does not install any monitoring agents or callbacks
- Is fully open source — every line readable at github.com/actools-pl/actoolsDrupal

## Summary

Your server → external servers   NEVER
Your code   → external API       NEVER
Your data   → anywhere           NEVER

Questions: open an issue at https://github.com/actools-pl/actoolsDrupal/issues
