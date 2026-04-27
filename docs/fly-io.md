# fly.io Deployment Guide

gjgit deploys to fly.io as a multi-container Fly Machine. fly.io handles
TLS at the edge; Caddy runs HTTP-only internally and routes traffic to
Forgejo (and ghproxy in proxy mode).

## Architecture

```
Internet → fly.io edge (HTTPS/TLS) → Caddy :80 → Forgejo :3000
                                              ↘ ghproxy :8080  (proxy mode)
```

All services run on a single Fly Machine. Service names (`forgejo`, `ghproxy`)
resolve via `/etc/hosts` injection. Data persists on Fly volumes mounted at
`/mnt/` paths.

## Prerequisites

```bash
# Install flyctl
brew install flyctl   # macOS

# Authenticate
fly auth login
```

flyctl v0.3.147+ is required for native compose support (v0.4.x recommended).

## One-time setup

Run once per Fly account before the first deploy:

```bash
# Standalone mode (Forgejo + Caddy)
task fly:bootstrap

# Proxy/mirror mode (adds ghproxy_cache volume)
task fly:bootstrap:proxy
```

This creates:
- The `gjgit` Fly app
- Persistent volumes: `forgejo_data` (10GB), `caddy_data` (1GB), `shared_token` (1GB)
- Proxy mode also creates: `ghproxy_cache` (20GB)
- A dedicated public IPv4 address

Customize the app name or region by setting env vars:

```bash
FLY_APP=my-git-server FLY_REGION=lax task fly:bootstrap
```

## Configure secrets

gjgit uses Fly secrets instead of a `.env` file on the server. Create `.env`
locally from the template, fill it in, then upload:

```bash
cp .env.example .env
# Edit .env — set DOMAIN, credentials, GitHub token, etc.

task secrets:fly   # Uploads to Fly; never commits to git
```

Secrets are injected as environment variables into the Fly Machine at runtime.
Re-run `task secrets:fly` whenever `.env` changes, then re-deploy.

**Important**: Set `DOMAIN` to your Fly app's hostname (e.g. `gjgit.fly.dev`)
or your custom domain. Forgejo uses `FLY_APP_NAME.fly.dev` automatically if
`DOMAIN` is not set, but set it explicitly for custom domains.

## Deploy

```bash
# Standalone mode (Forgejo + Caddy only)
task deploy:fly

# Proxy/mirror mode (+ gitea-mirror + ghproxy)
task deploy:fly:proxy
```

`fly deploy` builds images, uploads compose config, and starts the Machine.
First deploy takes ~3-5 minutes as images are pulled. Subsequent deploys
are faster (~1 min).

## Verify the deployment

```bash
task fly:smoke          # E2E check: Forgejo health, token file, admin user
task fly:smoke:proxy    # Also checks gitea-mirror (proxy mode)
```

The smoke test verifies:
1. Forgejo responds at `https://gjgit.fly.dev/api/v1/version`
2. Bootstrap wrote the token file to `/mnt/shared_token/forgejo-token`
3. Forgejo admin user was created

## Operations

```bash
task fly:status     # Machine status + running processes
task fly:logs       # Tail logs (all containers)
task fly:ssh        # Interactive shell on the Machine

# Filter logs by container
APP=gjgit fly logs  # all
fly ssh console --app gjgit --command "docker logs gjgit-forgejo"
```

## Custom domain

1. Add a CNAME or A record pointing your domain to the Fly app:
   ```
   git.yourdomain.ai.  300  IN  CNAME  gjgit.fly.dev.
   ```
2. Add the domain to your Fly app:
   ```bash
   fly certs add git.yourdomain.ai --app gjgit
   ```
3. Update `.env`: set `DOMAIN=git.yourdomain.ai`
4. Re-upload secrets and redeploy:
   ```bash
   task secrets:fly && task deploy:fly
   ```

fly.io provisions a Let's Encrypt cert automatically once DNS propagates.

## SSH access to Forgejo

Fly.io doesn't proxy arbitrary TCP by default. To enable Forgejo SSH on port 2222:

1. Uncomment the `[[services]]` block in `fly.toml`:
   ```toml
   [[services]]
     protocol      = "tcp"
     internal_port = 22
     [[services.ports]]
       port = 2222
   ```
2. Redeploy: `task deploy:fly`
3. Clone via SSH: `git clone ssh://git@gjgit.fly.dev:2222/user/repo.git`

## Upgrading

```bash
task deploy:fly       # Pulls latest images and redeploys in-place
```

Forgejo data (git repos, users, DB) persists on the Fly volume across redeploys.
Check the [Forgejo changelog](https://codeberg.org/forgejo/forgejo/releases)
before upgrading across major versions.

## Cost estimate (HKG region, April 2026)

| Resource | Size | $/month (approx) |
|---|---|---|
| performance-2x VM (standalone) | 2 vCPU / 4GB | ~$62 |
| performance-4x VM (proxy mode) | 4 vCPU / 8GB | ~$124 |
| forgejo_data volume | 10GB | ~$1.50 |
| caddy_data volume | 1GB | ~$0.15 |
| shared_token volume | 1GB | ~$0.15 |
| ghproxy_cache volume (proxy) | 20GB | ~$3.00 |
| Dedicated IPv4 | — | ~$2.00 |

Fly.io pricing: https://fly.io/docs/about/pricing/

## Troubleshooting

**Machine won't start**: Check `task fly:logs`. Common cause: missing secrets
(run `task secrets:fly`) or volume mount permission issue.

**Forgejo shows wrong clone URLs**: Set `DOMAIN` in `.env` to your actual
domain and redeploy.

**Bootstrap didn't create admin**: The `bootstrap` container runs after
Forgejo is healthy. Check logs: `fly ssh console --app gjgit --command
"cat /tmp/bootstrap.log 2>/dev/null || echo no log"`. Re-run manually:
`fly ssh console --app gjgit --command "sh /scripts/bootstrap.sh"`.

**Caddy can't route to forgejo**: In the Fly multi-container environment,
`forgejo` resolves to `127.0.0.1` via `/etc/hosts`. Confirm with:
`fly ssh console --app gjgit --command "cat /etc/hosts"`.

**fly deploy fails with compose parse error**: Ensure flyctl >= v0.3.147.
Update with `brew upgrade flyctl`.
