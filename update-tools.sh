#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MANAGER_URL="${GATEWAY_MANAGER_URL:-https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/gateway-manager.sh}"
REQUESTED_DIR="${INSTALL_DIR:-${1:-}}"

die() { printf "%b\n" "${RED}ERROR${NC} $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo bash update-tools.sh"

if [[ -z "$REQUESTED_DIR" && -f /etc/ar-io-gateway.conf ]]; then
  REQUESTED_DIR="$(sed -n 's/^INSTALL_DIR=//p' /etc/ar-io-gateway.conf | tail -n1)"
fi

if [[ -z "$REQUESTED_DIR" ]]; then
  for candidate in /opt/ar-io-node /opt/ar-io-gateway "$PWD"; do
    if [[ -f "$candidate/.env" && -f "$candidate/docker-compose.yaml" ]]; then
      REQUESTED_DIR="$candidate"
      break
    fi
  done
fi

[[ -n "$REQUESTED_DIR" && -f "$REQUESTED_DIR/.env" && -f "$REQUESTED_DIR/docker-compose.yaml" ]] || \
  die "Could not find ar-io-node. Pass its path: sudo bash update-tools.sh /opt/ar-io-node"

printf "%b\n" "${YELLOW}Updating gateway helper commands...${NC}"
printf "Gateway directory: %b%s%b\n" "$CYAN" "$REQUESTED_DIR" "$NC"

temp="$(mktemp)"
trap 'rm -f "$temp"' EXIT
curl -fsSL "$MANAGER_URL" -o "$temp"
bash -n "$temp"

install -d -m 755 /usr/local/lib/ar-io-gateway
install -m 755 "$temp" /usr/local/lib/ar-io-gateway/manager.sh
INSTALL_DIR="$REQUESTED_DIR" /usr/local/lib/ar-io-gateway/manager.sh install-links "$REQUESTED_DIR"

printf "%b\n" "${GREEN}Gateway helper commands are up to date.${NC}"
echo "Run: gateway-help"
