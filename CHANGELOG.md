# Changelog

All notable changes to gjgit will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## [Unreleased]

### Added
- Smart-Git git clone caching for proxy mode (`wjqserver/smart-git:latest`, Go version)
  - `configs/smart-git/config.toml`: 5m TTL + upstream hash check; `expireEx=15m` for stable repos
  - `docker-compose.yml`: `smart-git` service under proxy profile; `smart_git_cache` named volume
  - `ghproxy` switches from `mode=bypass` to `mode=cache` with `smartGitAddr=http://smart-git:8080`
  - `tests/integration/proxy.sh`: smart-git health check + cache population assertion + HEAD SHA correctness check

### Notes
- Smart-Git cache invalidation: TTL-based (5m) with upstream hash check on expiry. New commits visible within 5m.
  Force-pushed branches may serve stale objects within the 5m window. Public repos only (no auth forwarding).
- No disk eviction/LRU policy: monitor `smart_git_cache` volume usage; named volume size is the only limit.
- **Migration**: existing proxy deployments must `docker compose --profile proxy pull && docker compose --profile proxy up -d`
  to start the new `smart-git` container. ghproxy will fail to start until smart-git is healthy.

### Added
- fly.io deployment support (native multi-container Fly Machines via `[build] compose`)
  - `fly.toml` (standalone) + `fly-proxy.toml` (proxy/mirror mode), HKG region, persistent volumes
  - `docker-compose.fly.yml` + `docker-compose.fly-proxy.yml` — fly-adapted compose files (no env_file, /mnt/ volume paths, HTTP-only Caddy)
  - `Caddyfile.fly` — HTTP-only Caddyfile (fly.io handles TLS at edge)
  - `scripts/fly-bootstrap.sh` — idempotent one-time app + volume + IP setup
  - `scripts/fly-secrets.sh` — imports .env as fly secrets
  - `scripts/fly-smoke.sh` — E2E verification: Forgejo health, bootstrap token, admin user
  - Taskfile fly tasks: `fly:bootstrap`, `secrets:fly`, `deploy:fly`, `deploy:fly:proxy`, `fly:ssh`, `fly:logs`, `fly:status`, `fly:smoke`
  - `docs/fly-io.md` — full deployment guide (setup, deploy, custom domain, SSH, cost, troubleshooting)
- `flyctl` v0.4.40 added as dev dependency (install: `brew install flyctl`)
- Project scaffold: Taskfile.yml, .gitignore, CHANGELOG.md, .env.example, secrets/ templates
- `docker-compose.yml`: standalone (Forgejo + Caddy) and proxy (+ gitea-mirror + ghproxy) profiles
- `Caddyfile`: automatic HTTPS + HTTP/3 via Let's Encrypt; inline proxy mode routing block
- `scripts/bootstrap.sh`: idempotent first-run admin user creation and API token generation from env vars
- `configs/ghproxy/config.toml`: wjqserver/ghproxy TOML config (rate limiting, connection pooling)
- `tests/unit/bootstrap.bats`: bats-core unit tests for bootstrap.sh (5 test cases)
- `tests/integration/standalone.sh` + `proxy.sh`: docker compose integration tests
- `.github/workflows/ci.yml`: GitHub Actions CI (lint + unit tests + compose validation + integration)
- `README.md`: 5-minute deploy guide, mode table, SSH instructions, troubleshooting
- `docs/high-volume.md`, `docs/china-hosting.md`, `docs/scaling.md`: operational guides
- `LICENSE`: MIT
- `vbrief/`: project definition, specification, and 6 scope vBRIEFs (all completed)
- `.github/PULL_REQUEST_TEMPLATE.md`: deft PR template

### Notes
- wjqserver/ghproxy does not expose Prometheus metrics (unlike LZUOSS/gh-proxy in original spec); use `docker stats` or cAdvisor for container metrics

## [0.1.0] - TBD

Initial release.
