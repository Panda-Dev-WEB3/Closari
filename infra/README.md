# Closari on the OVH VPS

Nothing here runs until someone with access does the steps below. M1 serves only the static site; services join in M4–M6.

## One-time VPS setup (Ubuntu 24.04+)

1. Create a non-root `deploy` user with SSH-key login only:
   `adduser --disabled-password deploy && install -d -m 700 -o deploy -g deploy /home/deploy/.ssh`, then write the CI deploy public key to `/home/deploy/.ssh/authorized_keys` and run `chown deploy:deploy /home/deploy/.ssh/authorized_keys && chmod 600 /home/deploy/.ssh/authorized_keys` (sshd's StrictModes rejects looser ownership or modes). In `/etc/ssh/sshd_config` set `PasswordAuthentication no` and `PermitRootLogin no`, then `systemctl reload ssh`.
   **Before reloading sshd or enabling ufw, confirm in a second terminal that a new SSH login as `deploy` works, and keep the root session open until then.**
2. Firewall: `ufw default deny incoming && ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 443/udp && ufw enable`.
3. Updates and brute-force protection: `apt install unattended-upgrades fail2ban && dpkg-reconfigure -plow unattended-upgrades`.
4. Docker Engine + Compose plugin from Docker's apt repository; add `deploy` to the `docker` group.
5. `mkdir -p /srv/closari/site /srv/closari/infra && chown -R deploy: /srv/closari`.
6. Copy `infra/docker-compose.yml`, `infra/Caddyfile` and an `infra/.env` (from `.env.example`, with the real domain) to `/srv/closari/infra/`.
7. Point the domain's A/AAAA records at the VPS, then `cd /srv/closari/infra && docker compose up -d`. Caddy obtains TLS automatically.

## Deploying the site

GitHub → Actions → `deploy-site` → Run workflow. It needs these repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `VPS_HOST` | VPS hostname or IP |
| `VPS_USER` | `deploy` |
| `VPS_SSH_KEY` | private key whose public half is in `deploy`'s `authorized_keys` |
| `VPS_KNOWN_HOSTS` | output of `ssh-keyscan -t ed25519 <VPS_HOST>` (pins the host key) |

The workflow builds `apps/site`, rsyncs `dist/` to `/srv/closari/site/` and reloads Caddy. Roll back by re-running it on an earlier commit.

## Later milestones

Postgres 16 + TimescaleDB, Redis, keeper, Hermes fetcher, indexer, API and MCP are added to `docker-compose.yml` in M4–M6 with images pinned by digest. Keeper and Hermes secrets live only in the VPS environment, never in the repo (Backend §10).
