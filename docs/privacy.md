# Privacy & Data Policy

## AI Assistant

The Actools AI assistant (`actools ai`) runs entirely on your server.

- **Local only** — powered by [Ollama](https://ollama.ai) running inside Docker
- **No external calls** — zero data sent to any external API
- **No telemetry** — no usage data, no analytics, no phone-home
- **No cloud dependency** — works without internet after initial model download
- **Your code stays on your server** — always

The AI has read access to your codebase context only. It cannot modify files,
execute commands, or access credentials.

## Installer

The `actools.sh` installer script:

- Makes outbound calls only to: GitHub, packages.drupal.org, hub.docker.com
  (standard package downloads during install)
- Does not send server configuration, credentials, or site data to feesix.com
- Does not install any monitoring agents or callbacks
- Is fully open source — every line readable at github.com/actools-pl/actoolsDrupal

## Summary

Your server → feesix.com     NEVER
Your code   → external API   NEVER
Your data   → anywhere       NEVER

Questions: hello@feesix.com
