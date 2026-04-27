# gjgit

[![CI](https://github.com/openclaw/gjgit/actions/workflows/ci.yml/badge.svg)](https://github.com/openclaw/gjgit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Turnkey GitHub mirror + Forgejo self-hosting stack.**  
Deploy a fully functional, HTTPS-enabled git hosting instance in under 5 minutes — or mirror any GitHub repo with caching and acceleration for China-first latency.

## Modes

| Mode | Command | Services |
|---|---|---|
| **Standalone** | `docker compose up -d` | Forgejo + Caddy (TLS) |
| **Proxy/Mirror** | `docker compose --profile proxy up -d` | + ghproxy + gitea-mirror |

## Prerequisites

- Docker 24+ and Docker Compose v2
- A domain with an A record pointing to your VPS
- Port 80 and 443 open on the VPS (for Let's Encrypt)

## Quickstart — 5 minutes

```bash
# 1. Clone the repo
git clone https://github.com/openclaw/gjgit.git && cd gjgit

# 2. Configure
cp .env.example .env
# Edit .env: set DOMAIN, LETSENCRYPT_EMAIL, admin credentials
# For proxy mode: also set GITHUB_REPO and GITHUB_TOKEN

# 3. Start
docker compose up -d                             # Standalone
docker compose --profile proxy up -d            # Proxy / mirror mode

# 4. Point your domain's A record to this VPS IP — done.
```

Caddy provisions a Let's Encrypt TLS certificate automatically on first start.  
The admin account is created from `.env` credentials — no manual web UI signup needed.

## First-run: admin user setup

**Local docker compose** — handled automatically:

```bash
task up              # starts Forgejo + Caddy
task bootstrap       # creates admin + generates API token (proxy mode)
```

Admin credentials come from `.env` (`GITEA_ADMIN_USERNAME`, `GITEA_ADMIN_PASSWORD`).  
> **Note**: `admin` is a reserved username in Forgejo. Use `gitadmin`, your name, etc.

**fly.io** — one task after deploy:

```bash
task deploy:fly
task fly:admin:create EMAIL=you@example.com         # creates 'gitadmin' with random password
task fly:admin:create USERNAME=viz EMAIL=you@x.com  # or with a custom username
task fly:admin:reset  USERNAME=viz                  # reset password later if needed
```

The random password is printed once — save it immediately. Change it at  
https://gjgit.fly.dev/user/settings/security

## SSH access

Forgejo SSH is exposed on `FORGEJO_SSH_PORT` (default `2222`):

```bash
# Clone via SSH
git clone ssh://git@yourdomain.ai:2222/owner/repo.git

# Or add to ~/.ssh/config
Host gjgit
  HostName yourdomain.ai
  Port 2222
  User git
```

## Configuration reference

See [`.env.example`](.env.example) — every variable is documented inline.

Key variables:

| Variable | Description | Default |
|---|---|---|
| `DOMAIN` | Your domain | — |
| `LETSENCRYPT_EMAIL` | TLS cert email | — |
| `FORGEJO_SSH_PORT` | Forgejo SSH host port | `2222` |
| `GITEA_ADMIN_PASSWORD` | Admin password **(change this!)** | — |
| `GITHUB_REPO` | Repo/org to mirror (proxy mode) | — |
| `GITHUB_TOKEN` | GitHub PAT (proxy mode) | — |
| `MIRROR_INTERVAL` | Sync cadence | `15m` |
| `GH_PROXY_CACHE_SIZE` | ghproxy disk cache | `20G` |

## Task runner

```bash
task              # List all tasks
task up           # Start standalone
task up:proxy     # Start proxy mode
task down         # Stop (volumes preserved)
task logs         # Tail logs (SERVICE=forgejo to filter)
task check        # Lint + unit tests
task test         # Unit + integration tests
task bootstrap    # Re-run first-run bootstrap
```

## Upgrading

```bash
task pull         # Pull latest images
task up           # Restart with new images
```

## Troubleshooting

**Let's Encrypt rate limits**: Use `acme_ca https://acme-staging-v02.api.letsencrypt.org/directory` in your Caddyfile for testing. Remove it for production.

**Port 80 blocked**: Let's Encrypt HTTP-01 challenge requires port 80. Check your VPS firewall (`ufw allow 80`).

**Forgejo not starting**: Check logs with `task logs SERVICE=forgejo`. Common cause: `USER_UID`/`USER_GID` mismatch with volume ownership.

**gitea-mirror not syncing**: Check that `GITHUB_TOKEN` has `repo` scope and `GITHUB_REPO` is in `owner/repo` format.

## Docs

- [High-volume configuration](docs/high-volume.md)
- [China VPS hosting guide](docs/china-hosting.md)
- [Scaling beyond a single VPS](docs/scaling.md)

## License

MIT — see [LICENSE](LICENSE).
