# China VPS Hosting Guide

gjgit is optimised for deployment on Hong Kong / Los Angeles CN2 GIA VPS
servers, which provide the best mainland China latency for GitHub acceleration.

## Why CN2 GIA?

GitHub's servers are primarily US-east. CN2 GIA (China Telecom 2 Global
Internet Access) is a premium backbone route with:
- Direct peering between China Telecom and international carriers
- Typically 100–180ms RTT from major Chinese cities vs 200–400ms+ on BGP
- Less packet loss during peak hours than standard BGP routes

## Recommended VPS providers

| Provider | Location | Network | Notes |
|---|---|---|---|
| DMIT | HK / LAX | CN2 GIA | Best HK latency; LAX good for north China |
| BandwagonHost | LAX / HK | CN2 GIA | Reliable, good value at higher tiers |
| RackNerd | LAX | CN2 GIA | Budget option; verify CN2 GIA specifically |
| Vultr HK | HK | BGP | Not CN2; acceptable but not optimal |

**Always verify CN2 GIA** — providers sometimes change routing tiers.
Test with `traceroute github.com` from within China before committing.

## Recommended specs

- **CPU**: 4+ cores (Forgejo + ghproxy both benefit from concurrency)
- **RAM**: 8+ GB (16 GB for heavy LFS or large repos)
- **Disk**: NVMe SSD, 100 GB+ (ghproxy cache + Forgejo data)
- **Bandwidth**: 1 Gbps port, unmetered or >5 TB/month

## DNS configuration

Use a CDN-free A record pointing directly to your VPS IP:

```
git.yourdomain.ai.  300  IN  A  <VPS_IP>
```

Avoid putting this behind Cloudflare or other CDN proxies — they add latency
and break Let's Encrypt HTTP-01 challenges when proxied.

## Verifying latency from China

From a mainland China machine or via a Chinese proxy/relay:

```bash
# Ping test
ping git.yourdomain.ai

# Traceroute (shows CN2 GIA hops: 59.43.x.x range)
traceroute git.yourdomain.ai

# Git clone speed test
time git clone https://git.yourdomain.ai/owner/repo.git /tmp/test-clone
```

CN2 GIA hops typically show `59.43.*.*` IP ranges — if you see these, CN2 GIA
routing is active.

## Outbound proxy (optional)

If your VPS has poor direct GitHub connectivity, configure ghproxy to route
outbound through a SOCKS5 relay:

```toml
# configs/ghproxy/config.toml
[outbound]
enabled = true
url     = "socks5://127.0.0.1:1080"
```

Then run a SOCKS5 proxy (e.g. `ssh -D 1080 relay-server`) on the VPS host.

## Firewall checklist

```bash
# Required ports
ufw allow 22    # SSH (or your custom SSH port)
ufw allow 80    # HTTP (Let's Encrypt challenge)
ufw allow 443   # HTTPS
ufw allow 2222  # Forgejo SSH (or FORGEJO_SSH_PORT value)
ufw enable
```
