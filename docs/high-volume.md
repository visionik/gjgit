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

### Git clone caching (advanced)

wjqserver/ghproxy supports git clone caching via the
[Smart-Git](https://github.com/WJQSERVER-STUDIO/smart-git) sidecar.
Enable it by setting `[gitclone] mode = "cache"` and adding Smart-Git as
an additional service. This is not included in gjgit v1 but is documented
in the ghproxy project for v2 consideration.

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
