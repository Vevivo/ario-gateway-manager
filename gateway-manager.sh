#!/usr/bin/env bash
set -Eeuo pipefail

# Runtime manager for Vevivo's AR.IO gateway tools.
# It is installed at /usr/local/lib/ar-io-gateway/manager.sh and exposed
# through memorable gateway-* command symlinks.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_FILE="${GATEWAY_CONFIG_FILE:-/etc/ar-io-gateway.conf}"
MANAGER_URL="${GATEWAY_MANAGER_URL:-https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/gateway-manager.sh}"
TEST_TX="3lyxgbgEvqNSvJrTX2J7CfRychUD5KClFhhVLyTPNCQ"
INSTALL_DIR="${INSTALL_DIR:-}"

info() { printf "%b\n" "${CYAN}==>${NC} $*"; }
pass() { printf "%b\n" "${GREEN}OK${NC} $*"; }
warn() { printf "%b\n" "${YELLOW}WARN${NC} $*"; }
fail() { printf "%b\n" "${RED}FAIL${NC} $*" >&2; }
die() { fail "$*"; exit 1; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run this command as root (sudo)."
}

prompt() {
  local label="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$label" "$default" >&2
    read -r value
    printf "%s" "${value:-$default}"
  else
    printf "%s: " "$label" >&2
    read -r value
    printf "%s" "$value"
  fi
}

confirm() {
  local label="$1"
  local default="${2:-n}"
  local suffix="[y/N]"
  local value
  [[ "$default" == "y" ]] && suffix="[Y/n]"
  printf "%s %s: " "$label" "$suffix" >&2
  read -r value
  value="${value:-$default}"
  value="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "y" || "$value" == "yes" || "$value" == "e" || "$value" == "evet" ]]
}

read_config_value() {
  local key="$1"
  [[ -f "$CONFIG_FILE" ]] || return 0
  sed -n "s/^${key}=//p" "$CONFIG_FILE" | tail -n1
}

resolve_install_dir() {
  if [[ -n "$INSTALL_DIR" && -f "$INSTALL_DIR/.env" ]]; then
    return
  fi

  INSTALL_DIR="$(read_config_value INSTALL_DIR)"
  if [[ -n "$INSTALL_DIR" && -f "$INSTALL_DIR/.env" ]]; then
    return
  fi

  local candidate
  for candidate in /opt/ar-io-gateway /opt/ar-io-node "$PWD"; do
    if [[ -f "$candidate/.env" && -f "$candidate/docker-compose.yaml" ]]; then
      INSTALL_DIR="$candidate"
      return
    fi
  done
  die "Could not locate the ar-io-node directory. Set INSTALL_DIR=/path/to/ar-io-node."
}

get_env() {
  local key="$1"
  [[ -f "$INSTALL_DIR/.env" ]] || return 0
  sed -n "s/^${key}=//p" "$INSTALL_DIR/.env" | tail -n1
}

backup_env() {
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "$INSTALL_DIR/.env" "$INSTALL_DIR/.env.backup.${stamp}"
}

set_env() {
  local key="$1"
  local value="$2"
  [[ "$key" =~ ^[A-Z0-9_]+$ ]] || die "Invalid environment key: $key"
  [[ "$value" != *$'\n'* ]] || die "Environment values cannot contain newlines."

  local temp
  temp="$(mktemp "$INSTALL_DIR/.env.tmp.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { found=0 }
    $0 ~ "^" key "=" {
      if (!found) print key "=" value
      found=1
      next
    }
    { print }
    END { if (!found) print key "=" value }
  ' "$INSTALL_DIR/.env" > "$temp"
  chmod 600 "$temp"
  mv "$temp" "$INSTALL_DIR/.env"
}

remove_env() {
  local key="$1"
  local temp
  temp="$(mktemp "$INSTALL_DIR/.env.tmp.XXXXXX")"
  awk -v key="$key" '$0 !~ "^" key "=" { print }' "$INSTALL_DIR/.env" > "$temp"
  chmod 600 "$temp"
  mv "$temp" "$INSTALL_DIR/.env"
}

domain() {
  get_env ARNS_ROOT_HOST
}

compose() {
  (cd "$INSTALL_DIR" && docker compose "$@")
}

redact_url() {
  sed -E 's#(api-key=)[^& ]+#\1***#g; s#(token=)[^& ]+#\1***#g'
}

wait_for_local_health() {
  local attempts="${1:-24}"
  local i
  for ((i=1; i<=attempts; i++)); do
    if curl -fsS --max-time 5 http://127.0.0.1:3000/ar-io/healthcheck >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

cmd_help() {
  cat <<'HELP'
ar.io Gateway commands

Daily operations
  gateway                 Open the interactive operator menu
  gateway-check           Test public data, node info, observer, and Docker
  gateway-doctor          Run a complete read-only diagnostic report
  gateway-status          Show services, resources, disk, and inode usage
  gateway-logs            Follow core, observer, and envoy logs
  gateway-release-check   Compare the running node with the latest release
  gateway-update          Safely update ar-io-node from the stable main branch
  gateway-restart         Recreate services without deleting persistent data

Storage and TLS
  gateway-storage         Show cache protection and disk status
  gateway-storage-setup   Configure indexed or TTL 90% -> 85% protection
  gateway-cert-check      Show certificate expiry and renewal method
  gateway-cert-setup      Configure unattended Cloudflare/Namecheap renewal
  gateway-cert-manual     Renew with guided Namecheap TXT records while live
  gateway-renew-cert      Renew an automatic DNS-API certificate

Observer and optional features
  gateway-balance         Check a Solana wallet balance
  gateway-network-info    Read on-chain gateway status through @ar.io/sdk
  gateway-network-readiness Check domain, TLS, data, and wallet readiness
  gateway-observer-check  Diagnose observer key, report, and epoch state
  gateway-enable-x402     Configure x402 USDC data egress later
  gateway-x402-check      Inspect x402, rate limiter, metrics, and logs
  gateway-grafana         Start/stop a localhost-only Grafana sidecar
  gateway-filters         Configure ANS-104 bundle indexing filters
  gateway-apex            Serve an ArNS name or transaction at the root domain
  gateway-verification    Inspect trust headers or enable HTTP signatures
  gateway-cdb64-check     Inspect the built-in root transaction index
  gateway-cache-advisor   Assess optional high-traffic NGINX caching
  gateway-block-name      Block an ArNS name through the local admin API
  gateway-unblock-name    Unblock an ArNS name through the local admin API
  gateway-features        Open the optional feature menu

Manager
  gateway-tools-update    Update only these helper commands
  gateway-guides          Map official operator guides to safe local commands
  gateway-help            Show this list

Safety model
  - Cache cleanup uses the selected native indexed or TTL profile.
  - Persistent gateway data and Docker volumes are never blindly deleted.
  - Certificates reload NGINX; the gateway is not interrupted.
  - Autoheal restarts a service only when it becomes unhealthy.
  - Advanced NGINX caching is advisory because capacity and x402 policy vary.
HELP
}

cmd_menu() {
  while true; do
    clear || true
    printf "%b\n\n" "${BOLD}ar.io Gateway Operator${NC}"
    cat <<'MENU'
1) Complete health check
2) Service and disk status
3) Live logs
4) Storage protection
5) SSL certificate
6) Observer status
7) Wallet balance
8) Update gateway
9) Restart gateway
10) Optional features
11) Release and retrieval status
0) Exit
MENU
    local choice
    choice="$(prompt "Select" "1")"
    case "$choice" in
      1) cmd_doctor || true ;;
      2) cmd_status || true ;;
      3) cmd_logs || true ;;
      4) cmd_storage || true ;;
      5) cmd_cert_menu || true ;;
      6) cmd_observer_check || true ;;
      7) cmd_balance || true ;;
      8) cmd_update || true ;;
      9) cmd_restart || true ;;
      10) cmd_features || true ;;
      11) cmd_release_check || true ;;
      0) return ;;
      *) warn "Unknown selection." ;;
    esac
    echo
    read -r -p "Press Enter to continue..." _
  done
}

cmd_check() {
  resolve_install_dir
  local host
  host="$(domain)"
  [[ -n "$host" ]] || die "ARNS_ROOT_HOST is not set in .env."

  echo "=== Public content test ==="
  local content_file meta code
  content_file="$(mktemp)"
  meta="$(curl -sS -L --max-time 45 -o "$content_file" -w '%{http_code}|%{content_type}|%{url_effective}' "https://${host}/${TEST_TX}" 2>&1 || true)"
  code="${meta%%|*}"
  if LC_ALL=C grep -a -qx '1984' "$content_file"; then
    pass "Transaction content returned 1984 (HTTP ${code})."
  else
    warn "Content test did not return the expected value. Result: ${meta}"
  fi
  rm -f "$content_file"

  echo
  echo "=== Gateway info ==="
  curl -fsS --max-time 20 "https://${host}/ar-io/info" | jq '{release,wallet,programIds,rateLimiter,x402}' || true

  echo
  echo "=== Observer report ==="
  curl -fsS --max-time 20 "https://${host}/ar-io/observer/reports/current" | jq . || warn "Observer report is not ready. Run gateway-observer-check."

  echo
  echo "=== Docker services ==="
  compose ps
}

cmd_release_check() {
  resolve_install_dir
  local local_release latest_json latest_tag local_number="" latest_number=""
  local metrics metric order last_timeout leaving max_size concurrency
  local_release="$(curl -fsS --max-time 15 http://127.0.0.1:3000/ar-io/info 2>/dev/null | jq -r '.release // empty' || true)"
  latest_json="$(curl -fsS --max-time 15 -H 'Accept: application/vnd.github+json' https://api.github.com/repos/ar-io/ar-io-node/releases/latest 2>/dev/null || true)"
  latest_tag="$(printf '%s' "$latest_json" | jq -r '.tag_name // empty' 2>/dev/null || true)"
  [[ "$local_release" =~ ([0-9]+) ]] && local_number="${BASH_REMATCH[1]}"
  [[ "$latest_tag" =~ ([0-9]+) ]] && latest_number="${BASH_REMATCH[1]}"

  echo "=== AR.IO node release ==="
  echo "running release: ${local_release:-unavailable}"
  echo "latest GitHub release: ${latest_tag:-unavailable}"
  echo "git commit: $(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unavailable)"
  if [[ -n "$local_number" && -n "$latest_number" ]]; then
    if (( local_number < latest_number )); then
      warn "A newer recommended release is available. Review its notes, then run gateway-update."
    else
      pass "The running node is at the latest published release or newer."
    fi
  else
    warn "The local or latest release number could not be compared."
  fi

  echo
  echo "=== Release 83 baseline ==="
  order="$(get_env ARNS_RESOLVER_PRIORITY_ORDER)"
  last_timeout="$(get_env ARNS_COMPOSITE_LAST_RESOLVER_TIMEOUT_MS)"
  leaving="$(get_env SKIP_LEAVING_GATEWAYS)"
  if [[ -z "$order" || "$order" == "on-demand,gateway" ]]; then pass "ArNS resolves from chain first."; else warn "ArNS priority is ${order}; r83 recommends on-demand,gateway."; fi
  if [[ -z "$last_timeout" || "$last_timeout" == "5000" ]]; then pass "Last ArNS resolver timeout uses the r83 5-second value."; else warn "ARNS_COMPOSITE_LAST_RESOLVER_TIMEOUT_MS=${last_timeout}."; fi
  if [[ "$leaving" == "false" ]]; then warn "Leaving gateways are explicitly allowed as peers."; else pass "Leaving gateways are skipped by the explicit setting or r83 default."; fi
  if [[ "$(get_env ENABLE_CHUNK_DATA_CACHE_INDEX)" == "true" ]]; then pass "Index-driven chunk cache eviction is enabled."; else warn "Index-driven chunk cache eviction is not enabled; run gateway-storage-setup."; fi

  max_size="$(get_env FOREGROUND_CACHE_MAX_SIZE)"
  concurrency="$(get_env FOREGROUND_CACHE_CONCURRENCY)"
  info "Foreground write cap: ${max_size:-0/unbounded}; concurrency cap: ${concurrency:-0/unbounded}. Release 83 leaves both deployment-specific."

  echo
  echo "=== Release 83 metrics ==="
  metrics="$(curl -fsS --max-time 15 http://127.0.0.1:3000/ar-io/__gateway_metrics 2>/dev/null || true)"
  if [[ -z "$metrics" ]]; then
    warn "Gateway metrics endpoint is unavailable."
    return
  fi
  for metric in short_reads_rejected_total ar_io_peers_skipped_leaving_total foreground_cache_skipped_total foreground_cache_coalesced_outcome_total foreground_cache_re_elections_total; do
    if grep -Eq "^(# (HELP|TYPE) )?${metric}([ {]|$)" <<< "$metrics"; then
      pass "Metric available: ${metric}"
    else
      warn "Metric not exposed yet: ${metric}"
    fi
  done
  echo
  printf '%s\n' "$metrics" \
    | grep -E '^(short_reads_rejected_total|ar_io_peers_skipped_leaving_total|foreground_cache_(skipped|coalesced_outcome|re_elections)_total)(\{|[[:space:]])' \
    | head -30 || true
}

cmd_status() {
  resolve_install_dir
  echo "=== Docker services ==="
  compose ps
  echo
  echo "=== Resources ==="
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}' || true
  echo
  echo "=== Disk space ==="
  df -hP "$INSTALL_DIR"
  echo
  echo "=== Inodes ==="
  df -iP "$INSTALL_DIR"
}

cmd_logs() {
  resolve_install_dir
  compose logs -f --tail=150 core observer envoy
}

cmd_update() {
  require_root
  resolve_install_dir
  cd "$INSTALL_DIR"
  [[ -d .git ]] || die "$INSTALL_DIR is not a Git checkout."
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "ar-io-node has local tracked changes. Commit or review them before updating."
  fi

  local before after
  before="$(git rev-parse HEAD)"
  info "Fetching the stable ar-io-node main branch..."
  git fetch origin main
  git checkout main
  git merge --ff-only origin/main
  after="$(git rev-parse HEAD)"

  info "Validating Docker Compose configuration..."
  docker compose config --quiet
  info "Pulling pinned images and applying the update..."
  docker compose pull
  docker compose up -d

  if wait_for_local_health 24; then
    pass "Gateway is healthy. ${before:0:8} -> ${after:0:8}"
  else
    fail "Update applied, but the local health check did not recover within 2 minutes."
    compose ps || true
    compose logs --tail=120 core envoy || true
    return 1
  fi
}

cmd_restart() {
  require_root
  resolve_install_dir
  info "Recreating gateway services without deleting volumes..."
  compose up -d --force-recreate
  if wait_for_local_health 24; then
    pass "Gateway restarted and is healthy."
  else
    fail "Services restarted, but the health check is still failing."
    compose ps || true
    return 1
  fi
}

cmd_balance() {
  resolve_install_dir
  local wallet rpc payload
  wallet="${1:-$(get_env OBSERVER_WALLET)}"
  rpc="$(get_env SOLANA_RPC_URL)"
  rpc="${rpc:-https://api.mainnet-beta.solana.com}"
  [[ -n "$wallet" ]] || die "No observer wallet found. Pass a Solana address as the first argument."
  [[ "$rpc" != *'api-mainnet.helius-rpc.com'* && "$rpc" != *'/v0/transactions'* ]] || die "SOLANA_RPC_URL is an Enhanced API URL, not a JSON-RPC endpoint."

  echo "wallet: $wallet"
  printf "rpc: "
  printf "%s\n" "$rpc" | redact_url
  payload="$(jq -nc --arg wallet "$wallet" '{jsonrpc:"2.0",id:1,method:"getBalance",params:[$wallet]}')"
  curl -fsS --max-time 20 "$rpc" -H 'content-type: application/json' -d "$payload" |
    jq -r 'if .result.value? != null then "balance: " + ((.result.value / 1000000000) | tostring) + " SOL" elif .error.message? then "balance lookup failed: " + .error.message else "balance lookup failed: invalid RPC response" end'
}

cmd_network_info() {
  resolve_install_dir
  local wallet
  wallet="${1:-$(get_env AR_IO_WALLET)}"
  [[ -n "$wallet" ]] || die "No operator wallet found. Pass a wallet address as the first argument."
  info "Reading gateway registry data through the @ar.io/sdk bundled with ar-io-node..."
  compose exec -T -e GATEWAY_ADDRESS="$wallet" core node --input-type=module -e '
    import { ARIO } from "@ar.io/sdk/node";
    import { createSolanaRpc } from "@solana/kit";
    try {
      const rpc = createSolanaRpc(process.env.SOLANA_RPC_URL || "https://api.mainnet-beta.solana.com");
      const gateway = await ARIO.init({ rpc }).getGateway({ address: process.env.GATEWAY_ADDRESS });
      if (gateway == null) {
        console.error("Wallet is not registered as a gateway.");
        process.exit(2);
      }
      console.log(JSON.stringify(gateway, (_key, value) =>
        typeof value === "bigint" ? value.toString() : value, 2));
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exit(1);
    }
  '
}

cmd_observer_check() {
  resolve_install_dir
  echo "=== Observer configuration ==="
  grep -E '^(ENABLE_EPOCH_CRANKING|SOLANA_KEYPAIR_PATH|OBSERVER_KEYPAIR_PATH|AR_IO_WALLET|OBSERVER_WALLET|SOLANA_RPC_URL|REPORT_DATA_SINK)=' "$INSTALL_DIR/.env" | redact_url || true

  echo
  echo "=== Key files ==="
  local key host_key
  for key in SOLANA_KEYPAIR_PATH OBSERVER_KEYPAIR_PATH SOLANA_UPLOAD_KEYPAIR_PATH; do
    local path
    path="$(get_env "$key")"
    [[ -n "$path" ]] || continue
    host_key="$INSTALL_DIR/${path#/app/}"
    if [[ -f "$host_key" ]]; then
      local mode
      mode="$(stat -c '%a' "$host_key")"
      [[ "$mode" == "600" ]] && pass "$key exists with mode 600." || warn "$key exists but mode is $mode (use 600)."
    else
      fail "$key is missing at $host_key."
    fi
  done

  echo
  echo "=== Current report ==="
  curl -fsS --max-time 15 http://127.0.0.1:5050/ar-io/observer/reports/current | jq . || warn "Local observer report endpoint is unavailable."

  echo
  echo "=== Observer service ==="
  compose ps observer
  echo
  echo "=== Recent observer warnings/errors ==="
  compose logs observer --tail=300 2>/dev/null |
    grep -Ei 'error|warn|epoch|pda|crank|prescribe|report|wallet|solana|signature|transaction' |
    tail -120 || true
}

storage_values_valid() {
  local low="$1" high="$2"
  [[ "$low" =~ ^[0-9]+$ && "$high" =~ ^[0-9]+$ ]] || return 1
  (( low >= 1 && high <= 99 && low < high ))
}

protect_chunk_cleanup_floor() {
  [[ "$(get_env CHUNK_INGEST_CACHE_ENABLED)" == "true" ]] || return 0
  local confirm_ttl allowlist_ttl current_floor safe_floor
  confirm_ttl="$(get_env CHUNK_INGEST_CONFIRMATION_TIMEOUT_SECONDS)"; confirm_ttl="${confirm_ttl:-21600}"
  allowlist_ttl="$(get_env CHUNK_INGEST_ALLOWLIST_CONFIRMATION_TIMEOUT_SECONDS)"; allowlist_ttl="${allowlist_ttl:-86400}"
  current_floor="$(get_env CHUNK_DATA_CACHE_AGGRESSIVE_MIN_AGE_SECONDS)"; current_floor="${current_floor:-3600}"
  [[ "$confirm_ttl" =~ ^[0-9]+$ && "$allowlist_ttl" =~ ^[0-9]+$ && "$current_floor" =~ ^[0-9]+$ ]] || die "Chunk ingest timeout values must be whole seconds."
  safe_floor="$current_floor"
  (( confirm_ttl > safe_floor )) && safe_floor="$confirm_ttl"
  (( allowlist_ttl > safe_floor )) && safe_floor="$allowlist_ttl"
  set_env CHUNK_DATA_CACHE_AGGRESSIVE_MIN_AGE_SECONDS "$safe_floor"
  warn "Chunk ingest is enabled; filesystem cleanup age floor was raised to ${safe_floor}s to protect unconfirmed uploads."
}

cmd_storage_setup() {
  require_root
  resolve_install_dir
  local profile_choice profile high low reserve_gib reserve_bytes ttl has_existing="false"
  cat <<'STORAGE_OPTIONS'
Storage profile:
  1) Indexed eviction - production/large caches (recommended)
  2) TTL filesystem walk - small SSD caches, simple age retention
STORAGE_OPTIONS
  profile_choice="$(prompt "Select storage profile" "1")"
  case "$profile_choice" in
    1) profile="indexed" ;;
    2) profile="ttl" ;;
    *) die "Storage profile must be 1 or 2." ;;
  esac
  if [[ "$profile" == "indexed" ]] && ! grep -A15 -m1 'await fs.promises.writeFile(chunkPath, chunkData.chunk)' "$INSTALL_DIR/src/store/fs-chunk-data-store.ts" 2>/dev/null | grep -q "error.code !== 'ENOENT'"; then
    die "This ar-io-node checkout predates the chunk-write ENOENT retry required by indexed eviction. Run gateway-update, then retry."
  fi
  high="$(prompt "Start native cache eviction at disk usage percent" "90")"
  low="$(prompt "Continue eviction until usage falls below percent" "85")"
  storage_values_valid "$low" "$high" || die "Use integers with 1 <= low < high <= 99."
  reserve_gib="$(prompt "Minimum free-space reserve in GiB" "20")"
  [[ "$reserve_gib" =~ ^[0-9]+$ ]] || die "Reserve must be a whole number of GiB."
  reserve_bytes=$((reserve_gib * 1024 * 1024 * 1024))
  if [[ "$profile" == "ttl" ]]; then
    ttl="$(prompt "Base cache retention in seconds" "14400")"
    [[ "$ttl" =~ ^[1-9][0-9]*$ ]] || die "Cache retention must be a positive whole number of seconds."
  fi

  if [[ "$profile" == "indexed" ]] && find "$INSTALL_DIR/data/contiguous/data" "$INSTALL_DIR/data/chunks" -type f -print -quit 2>/dev/null | grep -q .; then
    has_existing="true"
  fi

  echo
  if [[ "$profile" == "indexed" ]]; then
    echo "This enables ar-io-node's indexed cache evictors."
    echo "The chunk filesystem walker stays available as the official drift reconciler."
  else
    echo "This enables ar-io-node's filesystem-walk TTL reclaimers with a ${ttl}s base retention."
    warn "Filesystem walks are O(files); use the indexed profile for large or spinning-disk caches."
  fi
  echo "It does not delete SQLite indexes, observer state, wallets, or active Docker volumes."
  echo "High watermark: ${high}% | drain target: ${low}% | reserve: ${reserve_gib} GiB"
  [[ "$has_existing" == "true" ]] && warn "Existing cache data was found; a resumable one-time index backfill will be enabled."
  confirm "Apply this storage protection" "y" || return 0

  backup_env
  set_env CONTIGUOUS_DATA_CACHE_LOW_WATERMARK_PERCENT "$low"
  set_env CONTIGUOUS_DATA_CACHE_HIGH_WATERMARK_PERCENT "$high"
  set_env CONTIGUOUS_DATA_CACHE_MIN_FREE_BYTES "$reserve_bytes"
  set_env ENABLE_CONTIGUOUS_DATA_CACHE_TEMP_CLEANUP true
  set_env CHUNK_DATA_CACHE_LOW_WATERMARK_PERCENT "$low"
  set_env CHUNK_DATA_CACHE_HIGH_WATERMARK_PERCENT "$high"
  set_env CHUNK_DATA_CACHE_MIN_FREE_BYTES "$reserve_bytes"

  if [[ "$profile" == "indexed" ]]; then
    set_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX true
    set_env CONTIGUOUS_DATA_CACHE_INDEX_EVICTION_INTERVAL_MS 60000
    remove_env CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD

    set_env ENABLE_CHUNK_DATA_CACHE_INDEX true
    set_env CHUNK_DATA_CACHE_INDEX_EVICTION_INTERVAL_MS 60000
    set_env ENABLE_CHUNK_DATA_CACHE_CLEANUP true
    set_env CHUNK_DATA_CACHE_CLEANUP_THRESHOLD 14400
    set_env CHUNK_SYMLINK_CLEANUP_INTERVAL 21600

    if [[ "$has_existing" == "true" ]]; then
      set_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX_BACKFILL true
      set_env ENABLE_CHUNK_DATA_CACHE_INDEX_BACKFILL true
    else
      set_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX_BACKFILL false
      set_env ENABLE_CHUNK_DATA_CACHE_INDEX_BACKFILL false
    fi
  else
    set_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX false
    set_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX_BACKFILL false
    set_env CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD "$ttl"

    set_env ENABLE_CHUNK_DATA_CACHE_INDEX false
    set_env ENABLE_CHUNK_DATA_CACHE_INDEX_BACKFILL false
    set_env ENABLE_CHUNK_DATA_CACHE_CLEANUP true
    set_env CHUNK_DATA_CACHE_CLEANUP_THRESHOLD "$ttl"
  fi
  protect_chunk_cleanup_floor

  (cd "$INSTALL_DIR" && docker compose config --quiet)
  compose up -d --force-recreate core envoy
  pass "Native $profile storage protection is active."
  if [[ "$has_existing" == "true" ]]; then
    echo "Watch progress: gateway-logs | grep -i 'backfill complete'"
    echo "After both backfills complete, run: gateway-storage finalize-backfill"
  fi
}

cmd_storage() {
  resolve_install_dir
  if [[ "${1:-}" == "setup" ]]; then
    cmd_storage_setup
    return
  fi
  if [[ "${1:-}" == "finalize-backfill" ]]; then
    require_root
    if ! compose logs core 2>/dev/null | grep -q 'Cache index backfill complete'; then
      warn "The contiguous cache completion message was not found in current logs."
      confirm "Disable the backfill flags anyway" "n" || return 1
    fi
    if ! compose logs core 2>/dev/null | grep -q 'Chunk cache index backfill complete'; then
      warn "The chunk cache completion message was not found in current logs."
      confirm "Disable the backfill flags anyway" "n" || return 1
    fi
    backup_env
    set_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX_BACKFILL false
    set_env ENABLE_CHUNK_DATA_CACHE_INDEX_BACKFILL false
    compose up -d --force-recreate core envoy
    pass "One-time backfill flags disabled; live indexes remain enabled."
    return
  fi

  echo "=== Filesystem ==="
  df -hP "$INSTALL_DIR"
  df -iP "$INSTALL_DIR"
  echo
  echo "=== Gateway data directories ==="
  du -sh "$INSTALL_DIR/data/contiguous" "$INSTALL_DIR/data/chunks" "$INSTALL_DIR/data/sqlite" "$INSTALL_DIR/data/observer" 2>/dev/null || true
  echo
  echo "=== Native cache protection ==="
  if [[ "$(get_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX)" == "true" ]]; then
    echo "Profile: indexed eviction"
  elif [[ -n "$(get_env CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD)" ]]; then
    echo "Profile: TTL filesystem walk"
  else
    echo "Profile: not configured"
  fi
  grep -E '^(ENABLE_(CONTIGUOUS|CHUNK)_DATA_CACHE_INDEX|ENABLE_CHUNK_DATA_CACHE_CLEANUP|(CONTIGUOUS|CHUNK)_DATA_CACHE_CLEANUP_THRESHOLD|CONTIGUOUS_DATA_CACHE_(LOW|HIGH)_WATERMARK_PERCENT|CHUNK_DATA_CACHE_(LOW|HIGH)_WATERMARK_PERCENT|CONTIGUOUS_DATA_CACHE_MIN_FREE_BYTES|CHUNK_DATA_CACHE_MIN_FREE_BYTES|CHUNK_DATA_CACHE_AGGRESSIVE_MIN_AGE_SECONDS|ENABLE_(CONTIGUOUS|CHUNK)_DATA_CACHE_INDEX_BACKFILL)=' "$INSTALL_DIR/.env" || warn "Native watermark protection is not fully configured. Run gateway-storage-setup."
  echo
  echo "=== Recent eviction/backfill activity ==="
  compose logs core --tail=1000 2>/dev/null | grep -Ei 'cache index|evict|disk pressure|backfill complete|cleanup' | tail -80 || true
}

cert_path() {
  local host="$1"
  printf "/etc/letsencrypt/live/%s/fullchain.pem" "$host"
}

cert_authenticator() {
  local host="$1"
  local renewal="/etc/letsencrypt/renewal/${host}.conf"
  [[ -f "$renewal" ]] || return 0
  sed -n 's/^authenticator = //p' "$renewal" | tail -n1
}

cmd_cert_check() {
  resolve_install_dir
  local host cert end epoch now days auth result=0
  host="$(domain)"
  [[ -n "$host" ]] || die "ARNS_ROOT_HOST is not set."
  cert="$(cert_path "$host")"
  [[ -f "$cert" ]] || die "Certificate not found at $cert. Run gateway-cert-setup."
  end="$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2-)"
  epoch="$(date -d "$end" +%s)"
  now="$(date +%s)"
  days=$(( (epoch - now) / 86400 ))
  auth="$(cert_authenticator "$host")"
  echo "domain: $host"
  echo "expires: $end"
  echo "days remaining: $days"
  echo "renewal method: ${auth:-unknown}"
  if (( days < 0 )); then
    fail "Certificate has expired."
    result=1
  elif (( days <= 5 )); then
    fail "Certificate expires within 5 days. Renew now."
    result=1
  elif (( days <= 30 )); then
    warn "Certificate is inside Certbot's normal renewal window."
  else
    pass "Certificate has sufficient lifetime remaining."
  fi
  if [[ "$auth" == "manual" ]]; then
    warn "Manual DNS cannot renew unattended. Run gateway-cert-manual to renew now, or gateway-cert-setup to enable a DNS API."
  fi
  if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
    if [[ "$auth" == "manual" ]]; then
      warn "certbot.timer is enabled system-wide, but it cannot renew this manual DNS certificate."
    else
      pass "certbot.timer is enabled."
    fi
    systemctl list-timers certbot.timer --no-pager 2>/dev/null | tail -n +2 || true
  else
    warn "certbot.timer is not enabled."
  fi
  return "$result"
}

install_cert_deploy_hook() {
  local host slug hook
  host="$(domain)"
  slug="${host//./-}"
  hook="/etc/letsencrypt/renewal-hooks/deploy/ar-io-${slug}-reload-nginx"
  install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
  cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
nginx -t
systemctl reload nginx
HOOK
  chmod 755 "$hook"
}

cmd_cert_manual() {
  require_root
  resolve_install_dir
  local host cert auth end epoch now days default_answer renewal stamp record_name
  local force_args=()
  host="$(domain)"
  [[ -n "$host" ]] || die "ARNS_ROOT_HOST is not set."
  command -v certbot >/dev/null 2>&1 || die "Certbot is not installed. Run gateway-cert-setup first."
  command -v nginx >/dev/null 2>&1 || die "NGINX is not installed."
  cert="$(cert_path "$host")"
  auth="$(cert_authenticator "$host")"
  record_name="_acme-challenge.${host}"
  default_answer="y"

  echo "=== Guided manual wildcard certificate renewal ==="
  echo "Domain: $host"
  if [[ -f "$cert" ]]; then
    end="$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2-)"
    epoch="$(date -d "$end" +%s)"
    now="$(date +%s)"
    days=$(( (epoch - now) / 86400 ))
    echo "Current expiry: $end"
    echo "Days remaining: $days"
    force_args=(--force-renewal)
    if (( days > 30 )); then
      warn "More than 30 days remain. Renewing now is usually unnecessary and uses a Let's Encrypt issuance."
      default_answer="n"
    fi
  else
    warn "No existing certificate was found; this command will obtain the first one."
  fi

  if [[ -n "$auth" && "$auth" != "manual" ]]; then
    warn "The current renewal method is '$auth'. Continuing changes this certificate to manual DNS renewal."
  fi

  cat <<GUIDE

The gateway containers and NGINX will stay running. DNS-01 validation does not
take port 80 and this command does not stop or restart either service.

When Certbot displays the TXT record name and value:
  1) Open Namecheap: Domain List -> Manage -> Advanced DNS -> Host Records.
  2) Choose Add New Record -> TXT Record.
  3) Copy the exact value displayed by Certbot.
  4) Namecheap Host examples:
       certificate domain example.com         -> _acme-challenge
       certificate domain gateway.example.com -> _acme-challenge.gateway
     Use the part before your purchased base domain; Certbot's full record is authoritative.
  5) Set TTL to Automatic.
  6) If Certbot requests a second value for the same Host, keep both TXT values
     until every validation has completed.
  7) In a second SSH terminal, wait until the requested value appears with:
       dig +short TXT ${record_name} @1.1.1.1
     Only then return here and press Enter in Certbot.

Do not remove the TXT record(s) until Certbot reports success. After success,
this helper checks NGINX, reloads it without downtime, and shows the new expiry.
Manual certificates still require gateway-cert-manual again for each renewal.
GUIDE

  confirm "Start the manual DNS renewal now" "$default_answer" || {
    info "No change was made."
    return 0
  }

  renewal="/etc/letsencrypt/renewal/${host}.conf"
  if [[ -f "$renewal" ]]; then
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    cp -a "$renewal" "${renewal}.backup.${stamp}"
  fi

  certbot certonly --manual --preferred-challenges dns --agree-tos \
    --register-unsafely-without-email --cert-name "$host" \
    "${force_args[@]}" -d "$host" -d "*.${host}"

  install_cert_deploy_hook
  nginx -t
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    pass "NGINX reloaded without stopping the gateway."
  else
    warn "The certificate was issued, but NGINX is not active; no reload was attempted."
  fi
  pass "Manual wildcard certificate renewal completed. Remove the temporary TXT record(s) from Namecheap."
  cmd_cert_check || true
}

cmd_cert_menu() {
  cat <<'OPTIONS'
SSL certificate
1) Show expiry and renewal method
2) Configure automatic renewal (Namecheap or Cloudflare DNS API)
3) Renew manually with guided Namecheap TXT records (gateway stays live)
0) Back
OPTIONS
  local choice
  choice="$(prompt "Select" "1")"
  case "$choice" in
    1) cmd_cert_check ;;
    2) cmd_cert_setup ;;
    3) cmd_cert_manual ;;
    0) return ;;
    *) die "Unknown selection." ;;
  esac
}

cmd_cert_setup() {
  require_root
  resolve_install_dir
  local host choice token credentials cert auth username api_key public_ipv4 pip_args=()
  host="$(domain)"
  [[ -n "$host" ]] || die "ARNS_ROOT_HOST is not set."
  cert="$(cert_path "$host")"
  cat <<'OPTIONS'
Wildcard certificate renewal
1) Cloudflare DNS API (fully automatic)
2) Namecheap DNS API (automatic, recommended; account API requirements apply)
3) Keep the certificate's current Certbot renewal method
4) Manual DNS challenge (cannot renew unattended)
OPTIONS
  choice="$(prompt "Select" "2")"
  case "$choice" in
    1)
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-dns-cloudflare
      echo "Create a Cloudflare token with Zone:Read and DNS:Edit for only this zone."
      printf "Cloudflare API token (hidden): " >&2
      read -r -s token
      printf "\n" >&2
      [[ -n "$token" ]] || die "Token cannot be empty."
      credentials="/etc/letsencrypt/ar-io-${host//./-}-cloudflare.ini"
      umask 077
      printf "dns_cloudflare_api_token = %s\n" "$token" > "$credentials"
      unset token
      chmod 600 "$credentials"
      auth="$(cert_authenticator "$host")"
      if [[ -f "$cert" && "$auth" == "dns-cloudflare" ]]; then
        info "The existing certificate already uses Cloudflare; updating credentials without forcing a new issuance."
      else
        local force=()
        [[ -f "$cert" ]] && force=(--force-renewal)
        certbot certonly --non-interactive --agree-tos --register-unsafely-without-email \
          --dns-cloudflare --dns-cloudflare-credentials "$credentials" \
          --dns-cloudflare-propagation-seconds 30 --cert-name "$host" \
          "${force[@]}" -d "$host" -d "*.${host}"
      fi
      install_cert_deploy_hook
      systemctl enable --now certbot.timer
      nginx -t
      systemctl reload nginx
      certbot renew --dry-run --cert-name "$host"
      pass "Cloudflare wildcard renewal is configured. Certbot checks twice daily and renews inside 30 days."
      ;;
    2)
      warn "Namecheap normally requires 20 domains, a USD 50 balance, and USD 50 spent in the last two years for API access."
      confirm "My Namecheap API access is active" "n" || return 0
      public_ipv4="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
      echo "Server public IPv4: ${public_ipv4:-could not be detected}"
      echo "Namecheap: Profile -> Tools -> Namecheap API Access -> Whitelisted IPs"
      confirm "This server IPv4 is whitelisted in Namecheap" "n" || return 0
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-pip
      if python3 -m pip help install 2>/dev/null | grep -q -- '--break-system-packages'; then
        pip_args=(--break-system-packages)
      fi
      python3 -m pip install "${pip_args[@]}" certbot-dns-namecheap
      certbot plugins | grep -q 'dns-namecheap' || die "Certbot could not load the Namecheap plugin."
      username="$(prompt "Namecheap username" "")"
      printf "Namecheap API key (hidden): " >&2
      read -r -s api_key
      printf "\n" >&2
      [[ -n "$username" && -n "$api_key" ]] || die "Username and API key are required."
      credentials="/etc/letsencrypt/ar-io-${host//./-}-namecheap.ini"
      umask 077
      printf "dns_namecheap_username = %s\ndns_namecheap_api_key = %s\n" "$username" "$api_key" > "$credentials"
      unset api_key
      chmod 600 "$credentials"
      auth="$(cert_authenticator "$host")"
      if [[ -f "$cert" && "$auth" == "dns-namecheap" ]]; then
        info "The existing certificate already uses Namecheap; updating credentials without forcing a new issuance."
      else
        local force=()
        [[ -f "$cert" ]] && force=(--force-renewal)
        certbot certonly --non-interactive --agree-tos --register-unsafely-without-email \
          --dns-namecheap --dns-namecheap-credentials "$credentials" \
          --cert-name "$host" "${force[@]}" -d "$host" -d "*.${host}"
      fi
      install_cert_deploy_hook
      systemctl enable --now certbot.timer
      nginx -t
      systemctl reload nginx
      certbot renew --dry-run --cert-name "$host"
      pass "Namecheap wildcard renewal is configured and dry-run verified."
      ;;
    3)
      [[ -f "$cert" ]] || die "No existing certificate was found."
      install_cert_deploy_hook
      auth="$(cert_authenticator "$host")"
      if [[ "$auth" == "manual" || -z "$auth" ]]; then
        warn "The current certificate cannot renew unattended. Choose Cloudflare or Namecheap instead."
      else
        systemctl enable --now certbot.timer
        certbot renew --dry-run --cert-name "$host"
      fi
      cmd_cert_check
      ;;
    4)
      cmd_cert_manual
      ;;
    *) die "Unknown selection." ;;
  esac
}

cmd_renew_cert() {
  require_root
  resolve_install_dir
  local host auth
  host="$(domain)"
  auth="$(cert_authenticator "$host")"
  if [[ "$auth" == "manual" || -z "$auth" ]]; then
    warn "This certificate uses manual DNS. Certbot cannot renew it without a new TXT record."
    cmd_cert_manual
    return
  fi
  if [[ "${1:-}" == "--dry-run" ]]; then
    certbot renew --dry-run --cert-name "$host"
  else
    certbot renew --cert-name "$host"
    nginx -t
    systemctl reload nginx
  fi
  cmd_cert_check
}

cmd_x402_check() {
  resolve_install_dir
  echo "=== x402 and rate limiter configuration ==="
  grep -E '^(ENABLE_RATE_LIMITER|RATE_LIMITER_|ENABLE_X_402|X_402_)' "$INSTALL_DIR/.env" |
    sed -E 's/(SECRET|PRIVATE_KEY)=.*/\1=***/' | redact_url || true
  echo
  echo "=== Runtime metrics ==="
  curl -fsS --max-time 15 http://127.0.0.1:3000/ar-io/__gateway_metrics | grep -Ei 'rate_limit|token|x402|payment' | head -80 || warn "Metrics unavailable or no x402 metrics emitted yet."
  echo
  echo "=== Recent payment/rate-limit logs ==="
  compose logs core --tail=500 2>/dev/null | grep -Ei 'x402|payment|rate limit' | tail -100 || true
}

is_evm_address() { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; }
is_decimal() { [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; }

cmd_enable_x402() {
  require_root
  resolve_install_dir
  local network wallet facilitator per_byte min_price max_price multiplier app_name app_logo limiter
  local redis_endpoint redis_flags chunk_size ip_allowlist arns_allowlist
  local ip_bucket ip_refill resource_bucket resource_refill
  local cdp_id cdp_client cdp_secret existing_cdp_secret
  echo "x402 charges USDC on Base for data egress after the free rate-limit capacity is exhausted."
  echo "It requires ENABLE_RATE_LIMITER=true. Existing gateway data is not reinstalled."
  limiter="$(prompt "Rate limiter type (redis or memory)" "${RATE_LIMITER_TYPE:-$(get_env RATE_LIMITER_TYPE)}")"
  limiter="${limiter:-redis}"
  [[ "$limiter" == "redis" || "$limiter" == "memory" ]] || die "Rate limiter must be redis or memory."
  redis_endpoint="$(get_env RATE_LIMITER_REDIS_ENDPOINT)"
  redis_endpoint="${redis_endpoint:-redis://redis:6379}"
  redis_flags="$(get_env EXTRA_REDIS_FLAGS)"
  redis_flags="${redis_flags:---save 300 10 --appendonly yes --appendfsync everysec}"
  if [[ "$limiter" == "redis" ]]; then
    redis_endpoint="$(prompt "Redis endpoint" "$redis_endpoint")"
    redis_flags="$(prompt "Redis persistence flags" "$redis_flags")"
  fi
  ip_bucket="$(prompt "IP tokens per bucket" "$(get_env RATE_LIMITER_IP_TOKENS_PER_BUCKET)")"
  ip_bucket="${ip_bucket:-100000}"
  ip_refill="$(prompt "IP refill per second" "$(get_env RATE_LIMITER_IP_REFILL_PER_SEC)")"
  ip_refill="${ip_refill:-20}"
  resource_bucket="$(prompt "Resource tokens per bucket" "$(get_env RATE_LIMITER_RESOURCE_TOKENS_PER_BUCKET)")"
  resource_bucket="${resource_bucket:-1000000}"
  resource_refill="$(prompt "Resource refill per second" "$(get_env RATE_LIMITER_RESOURCE_REFILL_PER_SEC)")"
  resource_refill="${resource_refill:-100}"
  [[ "$ip_bucket" =~ ^[0-9]+$ && "$ip_refill" =~ ^[0-9]+$ && "$resource_bucket" =~ ^[0-9]+$ && "$resource_refill" =~ ^[0-9]+$ ]] || die "Rate limit values must be whole numbers."
  network="$(prompt "Network (base or base-sepolia)" "${X402_NETWORK:-$(get_env X_402_USDC_NETWORK)}")"
  network="${network:-base}"
  [[ "$network" == "base" || "$network" == "base-sepolia" ]] || die "Network must be base or base-sepolia."
  while true; do
    wallet="$(prompt "EVM/Base USDC receiver wallet" "$(get_env X_402_USDC_WALLET_ADDRESS)")"
    is_evm_address "$wallet" && break
    warn "Enter a 0x-prefixed 40-byte EVM address."
  done
  facilitator="$(get_env X_402_USDC_FACILITATOR_URL)"
  [[ -n "$facilitator" ]] || facilitator="https://facilitator.x402.rs"
  [[ "$network" == "base-sepolia" && "$facilitator" == "https://facilitator.x402.rs" ]] && facilitator="https://x402.org/facilitator"
  facilitator="$(prompt "Facilitator URL" "$facilitator")"
  [[ "$facilitator" =~ ^https?://[^[:space:]]+$ ]] || die "Facilitator must be an HTTP(S) URL."
  per_byte="$(prompt "USDC price per byte" "${X402_PER_BYTE_PRICE:-$(get_env X_402_USDC_PER_BYTE_PRICE)}")"
  per_byte="${per_byte:-0.0000000001}"
  min_price="$(prompt "Minimum charge" "${X402_MIN_PRICE:-$(get_env X_402_USDC_DATA_EGRESS_MIN_PRICE)}")"
  min_price="${min_price:-0.001}"
  max_price="$(prompt "Maximum charge" "${X402_MAX_PRICE:-$(get_env X_402_USDC_DATA_EGRESS_MAX_PRICE)}")"
  max_price="${max_price:-1.00}"
  multiplier="$(prompt "Paid capacity multiplier" "${X402_MULTIPLIER:-$(get_env X_402_RATE_LIMIT_CAPACITY_MULTIPLIER)}")"
  multiplier="${multiplier:-10}"
  is_decimal "$per_byte" && is_decimal "$min_price" && is_decimal "$max_price" || die "x402 prices must be non-negative decimal numbers."
  [[ "$multiplier" =~ ^[1-9][0-9]*$ ]] || die "Capacity multiplier must be a positive whole number."
  awk -v min="$min_price" -v max="$max_price" 'BEGIN { exit !(min <= max) }' || die "Minimum charge cannot exceed maximum charge."
  app_name="$(prompt "Paywall app name" "$(get_env X_402_APP_NAME)")"
  app_name="${app_name:-$(domain)}"
  app_logo="$(prompt "Paywall logo URL (optional)" "$(get_env X_402_APP_LOGO)")"
  chunk_size="$(prompt "Chunk base64 size in bytes" "$(get_env CHUNK_GET_BASE64_SIZE_BYTES)")"
  chunk_size="${chunk_size:-368640}"
  [[ "$chunk_size" =~ ^[0-9]+$ ]] || die "Chunk size must be a whole number."
  ip_allowlist="$(prompt "IP/CIDR allowlist, comma-separated (optional)" "$(get_env RATE_LIMITER_IPS_AND_CIDRS_ALLOWLIST)")"
  arns_allowlist="$(prompt "ArNS allowlist, comma-separated (optional)" "$(get_env RATE_LIMITER_ARNS_ALLOWLIST)")"

  cdp_id="$(get_env CDP_API_KEY_ID)"
  cdp_client="$(get_env X_402_CDP_CLIENT_KEY)"
  existing_cdp_secret="$(get_env CDP_API_KEY_SECRET_FILE)"
  cdp_secret=""
  if confirm "Configure optional Coinbase CDP browser onramp" "n"; then
    cdp_id="$(prompt "CDP_API_KEY_ID" "$cdp_id")"
    cdp_client="$(prompt "X_402_CDP_CLIENT_KEY (public)" "$cdp_client")"
    printf "CDP API secret (hidden; blank keeps the current secret): " >&2
    read -r -s cdp_secret
    printf "\n" >&2
  fi

  echo
  echo "network=$network receiver=$wallet min=$min_price max=$max_price"
  confirm "Apply x402 configuration" "n" || return 0
  backup_env
  set_env ENABLE_RATE_LIMITER true
  set_env RATE_LIMITER_TYPE "$limiter"
  set_env RATE_LIMITER_IP_TOKENS_PER_BUCKET "$ip_bucket"
  set_env RATE_LIMITER_IP_REFILL_PER_SEC "$ip_refill"
  set_env RATE_LIMITER_RESOURCE_TOKENS_PER_BUCKET "$resource_bucket"
  set_env RATE_LIMITER_RESOURCE_REFILL_PER_SEC "$resource_refill"
  if [[ "$limiter" == "redis" ]]; then
    set_env RATE_LIMITER_REDIS_ENDPOINT "$redis_endpoint"
    set_env EXTRA_REDIS_FLAGS "$redis_flags"
  else
    remove_env RATE_LIMITER_REDIS_ENDPOINT
    remove_env EXTRA_REDIS_FLAGS
  fi
  set_env ENABLE_X_402_USDC_DATA_EGRESS true
  set_env X_402_USDC_NETWORK "$network"
  set_env X_402_USDC_WALLET_ADDRESS "$wallet"
  set_env X_402_USDC_FACILITATOR_URL "$facilitator"
  set_env X_402_USDC_PER_BYTE_PRICE "$per_byte"
  set_env X_402_USDC_DATA_EGRESS_MIN_PRICE "$min_price"
  set_env X_402_USDC_DATA_EGRESS_MAX_PRICE "$max_price"
  set_env X_402_RATE_LIMIT_CAPACITY_MULTIPLIER "$multiplier"
  set_env X_402_APP_NAME "$app_name"
  if [[ -n "$app_logo" ]]; then set_env X_402_APP_LOGO "$app_logo"; else remove_env X_402_APP_LOGO; fi
  set_env CHUNK_GET_BASE64_SIZE_BYTES "$chunk_size"
  if [[ -n "$ip_allowlist" ]]; then set_env RATE_LIMITER_IPS_AND_CIDRS_ALLOWLIST "$ip_allowlist"; else remove_env RATE_LIMITER_IPS_AND_CIDRS_ALLOWLIST; fi
  if [[ -n "$arns_allowlist" ]]; then set_env RATE_LIMITER_ARNS_ALLOWLIST "$arns_allowlist"; else remove_env RATE_LIMITER_ARNS_ALLOWLIST; fi
  if [[ -n "$cdp_id" ]]; then set_env CDP_API_KEY_ID "$cdp_id"; else remove_env CDP_API_KEY_ID; fi
  if [[ -n "$cdp_client" ]]; then set_env X_402_CDP_CLIENT_KEY "$cdp_client"; else remove_env X_402_CDP_CLIENT_KEY; fi
  if [[ -n "$cdp_secret" ]]; then
    install -d -m 700 "$INSTALL_DIR/secrets"
    umask 077
    printf "%s" "$cdp_secret" > "$INSTALL_DIR/secrets/cdp_secret_key"
    chmod 600 "$INSTALL_DIR/secrets/cdp_secret_key"
    set_env CDP_API_KEY_SECRET_FILE /app/secrets/cdp_secret_key
  elif [[ -n "$existing_cdp_secret" ]]; then
    set_env CDP_API_KEY_SECRET_FILE "$existing_cdp_secret"
  elif [[ -f "$INSTALL_DIR/secrets/cdp_secret_key" ]]; then
    set_env CDP_API_KEY_SECRET_FILE /app/secrets/cdp_secret_key
  fi
  unset cdp_secret

  (cd "$INSTALL_DIR" && docker compose config --quiet)
  if [[ "$limiter" == "redis" ]]; then
    compose up -d --force-recreate redis core envoy
  else
    compose up -d --force-recreate core envoy
  fi
  pass "x402 is configured."
  cmd_x402_check || true
}

cmd_grafana() {
  require_root
  resolve_install_dir
  local action="${1:-menu}"
  local compose_file="$INSTALL_DIR/docker-compose.grafana.safe.yaml"
  local secret_file="$INSTALL_DIR/secrets/grafana.env"
  if [[ "$action" == "menu" ]]; then
    echo "1) Start or update Grafana"
    echo "2) Status"
    echo "3) Stop"
    action="$(prompt "Select" "1")"
    case "$action" in 1) action=start;; 2) action=status;; 3) action=stop;; *) die "Unknown selection.";; esac
  fi
  if [[ "$action" == "start" ]]; then
    install -d -m 700 "$INSTALL_DIR/secrets"
    if [[ ! -f "$secret_file" ]]; then
      local password
      password="$(openssl rand -base64 24 | tr -d '\n')"
      printf "GF_SECURITY_ADMIN_USER=admin\nGF_SECURITY_ADMIN_PASSWORD=%s\n" "$password" > "$secret_file"
      chmod 600 "$secret_file"
      echo "Grafana username: admin"
      echo "Grafana password: $password"
      echo "Save this password now. It remains in $secret_file with mode 600."
    fi
    cat > "$compose_file" <<'YAML'
networks:
  ar-io-network:
    external: true
    name: ${DOCKER_NETWORK_NAME:-ar-io-network}

services:
  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    networks: [ar-io-network]
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro

  node-exporter:
    image: prom/node-exporter:v1.3.1
    restart: unless-stopped
    networks: [ar-io-network]
    volumes:
      - /:/host:ro,rslave
    command: ['--path.rootfs=/host']

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    networks: [ar-io-network]
    ports:
      - 127.0.0.1:1024:1024
    env_file:
      - ./secrets/grafana.env
    environment:
      - TERM=linux
      - GF_SERVER_ROOT_URL=http://localhost:1024/grafana
      - GF_SERVER_SERVE_FROM_SUB_PATH=true
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-polystat-panel
      - GF_SERVER_HTTP_PORT=1024
    volumes:
      - ./monitoring/grafana/dashboards:/etc/grafana/dashboards:ro
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./data/grafana:/var/lib/grafana
YAML
    chmod 600 "$compose_file"
    (cd "$INSTALL_DIR" && docker compose -f "$compose_file" pull && docker compose -f "$compose_file" up -d)
    pass "Grafana is bound to localhost only."
    echo "Open it securely from your computer with:"
    echo "  ssh -L 1024:127.0.0.1:1024 root@YOUR_SERVER"
    echo "Then visit http://localhost:1024/grafana"
  elif [[ "$action" == "status" ]]; then
    [[ -f "$compose_file" ]] || die "Grafana has not been configured."
    (cd "$INSTALL_DIR" && docker compose -f "$compose_file" ps)
  elif [[ "$action" == "stop" ]]; then
    [[ -f "$compose_file" ]] || die "Grafana has not been configured."
    (cd "$INSTALL_DIR" && docker compose -f "$compose_file" down)
  else
    die "Use gateway-grafana start|status|stop."
  fi
}

cmd_filters() {
  require_root
  resolve_install_dir
  cat <<'FILTERS'
ANS-104 indexing profile
1) Disabled (default, lowest resource use)
2) Index all bundles and data items (high resource use)
3) Custom JSON filters (professional)
FILTERS
  local choice unbundle index
  choice="$(prompt "Select" "1")"
  case "$choice" in
    1) unbundle='{"never":true}'; index='{"never":true}' ;;
    2)
      warn "Indexing everything can require substantial CPU, memory, disk, and sync time."
      confirm "Enable full bundle processing" "n" || return 0
      unbundle='{"always":true}'; index='{"always":true}'
      ;;
    3)
      unbundle="$(prompt "ANS104_UNBUNDLE_FILTER JSON" "$(get_env ANS104_UNBUNDLE_FILTER)")"
      index="$(prompt "ANS104_INDEX_FILTER JSON" "$(get_env ANS104_INDEX_FILTER)")"
      printf "%s" "$unbundle" | jq -e . >/dev/null || die "Invalid unbundle JSON."
      printf "%s" "$index" | jq -e . >/dev/null || die "Invalid index JSON."
      ;;
    *) die "Unknown selection." ;;
  esac
  backup_env
  set_env ANS104_UNBUNDLE_FILTER "$unbundle"
  set_env ANS104_INDEX_FILTER "$index"
  (cd "$INSTALL_DIR" && docker compose config --quiet)
  compose up -d --force-recreate core
  pass "ANS-104 filters updated."
}

is_tx_id() { [[ "$1" =~ ^[A-Za-z0-9_-]{43}$ ]]; }
is_arns_name_list() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*(,[a-z0-9][a-z0-9_-]*)*$ ]]; }

cmd_apex() {
  require_root
  resolve_install_dir
  local choice value
  echo "Current APEX_ARNS_NAME: $(get_env APEX_ARNS_NAME)"
  echo "Current APEX_TX_ID: $(get_env APEX_TX_ID)"
  cat <<'APEX'
1) Use an ArNS name (recommended; later content changes need no restart)
2) Use a fixed transaction ID
3) Restore the default gateway information page
0) Cancel
APEX
  choice="$(prompt "Select" "1")"
  case "$choice" in
    1)
      value="$(prompt "ArNS name" "$(get_env APEX_ARNS_NAME)")"
      is_arns_name_list "$value" || die "Use a lowercase ArNS name (comma-separated names are allowed for multiple root hosts)."
      backup_env
      set_env APEX_ARNS_NAME "$value"
      remove_env APEX_TX_ID
      ;;
    2)
      value="$(prompt "43-character Arweave transaction ID" "$(get_env APEX_TX_ID)")"
      is_tx_id "$value" || die "Invalid Arweave transaction ID."
      backup_env
      set_env APEX_TX_ID "$value"
      remove_env APEX_ARNS_NAME
      ;;
    3)
      confirm "Restore the default apex page" "n" || return 0
      backup_env
      remove_env APEX_TX_ID
      remove_env APEX_ARNS_NAME
      ;;
    0) return 0 ;;
    *) die "Unknown selection." ;;
  esac
  (cd "$INSTALL_DIR" && docker compose config --quiet)
  compose up -d --force-recreate core envoy
  wait_for_local_health 24 || die "Apex configuration was applied, but the gateway did not become healthy."
  pass "Apex content configuration updated."
}

print_verification_headers() {
  awk '{ lower=tolower($0) }
    lower ~ /^http\// || lower ~ /^x-ar-io-(verified|stable|trusted|digest|data-id|hops|root-transaction-id):/ ||
    lower ~ /^content-digest:/ || lower ~ /^etag:/ || lower ~ /^x-cache:/ || lower ~ /^signature(-input)?:/ { sub(/\r$/, ""); print }'
}

cmd_verification() {
  resolve_install_dir
  local action="${1:-menu}" id host
  host="$(domain)"
  [[ -n "$host" ]] || die "ARNS_ROOT_HOST is not set."
  if [[ "$action" == "menu" ]]; then
    cat <<'VERIFY'
1) Inspect trust, digest, and signature headers
2) Enable RFC 9421 HTTP response signatures
3) Show signing status
0) Cancel
VERIFY
    action="$(prompt "Select" "1")"
    case "$action" in 1) action=check;; 2) action=enable;; 3) action=status;; 0) return 0;; *) die "Unknown selection.";; esac
  fi
  case "$action" in
    check)
      id="${2:-$(prompt "Transaction/data item ID" "$TEST_TX")}"; is_tx_id "$id" || die "Invalid transaction/data item ID."
      echo "First HEAD request (a MISS or Verified=false can be normal):"
      curl -sSIL --max-time 45 "https://${host}/${id}" | print_verification_headers
      echo
      echo "Second HEAD request (checks the cached response):"
      curl -sSIL --max-time 45 "https://${host}/${id}" | print_verification_headers
      ;;
    enable)
      require_root
      if [[ -z "$(get_env OBSERVER_KEYPAIR_PATH)" && -z "$(get_env OBSERVER_PRIVATE_KEY)" ]]; then
        warn "No explicit observer key is configured. The node will generate a standalone signing key that is not tied to the on-chain gateway registry."
      else
        info "The configured observer key will identify signed responses against the gateway registry."
      fi
      confirm "Enable HTTPSIG_ENABLED" "y" || return 0
      backup_env
      set_env HTTPSIG_ENABLED true
      compose up -d --force-recreate core envoy
      wait_for_local_health 24 || die "HTTP signatures were enabled, but the gateway did not become healthy."
      cmd_verification status
      ;;
    status)
      echo "HTTPSIG_ENABLED=$(get_env HTTPSIG_ENABLED)"
      curl -fsS --max-time 20 "https://${host}/ar-io/info" | jq '.httpsig // {enabled:false}' || warn "Gateway info is unavailable."
      ;;
    *) die "Use gateway-verification check|enable|status [TX_ID]." ;;
  esac
}

cmd_cdb64_check() {
  resolve_install_dir
  local order normalized_order sources release
  order="$(get_env ROOT_TX_LOOKUP_ORDER)"
  normalized_order="$(printf "%s" "$order" | tr -d '[:space:]')"
  sources="$(get_env CDB64_ROOT_TX_INDEX_SOURCES)"
  release="$(curl -fsS --max-time 15 http://127.0.0.1:3000/ar-io/info 2>/dev/null | jq -r '.release // "unknown"' || true)"
  echo "gateway release: ${release:-unknown}"
  echo "ROOT_TX_LOOKUP_ORDER: ${order:-built-in release default}"
  echo "CDB64_ROOT_TX_INDEX_SOURCES: ${sources:-shipped default index}"
  if [[ -n "$normalized_order" && ",$normalized_order," != *,cdb,* ]]; then
    warn "CDB64 is explicitly absent from ROOT_TX_LOOKUP_ORDER. This is normally not recommended."
  else
    pass "CDB64 is available through the default or explicit lookup order."
  fi
  echo
  echo "=== Local index files ==="
  du -sh "$INSTALL_DIR/data/cdb64-root-tx-index" 2>/dev/null || echo "No local CDB64 directory (remote shipped index may still be active)."
  echo
  echo "=== Recent CDB64 logs ==="
  compose logs core --tail=1000 2>/dev/null | grep -i cdb64 | tail -80 || true
}

cmd_cache_advisor() {
  resolve_install_dir
  local used available x402 configured="false"
  used="$(df -hP "$INSTALL_DIR" | awk 'NR==2 {print $5}')"
  available="$(df -hP "$INSTALL_DIR" | awk 'NR==2 {print $4}')"
  [[ "$(get_env ENABLE_X_402_USDC_DATA_EGRESS)" == "true" ]] && x402="enabled" || x402="disabled"
  nginx -T 2>/dev/null | grep -q 'proxy_cache_path' && configured="true"
  echo "Advanced NGINX cache readiness"
  echo "filesystem usage: $used | available: $available"
  echo "x402: $x402 | proxy_cache_path detected: $configured"
  echo "foreground max item bytes: $(get_env FOREGROUND_CACHE_MAX_SIZE) (blank/0 = unbounded)"
  echo "foreground write concurrency: $(get_env FOREGROUND_CACHE_CONCURRENCY) (blank/0 = unbounded)"
  echo "coalescing minimum bytes: $(get_env FOREGROUND_CACHE_COALESCE_MIN_SIZE) (blank/0 = no floor)"
  echo
  echo "The ar.io node works without an NGINX cache. It is intended for high-traffic gateways."
  echo "A production design must size each cache zone, leave room for SQLite/ClickHouse and the OS,"
  echo "avoid a constrained database disk, bypass 429 and Cache-Control:no-store responses, and preserve moderation purges."
  if [[ "$x402" == "enabled" ]]; then
    warn "Cached 200 responses do not reach the node rate limiter. This changes x402 enforcement and must be a deliberate policy decision."
  fi
  echo
  echo "Official guide: https://docs.ar.io/build/run-a-gateway/manage/nginx-caching/"
  echo "This command does not rewrite a live NGINX configuration automatically."
}

cmd_guides() {
  cat <<'GUIDES'
Official ar.io operator guide map

Installation and production domain
  command: gateway-doctor
  guide:   https://docs.ar.io/build/run-a-gateway/quick-start/

Solana migration and registry
  commands: gateway-observer-check, gateway-balance, gateway-network-info
  guides:   https://docs.ar.io/build/run-a-gateway/manage/solana-migration/
            https://docs.ar.io/sdks/ar-io-sdk/

Safe upgrade
  command: gateway-update
  guide:   https://docs.ar.io/build/run-a-gateway/manage/upgrading-a-gateway/

Automatic wildcard SSL
  commands: gateway-cert-setup, gateway-cert-check, gateway-cert-manual, gateway-renew-cert --dry-run
  guide:    https://docs.ar.io/build/run-a-gateway/manage/ssl-certs/

Verification and HTTP signatures
  command: gateway-verification
  guide:   https://docs.ar.io/build/run-a-gateway/manage/verification-headers/

Performance
  commands: gateway-storage, gateway-filters, gateway-cdb64-check, gateway-cache-advisor
  guides:   https://docs.ar.io/build/run-a-gateway/manage/filters/
            https://docs.ar.io/build/run-a-gateway/manage/cdb64/
            https://docs.ar.io/build/run-a-gateway/manage/nginx-caching/

Content and payments
  commands: gateway-apex, gateway-block-name, gateway-unblock-name, gateway-enable-x402
  guides:   https://docs.ar.io/build/run-a-gateway/manage/setting-apex-domain/
            https://docs.ar.io/build/run-a-gateway/manage/content-moderation/
            https://docs.ar.io/build/run-a-gateway/manage/x402-setup/

Monitoring and troubleshooting
  commands: gateway-grafana, gateway-doctor, gateway-logs
  guides:   https://docs.ar.io/build/extensions/grafana/
            https://docs.ar.io/build/run-a-gateway/manage/troubleshooting/

Separate products and professional sidecars
  Wayfinder Router: https://docs.ar.io/build/run-wayfinder-router/
  ClickHouse:       https://docs.ar.io/build/extensions/clickhouse/
  Bundler:          https://docs.ar.io/build/extensions/bundler/
  Verifiable AI:    https://docs.ar.io/build/verifiable-ai/
  These are not enabled by this gateway manager because each adds a separate
  security, storage, wallet, domain, or data-retention boundary.

SQLite snapshot import is intentionally not automated: it stops the gateway and
replaces index databases. Follow the current official guide and verify its snapshot
source before a planned maintenance window:
  https://docs.ar.io/build/run-a-gateway/manage/index-snapshots/

Environment variable reference:
  https://docs.ar.io/build/run-a-gateway/manage/environment-variables/
GUIDES
}

admin_key() { get_env ADMIN_API_KEY; }

cmd_block_name() {
  require_root
  resolve_install_dir
  local name notes source key body
  name="${1:-$(prompt "ArNS name to block" "")}"; [[ -n "$name" ]] || die "Name cannot be empty."
  notes="$(prompt "Private operator note" "blocked by operator")"
  source="$(prompt "Source" "manual")"
  key="$(admin_key)"; [[ -n "$key" ]] || die "ADMIN_API_KEY is not configured."
  body="$(jq -nc --arg name "$name" --arg notes "$notes" --arg source "$source" '{name:$name,notes:$notes,source:$source}')"
  curl -fsS -X PUT http://127.0.0.1:3000/ar-io/admin/block-name \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body"
  echo
  pass "ArNS name '$name' is blocked on this gateway."
}

cmd_unblock_name() {
  require_root
  resolve_install_dir
  local name key body
  name="${1:-$(prompt "ArNS name to unblock" "")}"; [[ -n "$name" ]] || die "Name cannot be empty."
  key="$(admin_key)"; [[ -n "$key" ]] || die "ADMIN_API_KEY is not configured."
  body="$(jq -nc --arg name "$name" '{name:$name}')"
  curl -fsS -X PUT http://127.0.0.1:3000/ar-io/admin/unblock-name \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body"
  echo
  pass "ArNS name '$name' is unblocked on this gateway."
}

cmd_features() {
  cat <<'FEATURES'
Optional gateway features
1) x402 USDC data egress
2) Native disk protection
3) Automatic wildcard SSL (Cloudflare or Namecheap)
4) Local Grafana monitoring
5) ANS-104 indexing filters
6) ArNS name moderation
7) Network registration readiness
8) Apex domain content
9) Verification headers and HTTP signatures
10) CDB64 index status
11) High-traffic NGINX cache advisor
12) On-chain gateway registry status (AR.IO SDK)
13) Official operator guide map
0) Back
FEATURES
  local choice
  choice="$(prompt "Select" "1")"
  case "$choice" in
    1) cmd_enable_x402 ;;
    2) cmd_storage_setup ;;
    3) cmd_cert_setup ;;
    4) cmd_grafana start ;;
    5) cmd_filters ;;
    6)
      echo "1) Block name  2) Unblock name"
      choice="$(prompt "Select" "1")"
      [[ "$choice" == "1" ]] && cmd_block_name || cmd_unblock_name
      ;;
    7) cmd_network_readiness ;;
    8) cmd_apex ;;
    9) cmd_verification ;;
    10) cmd_cdb64_check ;;
    11) cmd_cache_advisor ;;
    12) cmd_network_info ;;
    13) cmd_guides ;;
    0) return ;;
    *) die "Unknown selection." ;;
  esac
}

cmd_network_readiness() {
  resolve_install_dir
  local host failures=0
  host="$(domain)"
  [[ -n "$host" ]] || die "ARNS_ROOT_HOST is not set."
  echo "=== Network registration readiness ==="
  if curl -fsS -L --max-time 30 "https://${host}/${TEST_TX}" | grep -qx '1984'; then pass "Public transaction test"; else fail "Public transaction test"; failures=$((failures+1)); fi
  if echo | openssl s_client -connect "${host}:443" -servername "test.${host}" 2>/dev/null | openssl x509 -noout -checkend 432000 >/dev/null 2>&1; then pass "Wildcard TLS valid for more than 5 days"; else fail "Wildcard TLS check"; failures=$((failures+1)); fi
  [[ -n "$(get_env AR_IO_WALLET)" ]] && pass "Operator wallet configured" || { fail "Operator wallet missing"; failures=$((failures+1)); }
  [[ -n "$(get_env OBSERVER_WALLET)" ]] && pass "Observer wallet configured" || { fail "Observer wallet missing"; failures=$((failures+1)); }
  if (( failures == 0 )); then
    pass "Technical checks passed. Review current stake and registration requirements at https://docs.ar.io/build/run-a-gateway/join-the-network/"
  else
    fail "$failures readiness check(s) failed."
    return 1
  fi
}

cmd_doctor() {
  resolve_install_dir
  local failures=0 warnings=0 host used inode cert cert_auth order
  host="$(domain)"
  echo "=== ar.io Gateway Doctor ==="
  echo "install: $INSTALL_DIR"
  echo "domain: ${host:-not set}"
  echo

  if docker info >/dev/null 2>&1; then pass "Docker daemon"; else fail "Docker daemon"; failures=$((failures+1)); fi
  if (cd "$INSTALL_DIR" && docker compose config --quiet >/dev/null 2>&1); then pass "Docker Compose configuration"; else fail "Docker Compose configuration"; failures=$((failures+1)); fi
  if nginx -t >/dev/null 2>&1; then pass "NGINX configuration"; else fail "NGINX configuration"; failures=$((failures+1)); fi
  if wait_for_local_health 1; then pass "Local gateway health"; else fail "Local gateway health"; failures=$((failures+1)); fi
  if [[ -n "$host" ]] && curl -fsS --max-time 15 "https://${host}/ar-io/healthcheck" >/dev/null; then pass "Public HTTPS health"; else fail "Public HTTPS health"; failures=$((failures+1)); fi
  if [[ -n "$host" ]] && curl -fsS -L --max-time 30 "https://${host}/${TEST_TX}" | grep -qx '1984'; then pass "Public data retrieval"; else fail "Public data retrieval"; failures=$((failures+1)); fi

  used="$(df -P "$INSTALL_DIR" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
  inode="$(df -Pi "$INSTALL_DIR" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
  if (( used >= 90 )); then fail "Disk usage is ${used}%"; failures=$((failures+1)); elif (( used >= 80 )); then warn "Disk usage is ${used}%"; warnings=$((warnings+1)); else pass "Disk usage is ${used}%"; fi
  if (( inode >= 90 )); then fail "Inode usage is ${inode}%"; failures=$((failures+1)); elif (( inode >= 80 )); then warn "Inode usage is ${inode}%"; warnings=$((warnings+1)); else pass "Inode usage is ${inode}%"; fi

  cert="$(cert_path "$host")"
  if [[ -f "$cert" ]] && openssl x509 -checkend 432000 -noout -in "$cert" >/dev/null; then pass "TLS certificate valid for more than 5 days"; else fail "TLS certificate missing or near expiry"; failures=$((failures+1)); fi
  cert_auth="$(cert_authenticator "$host")"
  if [[ "$cert_auth" == "manual" || -z "$cert_auth" ]]; then
    warn "TLS renewal is not unattended (${cert_auth:-unknown} authenticator)"; warnings=$((warnings+1))
  elif systemctl is-enabled certbot.timer >/dev/null 2>&1; then
    pass "Automatic TLS renewal timer"
  else
    fail "Automatic TLS authenticator exists but certbot.timer is disabled"; failures=$((failures+1))
  fi
  if [[ "$(get_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX)" == "true" && "$(get_env ENABLE_CHUNK_DATA_CACHE_INDEX)" == "true" ]]; then
    pass "Native indexed cache eviction enabled"
  elif [[ -n "$(get_env CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD)" && "$(get_env ENABLE_CHUNK_DATA_CACHE_CLEANUP)" == "true" ]]; then
    pass "Native TTL cache cleanup enabled"
  else
    warn "Native cache protection is not fully enabled"
    warnings=$((warnings+1))
  fi
  if [[ "$(get_env RUN_AUTOHEAL)" == "true" ]]; then pass "Container autoheal enabled"; else warn "RUN_AUTOHEAL is not enabled"; warnings=$((warnings+1)); fi
  if [[ "$(get_env ENABLE_X_402_USDC_DATA_EGRESS)" == "true" && "$(get_env ENABLE_RATE_LIMITER)" != "true" ]]; then
    fail "x402 is enabled without the required rate limiter"; failures=$((failures+1))
  fi
  order="$(get_env ROOT_TX_LOOKUP_ORDER)"
  if [[ -n "$order" && ",$order," != *,cdb,* ]]; then warn "CDB64 is absent from the explicit root lookup order"; warnings=$((warnings+1)); else pass "CDB64 root lookup available by default or explicitly"; fi

  local service container_port published
  for service in envoy core observer; do
    case "$service" in envoy) container_port=3000;; core) container_port=4000;; observer) container_port=5050;; esac
    published="$(compose port "$service" "$container_port" 2>/dev/null || true)"
    if grep -Eq '^(0\.0\.0\.0|\[::\]|:::)' <<< "$published"; then
      warn "$service port $container_port is published on all interfaces; restrict it with the provider firewall if only NGINX should be public"
      warnings=$((warnings+1))
    fi
  done

  local wallet_key observer_key path mode
  wallet_key="$(get_env SOLANA_KEYPAIR_PATH)"
  observer_key="$(get_env OBSERVER_KEYPAIR_PATH)"
  for path in "$wallet_key" "$observer_key"; do
    [[ -n "$path" ]] || continue
    path="$INSTALL_DIR/${path#/app/}"
    if [[ -f "$path" ]]; then
      mode="$(stat -c '%a' "$path")"
      [[ "$mode" == "600" ]] && pass "Keyfile permissions: $path" || { warn "Keyfile mode $mode: $path"; warnings=$((warnings+1)); }
    else
      fail "Missing keyfile: $path"; failures=$((failures+1))
    fi
  done

  echo
  compose ps || true
  echo
  if (( failures == 0 )); then
    pass "Doctor completed with $warnings warning(s) and no failures."
  else
    fail "Doctor found $failures failure(s) and $warnings warning(s)."
    return 1
  fi
}

write_manager_config() {
  require_root
  local dir="${1:-$INSTALL_DIR}"
  [[ -n "$dir" ]] || die "Install directory is required."
  install -d -m 755 "$(dirname "$CONFIG_FILE")"
  printf "INSTALL_DIR=%s\n" "$dir" > "$CONFIG_FILE"
  chmod 644 "$CONFIG_FILE"
}

cmd_install_links() {
  require_root
  [[ -n "$INSTALL_DIR" ]] || INSTALL_DIR="${1:-}"
  resolve_install_dir
  write_manager_config "$INSTALL_DIR"
  local target="$(readlink -f "$0")"
  local command
  for command in \
    gateway gateway-help gateway-check gateway-doctor gateway-status gateway-logs \
    gateway-release-check gateway-update gateway-restart gateway-balance gateway-observer-check \
    gateway-network-info \
    gateway-storage gateway-storage-setup gateway-cert-check gateway-cert-setup gateway-cert-manual \
    gateway-renew-cert gateway-x402-check gateway-enable-x402 gateway-grafana \
    gateway-filters gateway-block-name gateway-unblock-name gateway-features \
    gateway-apex gateway-verification gateway-cdb64-check gateway-cache-advisor \
    gateway-network-readiness gateway-guides gateway-tools-update; do
    ln -sfn "$target" "/usr/local/bin/$command"
  done
  pass "Gateway helper commands installed. Run gateway-help."
}

cmd_tools_update() {
  require_root
  resolve_install_dir
  local target temp
  target="$(readlink -f "$0")"
  temp="$(mktemp)"
  curl -fsSL "$MANAGER_URL" -o "$temp"
  bash -n "$temp"
  chmod 755 "$temp"
  mv "$temp" "$target"
  INSTALL_DIR="$INSTALL_DIR" "$target" install-links "$INSTALL_DIR"
  pass "Gateway helper commands updated."
}

dispatch() {
  local invoked command
  invoked="$(basename "$0")"
  command="${1:-}"
  if [[ "$invoked" == "gateway-manager.sh" || "$invoked" == "manager.sh" ]]; then
    [[ -n "$command" ]] || command="menu"
    shift || true
  else
    command="${invoked#gateway-}"
    [[ "$invoked" == "gateway" ]] && command="menu"
  fi

  case "$command" in
    menu) cmd_menu "$@" ;;
    help) cmd_help ;;
    check) cmd_check "$@" ;;
    doctor) cmd_doctor "$@" ;;
    status) cmd_status "$@" ;;
    logs) cmd_logs "$@" ;;
    release-check) cmd_release_check "$@" ;;
    update) cmd_update "$@" ;;
    restart) cmd_restart "$@" ;;
    balance) cmd_balance "$@" ;;
    network-info) cmd_network_info "$@" ;;
    observer-check) cmd_observer_check "$@" ;;
    storage) cmd_storage "$@" ;;
    storage-setup) cmd_storage_setup "$@" ;;
    cert-check) cmd_cert_check "$@" ;;
    cert-setup) cmd_cert_setup "$@" ;;
    cert-manual) cmd_cert_manual "$@" ;;
    renew-cert) cmd_renew_cert "$@" ;;
    x402-check) cmd_x402_check "$@" ;;
    enable-x402) cmd_enable_x402 "$@" ;;
    grafana) cmd_grafana "$@" ;;
    filters) cmd_filters "$@" ;;
    apex) cmd_apex "$@" ;;
    verification) cmd_verification "$@" ;;
    cdb64-check) cmd_cdb64_check "$@" ;;
    cache-advisor) cmd_cache_advisor "$@" ;;
    guides) cmd_guides ;;
    block-name) cmd_block_name "$@" ;;
    unblock-name) cmd_unblock_name "$@" ;;
    features) cmd_features "$@" ;;
    network-readiness) cmd_network_readiness "$@" ;;
    tools-update) cmd_tools_update "$@" ;;
    install-links) cmd_install_links "$@" ;;
    *) cmd_help; die "Unknown command: $command" ;;
  esac
}

if [[ "${GATEWAY_MANAGER_LIB_ONLY:-false}" != "true" ]]; then
  dispatch "$@"
fi
