# Changelog

All notable changes to gjgit will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## [Unreleased]

### Added
- Project scaffold: directory layout, Taskfile.yml, .gitignore, CHANGELOG.md, .env.example (all vars documented), secrets/ templates
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
