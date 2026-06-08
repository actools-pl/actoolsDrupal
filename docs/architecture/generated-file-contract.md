# Generated File Contract

## Purpose

Generated files are the highest-risk part of Phase 0 because a harmless-looking refactor can change YAML, Caddy, DB config, Docker images, or the operator CLI.

## Files covered

- `docker-compose.yml`
- `Caddyfile`
- `my.cnf`
- Dockerfiles
- `/usr/local/bin/actools`
- generated env files
- generated backup/cron/systemd helper files, if present

## Golden fixture naming

Recommended:

````text
tests/fixtures/golden/community/default/docker-compose.yml
tests/fixtures/golden/community/default/Caddyfile
tests/fixtures/golden/community/default/my.cnf
tests/fixtures/golden/community/default/actools-cli
````

For mode variants:

````text
tests/fixtures/golden/community/redis-enabled/
tests/fixtures/golden/community/s3-enabled/
tests/fixtures/golden/community/all-in-one/
tests/fixtures/golden/community/cadvisor-enabled/
````

## Golden comparison rule

A phase that changes generation logic must state one of:

- **Unchanged:** generated output matches golden fixtures.
- **Changed intentionally:** generated output differs and the release note explains why.
- **Changed unexpectedly:** phase fails.

## Required validation

At minimum:

````bash
bash -n actools.sh
bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
````

Where available:

````bash
shellcheck actools.sh cli/actools installer/*.sh core/*.sh modules/**/*.sh
bats tests
````

Runtime validators where available:

````bash
docker compose config
caddy validate --config Caddyfile
````

## Prohibited shortcuts

- Do not reformat generated YAML without a release note.
- Do not change Caddy security headers accidentally.
- Do not move secrets from env/defaults files into process arguments.
- Do not convert heredocs to echo chains.
- Do not patch generated and static CLI independently.

