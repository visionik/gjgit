# Scaling

gjgit ships as a single-VPS stack. This document covers scaling options
for deployments that outgrow a single node.

## Single-node vertical scaling

Before adding nodes, exhaust vertical options:

1. **More RAM** — Forgejo and ghproxy both benefit. 16–32 GB covers most workloads.
2. **NVMe disk** — ghproxy throughput is disk-bound for large file caching.
3. **CPU** — Go services (ghproxy) are highly concurrent; more cores help.

## Multi-node: separate ghproxy

For >10k daily git operations, run ghproxy on a dedicated node:

```yaml
# docker-compose.override.yml on the proxy node
services:
  ghproxy:
    ports:
      - "8080:8080"
```

Then update Caddy on the main node to point to the external IP:

```caddy
handle @git_paths {
    reverse_proxy <ghproxy-node-ip>:8080
}
```

## Load balancing multiple ghproxy instances

Caddy supports round-robin load balancing natively:

```caddy
handle @git_paths {
    reverse_proxy ghproxy-1:8080 ghproxy-2:8080 ghproxy-3:8080 {
        lb_policy       round_robin
        health_uri      /
        health_interval 15s
    }
}
```

Each ghproxy instance maintains its own disk cache. For cache consistency,
either use a shared NFS/NVMe mount for the cache volume, or accept that
cache miss rates will be higher with multiple nodes.

## Backup strategy

Forgejo data lives in the `forgejo_data` named volume. Back it up regularly:

```bash
# Stop Forgejo gracefully
docker compose stop forgejo

# Export volume to a tarball
docker run --rm \
  -v gjgit_forgejo_data:/data:ro \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/forgejo-$(date +%Y%m%d).tar.gz -C / data

# Restart Forgejo
docker compose start forgejo
```

Automate with cron: `0 3 * * * /path/to/backup-forgejo.sh`

## Upgrade procedure

```bash
# 1. Pull updated images
task pull

# 2. Recreate containers with new images (rolling restart)
task up           # or task up:proxy

# 3. Verify health
task ps
task logs SERVICE=forgejo
```

Forgejo upgrades are generally in-place safe — the data volume is preserved.
Always check the [Forgejo changelog](https://codeberg.org/forgejo/forgejo/releases)
for breaking changes before upgrading across major versions.

## Kubernetes (future)

A Helm chart for Kubernetes deployment is on the gjgit roadmap. In the
meantime, all services can be deployed as Kubernetes Deployments with
PersistentVolumeClaims replacing the named Docker volumes.
