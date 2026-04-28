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

- Docker 24+ with Docker Compose v2
- A domain with an A record pointing to your server
- Ports 80 and 443 open (for Let's Encrypt TLS)

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/visionik/gjgit/main/install.sh | sh
```

That's it. The installer checks prerequisites, installs the task runner if needed, then launches an interactive setup wizard that collects your config and deploys the stack — locally, over SSH to any Docker host, or to Fly.io.

> **Already have the repo cloned?** Just run `./install.sh` or `task setup` from the project root.

### What the wizard does

1. Asks which mode: **standalone** (Forgejo + Caddy) or **proxy** (+ gitea-mirror + ghproxy)
2. Prompts for all required config — passwords and secrets are auto-generated if left blank
3. Shows a review screen with secrets masked; lets you edit any field before confirming
4. Writes `.env` and asks where to deploy:
   - **Locally** — `docker compose up -d` right there
   - **SSH** — packages the stack and deploys to any remote Docker host
   - **Fly.io** — uploads secrets and runs `fly deploy`
   - **Bundle** — builds a portable `.tar.gz` for manual deployment

Caddy provisions a Let's Encrypt TLS certificate automatically on first start.  
All bootstrap steps (admin user creation, API token generation, mirror setup) run automatically.

## fly.io admin management

```bash
task fly:admin:create EMAIL=you@example.com         # first-run: create admin with random password
task fly:admin:create USERNAME=viz EMAIL=you@x.com  # custom username
task fly:admin:reset  USERNAME=viz                  # reset password
```

The random password is printed once — save it immediately.

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
