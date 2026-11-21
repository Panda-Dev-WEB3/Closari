#!/usr/bin/env bash
# Deploys Closari on a shared host whose ports 80/443 already belong to the system nginx:
#   1. pinned toolchain (Bun from .bun-version must already be installed; Foundry is installed into $BASE),
#   2. build (site + contracts),
#   3. publish the site to $WEB and install the nginx vhost (+ certbot TLS on first install),
#   4. run the loopback-only anvil devnet as a systemd service and deploy the contracts to it once.
# Usage, from the repository checkout on the host, as a user with sudo:
#   infra/shared-host/deploy.sh <domain>
#   REDEPLOY=1 infra/shared-host/deploy.sh <domain>   # wipe the devnet chain state, then deploy the contracts again
# Re-running is safe: it rebuilds and republishes, and leaves an existing vhost and devnet deployment in place.
# anvil persists its chain in $STATE/state.json, so after a contract change the deployer nonce is already above 0
# and a plain re-run skips the deploy: REDEPLOY=1 resets the devnet and deploys the current contracts.
set -euo pipefail

DOMAIN=${1:?usage: infra/shared-host/deploy.sh <domain>}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BASE=${CLOSARI_BASE:-/opt/closari}
WEB=${CLOSARI_WEB:-/var/www/closari}
PORT=${CLOSARI_DEVNET_PORT:-18545}
FOUNDRY_VERSION=v1.8.1
FOUNDRY_BIN=$BASE/toolchain/foundry/bin
STATE=$BASE/devnet
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 # anvil test account 0 (public key)
REDEPLOY=${REDEPLOY:-0}
export PATH=$FOUNDRY_BIN:$HOME/.bun/bin:$PATH

log() { printf '\n== %s\n' "$*"; }
wait_rpc() {
  for _ in $(seq 30); do cast block-number --rpc-url "$1" >/dev/null 2>&1 && break; sleep 1; done
  cast block-number --rpc-url "$1" >/dev/null
}

log "toolchain"
want_bun=$(cat "$REPO/.bun-version")
[ "$(bun --version)" = "$want_bun" ] || { echo "Bun $want_bun is required (found $(bun --version))"; exit 1; }
if ! "$FOUNDRY_BIN/forge" --version 2>/dev/null | grep -q "${FOUNDRY_VERSION#v}"; then
  mkdir -p "$FOUNDRY_BIN"
  curl -fsSL "https://github.com/foundry-rs/foundry/releases/download/$FOUNDRY_VERSION/foundry_${FOUNDRY_VERSION}_linux_amd64.tar.gz" |
    tar -xz -C "$FOUNDRY_BIN" forge cast anvil
fi
forge --version | head -1

log "build"
cd "$REPO"
git submodule update --init --recursive
bun install --frozen-lockfile
bun run site:build
(cd contracts && forge build)

log "site -> $WEB"
sudo install -d -m 755 "$WEB"
sudo rsync -a --delete "$REPO/apps/site/dist/" "$WEB/"

SITE=/etc/nginx/sites-available/closari
if [ -e "$SITE" ]; then
  echo "vhost $SITE exists (certbot-managed); left unchanged"
else
  log "nginx vhost for $DOMAIN"
  sed -e "s|__DOMAIN__|$DOMAIN|g" -e "s|__WEB__|$WEB|g" "$REPO/infra/shared-host/nginx-closari.conf" | sudo tee "$SITE" >/dev/null
  sudo ln -s "$SITE" /etc/nginx/sites-enabled/closari
  if ! sudo nginx -t; then
    sudo rm -f /etc/nginx/sites-enabled/closari "$SITE"
    echo "nginx -t failed; vhost removed"; exit 1
  fi
  sudo systemctl reload nginx
  sudo certbot --nginx -d "$DOMAIN" --non-interactive --redirect
fi

log "devnet on 127.0.0.1:$PORT"
install -d -m 700 "$STATE"
sed -e "s|__USER__|$(id -un)|g" -e "s|__ANVIL__|$FOUNDRY_BIN/anvil|g" -e "s|__PORT__|$PORT|g" -e "s|__STATE__|$STATE|g" \
  "$REPO/infra/shared-host/closari-devnet.service" | sudo tee /etc/systemd/system/closari-devnet.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now closari-devnet
RPC=http://127.0.0.1:$PORT
wait_rpc "$RPC"

if [ "$REDEPLOY" = "1" ]; then
  log "REDEPLOY=1: reset the devnet chain state"
  sudo systemctl stop closari-devnet
  rm -f "$STATE/state.json"
  sudo systemctl start closari-devnet
  wait_rpc "$RPC"
fi

if [ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC")" = "0" ]; then
  log "deploy contracts (DeployLocal: real LMSRMarket, mock pool/oracle/router)"
  (cd contracts && CLOSARI_LOCAL_DEPLOY=true forge script script/DeployLocal.s.sol --rpc-url "$RPC" --broadcast --sender "$DEPLOYER" --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80) |
    tee "$STATE/deploy.log"
else
  echo "devnet already deployed (deployer nonce > 0); see $STATE/deploy.log. REDEPLOY=1 resets it and deploys again."
fi

log "done: https://$DOMAIN  devnet $RPC"
