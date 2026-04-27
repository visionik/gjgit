# High-Volume Configuration

gjgit is designed to handle high-traffic workloads — this guide covers tuning
for deployments serving hundreds to thousands of daily git operations.

## Recommended specs (>1k daily clones)

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 8+ cores |
| RAM | 4 GB | 16+ GB |
| Disk | 50 GB SSD | 200 GB+ NVMe |
| Network | 100 Mbps | 1 Gbps+ |

## ghproxy tuning (`configs/ghproxy/config.toml`)

### Rate limiting

Increase `ratePerMinute` and `burst` for high-volume deployments:

```toml
[rateLimit]
enabled       = true
ratePerMinute = 6000   # 100 rps per IP
burst         = 600

  [rateLimit.bandwidthLimit]
  enabled     = true
  totalLimit  = "1gbps"
  totalBurst  = "1gbps"
  singleLimit = "200mbps"
  singleBurst = "200mbps"
```

### Connection pooling

For high concurrency, increase the HTTP client pool:

```toml
[httpc]
mode                = "auto"
maxIdleConns        = 500
maxIdleConnsPerHost = 200
```

### Git clone caching (Smart-Git)

gjgit ships with Smart-Git enabled in proxy mode. The `smart-git` service
caches git bare repos locally so repeat `git clone`/`git fetch` operations
are served from disk rather than round-tripping to GitHub.

**Cache behaviour:**
- Git objects (blobs, trees, commits) are immutable — cached safely forever
- TTL: 5m before checking upstream ref advertisement
- If upstream ref is unchanged: extends cache by `expireEx` (15m) without re-fetching
- If upstream ref changed: re-fetches only the new objects
- Force-pushed branches: stale objects may be served within the 5m TTL window
- **Public repos only**: auth tokens are not forwarded to Smart-Git

**Disk usage warning:** Smart-Git has no LRU eviction policy. Monitor
`smart_git_cache` volume size — once disk is full, new repos cannot be cached.
Manually prune stale repos by removing entries from `/data/smart-git/repos/`
inside the `smart-git` container.

Tune the TTL in `configs/smart-git/config.toml`:

```toml
[cache]
expire   = "5m"    # Lower = fresher, higher = fewer upstream checks
expireEx = "15m"   # Extension when upstream hash is unchanged
```

View cached repos:

```bash
docker exec gjgit-smart-git curl -s http://localhost:8080/api/db/data
```

## Forgejo tuning

For high-read workloads, configure Forgejo's LFS and cache:

1. Edit `forgejo_data/gitea/conf/app.ini` after first run:

```ini
[cache]
ENABLED    = true
ADAPTER    = memory
ITEM_TTL   = 16h

[lfs]
PATH = /data/gitea/lfs
```

2. Restart: `task restart`

## Monitoring with docker stats

wjqserver/ghproxy does not expose Prometheus metrics natively. Use
`docker stats` or a cAdvisor sidecar for container-level metrics:

```bash
docker stats gjgit-ghproxy gjgit-forgejo gjgit-caddy
```

To add cAdvisor for Grafana integration, see the
[cAdvisor quick-start](https://github.com/google/cadvisor#quick-start-running-cadvisor-in-a-docker-container).

## Scaling beyond one container

For >10k daily clones, run multiple ghproxy instances behind Caddy:

```caddy
@git_paths { path_regexp git \.git(/.*)?$ }
handle @git_paths {
    reverse_proxy ghproxy-1:8080 ghproxy-2:8080 {
        lb_policy round_robin
    }
}
```

See [scaling.md](scaling.md) for multi-node deployment.
