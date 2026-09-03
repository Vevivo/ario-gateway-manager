#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-/opt/ar-io-gateway}"
MANAGER_URL="${GATEWAY_MANAGER_URL:-https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/gateway-manager.sh}"
DOMAIN="${ARNS_ROOT_HOST:-${DOMAIN:-}}"
AR_IO_WALLET="${AR_IO_WALLET:-${ARIO_WALLET:-}}"
OBSERVER_WALLET="${OBSERVER_WALLET:-}"
GRAPHQL_HOST="${GRAPHQL_HOST:-turbo-gateway.com}"
GRAPHQL_PORT="${GRAPHQL_PORT:-443}"
START_HEIGHT="${START_HEIGHT:-1800000}"
SOLANA_RPC_URL="${SOLANA_RPC_URL:-https://api.mainnet-beta.solana.com}"
GATEWAY_TEST_TX="3lyxgbgEvqNSvJrTX2J7CfRychUD5KClFhhVLyTPNCQ"
ENABLE_EPOCH_CRANKING="false"

STORAGE_PROTECTION_ENABLED="true"
STORAGE_PROFILE="${STORAGE_PROFILE:-indexed}"
STORAGE_HIGH_WATERMARK="90"
STORAGE_LOW_WATERMARK="85"
STORAGE_MIN_FREE_GIB="20"
STORAGE_TTL_SECONDS="14400"
CERT_MODE="${CERT_MODE:-namecheap}"
CLOUDFLARE_API_TOKEN=""
NAMECHEAP_USERNAME="${NAMECHEAP_USERNAME:-}"
NAMECHEAP_API_KEY=""

ARIO_CORE_PROGRAM_ID="73YoECm6NKXpVRoe5f1Q9BcP5DJGPFUjnFy6AxBE5Nvh"
ARIO_GAR_PROGRAM_ID="89fNiiwgpFSPHKuqfNUkgYTYjtAJAhyqHjXmgXeppGpf"
ARIO_ARNS_PROGRAM_ID="2yCUx5edFvUrkibYaUa2ZXWyx9kuJkS8CwyzsgHPWdZZ"
ARIO_ANT_PROGRAM_ID="2MWexMHfMhGJwMHv9Qm9YAVCqjUFUJwDJAysW4oCUGk5"

X402_ENABLED="false"
X402_NETWORK="base"
X402_WALLET_ADDRESS=""
X402_FACILITATOR_URL="https://facilitator.x402.rs"
X402_PER_BYTE_PRICE="0.0000000001"
X402_MIN_PRICE="0.001"
X402_MAX_PRICE="1.00"
X402_CAPACITY_MULTIPLIER="10"
X402_APP_NAME=""
X402_APP_LOGO=""
X402_CDP_CLIENT_KEY=""
CDP_API_KEY_ID=""
CDP_SECRET_VALUE=""
CHUNK_GET_BASE64_SIZE_BYTES="368640"
RATE_LIMITER_TYPE="redis"
RATE_LIMITER_REDIS_ENDPOINT="redis://redis:6379"
RATE_LIMITER_IP_BUCKET="100000"
RATE_LIMITER_IP_REFILL="20"
RATE_LIMITER_RESOURCE_BUCKET="1000000"
RATE_LIMITER_RESOURCE_REFILL="100"
RATE_LIMITER_IP_ALLOWLIST=""
RATE_LIMITER_ARNS_ALLOWLIST=""
EXTRA_REDIS_FLAGS="--save 300 10 --appendonly yes --appendfsync everysec"
ENABLE_DEBUG_LOGS="false"
INSTALL_MODE="easy"

log() { printf "%b\n" "${CYAN}==>${NC} $*"; }
ok() { printf "%b\n" "${GREEN}OK${NC} $*"; }
warn() { printf "%b\n" "${YELLOW}WARN${NC} $*"; }
die() { printf "%b\n" "${RED}ERROR${NC} $*" >&2; exit 1; }

prompt() {
  local label="$1"
  local default="${2:-}"
  local value=""
  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$label" "$default" >&2
    read -r value < /dev/tty
    printf "%s" "${value:-$default}"
  else
    printf "%s: " "$label" >&2
    read -r value < /dev/tty
    printf "%s" "$value"
  fi
}

confirm() {
  local label="$1"
  local default="${2:-n}"
  local suffix="[y/N]"
  local value=""
  [[ "$default" == "y" ]] && suffix="[Y/n]"
  printf "%s %s: " "$label" "$suffix" >&2
  read -r value < /dev/tty
  value="${value:-$default}"
  value="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "y" || "$value" == "yes" || "$value" == "e" || "$value" == "evet" ]]
}

normalize_domain() {
  local raw="$1"
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  printf "%s" "$raw" | tr '[:upper:]' '[:lower:]'
}

is_evm_address() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]
}

is_decimal() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_domain() {
  [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}

is_solana_address() {
  [[ "$1" =~ ^[1-9A-HJ-NP-Za-km-z]{32,44}$ ]]
}

storage_values_valid() {
  local low="$1"
  local high="$2"
  [[ "$low" =~ ^[0-9]+$ && "$high" =~ ^[0-9]+$ ]] || return 1
  (( low >= 1 && high <= 99 && low < high ))
}

normalize_solana_rpc_url() {
  local value="$1"
  if [[ "$value" =~ ^[0-9a-fA-F-]{32,}$ ]]; then
    warn "That looks like a Helius API key, not a full RPC URL. Expanding it to the Helius mainnet endpoint."
    printf "https://mainnet.helius-rpc.com/?api-key=%s" "$value"
    return
  fi
  printf "%s" "$value"
}

validate_solana_rpc_url() {
  local value="$1"
  [[ "$value" =~ ^https?:// ]] || die "Solana RPC URL must start with https:// or http://. Example: https://mainnet.helius-rpc.com/?api-key=YOUR_KEY"
  if [[ "$value" == *"api-mainnet.helius-rpc.com"* || "$value" == *"/v0/transactions"* || "$value" == *"/v0/addresses"* ]]; then
    die "This is a Helius Enhanced API URL, not a Solana RPC URL. Use the RPCs panel URL: https://mainnet.helius-rpc.com/?api-key=YOUR_KEY"
  fi
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Please run as root: sudo bash install-gateway.sh"
}

guard_new_install() {
  [[ "${ALLOW_EXISTING_INSTALL:-false}" == "true" ]] && return
  if [[ -f "$INSTALL_DIR/.env" || -d "$INSTALL_DIR/data/sqlite" ]]; then
    die "Existing gateway data found in $INSTALL_DIR. Do not run the full installer again. Use update-tools.sh or gateway-update. For an intentional recovery run, set ALLOW_EXISTING_INSTALL=true."
  fi
  if [[ "$INSTALL_DIR" == "/opt/ar-io-gateway" && -f /opt/ar-io-node/.env ]]; then
    die "An existing gateway was found in /opt/ar-io-node. Use update-tools.sh or gateway-update instead of creating a second installation."
  fi
}

version_at_least() {
  local actual="${1#v}"
  local required="${2#v}"
  [[ "$(printf '%s\n' "$required" "$actual" | sort -V | head -n1)" == "$required" ]]
}

header() {
  clear || true
  cat <<'EOF'
░  ░░░░  ░░        ░░  ░░░░  ░░        ░░  ░░░░  ░░░      ░░
▒  ▒▒▒▒  ▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒
▓▓  ▓▓  ▓▓▓      ▓▓▓▓▓  ▓▓  ▓▓▓▓▓▓  ▓▓▓▓▓▓  ▓▓  ▓▓▓  ▓▓▓▓  ▓
███    ████  ██████████    ███████  ███████    ████  ████  █
████  █████        █████  █████        █████  ██████      ██

      Welcome to the First Permanent Cloud Network
         --- AR.IO Gateway Manager by Vevivo ---

                Solana-era production setup
EOF
  echo
  echo "Bu kurucu AR.IO gateway, observer, NGINX, otomatik SSL ve disk"
  echo "korumasini kurar. Kolay mod ilk kurulum icin onerilen ayarlari kullanir."
  echo
  echo "Not: Gateway'i AR.IO Network'e kaydetmez ve stake islemi yapmaz."
  echo
}

collect_config() {
  log "[1/8] Kurulum modu"

  cat <<'MODE_OPTIONS'
Kurulum modu:
  1) Kolay kurulum (onerilen)
     Yalniz gerekli bilgileri sorar. Guvenli disk ayarlari acik,
     observer yuklemeleri Turbo, cranking ve x402 kapali kurulur.

  2) Gelismis kurulum
     Depolama, SSL saglayicisi, AR upload, cranking ve x402 seceneklerini sorar.
MODE_OPTIONS
  local mode_choice
  mode_choice="$(prompt "Seciminiz" "1")"
  case "$mode_choice" in
    1) INSTALL_MODE="easy" ;;
    2) INSTALL_MODE="advanced" ;;
    *) die "Kurulum modu 1 veya 2 olmali." ;;
  esac

  echo
  log "Gerekli gateway bilgileri"
  echo "Namecheap'te @ ve * A kayitlarini yonlendirdiginiz domaini yazin."
  echo "Ornek: example.com  (https:// veya *. yazmayin)"

  DOMAIN="$(normalize_domain "$(prompt "Gateway alan adi" "$DOMAIN")")"
  is_domain "$DOMAIN" || die "example.com gibi gecerli bir alan adi girin; https://, yol veya *. eklemeyin."

  echo
  echo "AR.IO kaydinizdaki ana/operator Solana PUBLIC adresini yazin."
  echo "Bu alana seed phrase veya private key yazmayin."
  AR_IO_WALLET="$(prompt "Ana Solana gateway adresi" "$AR_IO_WALLET")"
  is_solana_address "$AR_IO_WALLET" || die "Ana wallet gecerli bir Solana public adresi olmali."

  if [[ -z "$OBSERVER_WALLET" ]]; then
    OBSERVER_WALLET="$AR_IO_WALLET"
  fi
  echo
  echo "Observer icin ayni wallet'i kullaniyorsaniz sadece Enter'a basin."
  echo "AR.IO kaydinizda ayri observer varsa onun PUBLIC adresini yazin."
  OBSERVER_WALLET="$(prompt "Observer Solana adresi (Enter = ana wallet ile ayni)" "$OBSERVER_WALLET")"
  is_solana_address "$OBSERVER_WALLET" || die "Observer wallet gecerli bir Solana public adresi olmali."
  if [[ "$OBSERVER_WALLET" == "$AR_IO_WALLET" ]]; then
    ok "Observer ana Solana wallet ile ayni olacak."
  else
    ok "Ayri observer wallet kullanilacak: ${OBSERVER_WALLET}"
  fi

  echo
  echo "Solana RPC saglayicinizdaki TAM mainnet URL'sini yapistirin."
  echo "Helius ornegi: https://mainnet.helius-rpc.com/?api-key=..."
  echo "URL'niz yoksa Enter public RPC'yi kullanir; uretimde ozel RPC onerilir."
  SOLANA_RPC_URL="$(prompt "Solana RPC URL" "$SOLANA_RPC_URL")"
  SOLANA_RPC_URL="$(normalize_solana_rpc_url "$SOLANA_RPC_URL")"
  validate_solana_rpc_url "$SOLANA_RPC_URL"

  echo
  if [[ "$INSTALL_MODE" == "easy" ]]; then
    STORAGE_PROTECTION_ENABLED="true"
    STORAGE_PROFILE="indexed"
    ok "Disk korumasi: %90'da baslat, %85'e indir, 20 GiB bos alan koru."
  else
    echo "Disk korumasi ar-io-node'un kendi cache temizleyicilerini kullanir."
    echo "Onerilen: %90'da baslat, %85'in altina indir, 20 GiB bos alan koru."
    if confirm "Otomatik disk korumasi acilsin mi" "y"; then
    STORAGE_PROTECTION_ENABLED="true"
    cat <<'STORAGE_OPTIONS'
Depolama profili:
  1) Indexed eviction - uretim/buyuk cache (onerilen)
  2) TTL filesystem walk - kucuk SSD cache
STORAGE_OPTIONS
    local storage_choice
    storage_choice="$(prompt "Depolama profili" "1")"
    case "$storage_choice" in
      1) STORAGE_PROFILE="indexed" ;;
      2)
        STORAGE_PROFILE="ttl"
        STORAGE_TTL_SECONDS="$(prompt "Cache saklama suresi (saniye)" "$STORAGE_TTL_SECONDS")"
        [[ "$STORAGE_TTL_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "Cache suresi pozitif tam sayi olmali."
        ;;
      *) die "Depolama profili 1 veya 2 olmali." ;;
    esac
    if ! confirm "Onerilen %90 / %85 / 20 GiB degerleri kullanilsin mi" "y"; then
      STORAGE_HIGH_WATERMARK="$(prompt "Temizligi baslatma yuzdesi" "$STORAGE_HIGH_WATERMARK")"
      STORAGE_LOW_WATERMARK="$(prompt "Temizligi durdurma yuzdesi" "$STORAGE_LOW_WATERMARK")"
      STORAGE_MIN_FREE_GIB="$(prompt "Korunacak bos alan (GiB)" "$STORAGE_MIN_FREE_GIB")"
      storage_values_valid "$STORAGE_LOW_WATERMARK" "$STORAGE_HIGH_WATERMARK" || die "1 <= dusuk esik < yuksek esik <= 99 olmali."
      [[ "$STORAGE_MIN_FREE_GIB" =~ ^[0-9]+$ ]] || die "Bos alan tam sayi GiB olmali."
    fi
    else
      STORAGE_PROTECTION_ENABLED="false"
    fi
  fi

  echo
  local cert_choice
  if [[ "$INSTALL_MODE" == "easy" ]]; then
    cert_choice="1"
    ok "SSL yontemi: Namecheap DNS API ile otomatik yenileme."
  else
    cat <<'SSL_OPTIONS'
Wildcard SSL yenileme yontemi:
  1) Namecheap DNS API - otomatik yenileme (onerilen)
  2) Cloudflare DNS API - otomatik yenileme
  3) Manuel DNS TXT - her saglayicida calisir, otomatik yenilenmez
SSL_OPTIONS
    cert_choice="$(prompt "SSL yontemi" "1")"
  fi
  case "$cert_choice" in
    1)
      CERT_MODE="namecheap"
      local public_ipv4
      echo "Namecheap hesabinizda API erisimini acin ve asagidaki IPv4'u whitelist'e ekleyin."
      warn "Namecheap API erisimi hesap kosullarina bagli olabilir; panel izin vermiyorsa Namecheap destekle gorusun."
      public_ipv4="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
      echo "Sunucu public IPv4: ${public_ipv4:-tespit edilemedi}"
      echo "Namecheap: Profile -> Tools -> Namecheap API Access -> Whitelisted IPs"
      confirm "API erisimi acik ve bu IPv4 whitelist'e eklendi mi" "n" || die "Namecheap API ve IPv4 whitelist ayarini tamamlayip kurulumu tekrar calistirin."
      NAMECHEAP_USERNAME="$(prompt "Namecheap kullanici adi" "$NAMECHEAP_USERNAME")"
      printf "Namecheap API key (yazdiginiz gorunmez): " >&2
      read -r -s NAMECHEAP_API_KEY < /dev/tty
      printf "\n" >&2
      [[ -n "$NAMECHEAP_USERNAME" && -n "$NAMECHEAP_API_KEY" ]] || die "Namecheap kullanici adi ve API key zorunlu."
      ;;
    2)
      CERT_MODE="cloudflare"
      echo "Create a Cloudflare API token limited to Zone:Read and DNS:Edit for this domain."
      printf "Cloudflare API token (hidden): " >&2
      read -r -s CLOUDFLARE_API_TOKEN < /dev/tty
      printf "\n" >&2
      [[ -n "$CLOUDFLARE_API_TOKEN" ]] || die "Cloudflare API token cannot be empty."
      ;;
    3) CERT_MODE="manual" ;;
    *) die "SSL method must be 1, 2, or 3." ;;
  esac

  REPORT_DATA_SINK=""
  if [[ "$INSTALL_MODE" == "advanced" ]]; then
    if confirm "Observer yuklemelerinde Turbo yerine AR token kullanilsin mi" "n"; then
      REPORT_DATA_SINK="arweave"
    fi

    echo
    warn "Ana/operator Solana keypair, cranking kapali olsa da gereklidir."
    if confirm "Opsiyonel epoch cranking acilsin mi (SOL harcar)" "n"; then
      ENABLE_EPOCH_CRANKING="true"
    fi
  else
    ok "Observer upload: Turbo | Epoch cranking: kapali | x402: kapali"
  fi

  if [[ "$INSTALL_MODE" == "advanced" ]] && confirm "Opsiyonel x402 USDC odemeleri acilsin mi" "n"; then
    X402_ENABLED="true"
    echo
    echo "x402 mainnet defaults will be used. You need an EVM/Base USDC receiver wallet."
    RATE_LIMITER_TYPE="$(prompt "Rate limiter type" "$RATE_LIMITER_TYPE")"
    [[ "$RATE_LIMITER_TYPE" == "redis" || "$RATE_LIMITER_TYPE" == "memory" ]] || die "Rate limiter type must be redis or memory."
    if [[ "$RATE_LIMITER_TYPE" == "redis" ]]; then
      RATE_LIMITER_REDIS_ENDPOINT="$(prompt "Redis endpoint" "$RATE_LIMITER_REDIS_ENDPOINT")"
      EXTRA_REDIS_FLAGS="$(prompt "Redis persistence flags" "$EXTRA_REDIS_FLAGS")"
    fi
    RATE_LIMITER_IP_BUCKET="$(prompt "RATE_LIMITER_IP_TOKENS_PER_BUCKET" "$RATE_LIMITER_IP_BUCKET")"
    RATE_LIMITER_IP_REFILL="$(prompt "RATE_LIMITER_IP_REFILL_PER_SEC" "$RATE_LIMITER_IP_REFILL")"
    RATE_LIMITER_RESOURCE_BUCKET="$(prompt "RATE_LIMITER_RESOURCE_TOKENS_PER_BUCKET" "$RATE_LIMITER_RESOURCE_BUCKET")"
    RATE_LIMITER_RESOURCE_REFILL="$(prompt "RATE_LIMITER_RESOURCE_REFILL_PER_SEC" "$RATE_LIMITER_RESOURCE_REFILL")"
    [[ "$RATE_LIMITER_IP_BUCKET" =~ ^[0-9]+$ && "$RATE_LIMITER_IP_REFILL" =~ ^[0-9]+$ && "$RATE_LIMITER_RESOURCE_BUCKET" =~ ^[0-9]+$ && "$RATE_LIMITER_RESOURCE_REFILL" =~ ^[0-9]+$ ]] || die "Rate limit values must be whole numbers."

    X402_NETWORK="$(prompt "x402 network: base for mainnet, base-sepolia for testnet" "$X402_NETWORK")"
    [[ "$X402_NETWORK" == "base" || "$X402_NETWORK" == "base-sepolia" ]] || die "x402 network must be base or base-sepolia."
    if [[ "$X402_NETWORK" == "base-sepolia" && "$X402_FACILITATOR_URL" == "https://facilitator.x402.rs" ]]; then
      X402_FACILITATOR_URL="https://x402.org/facilitator"
    fi
    X402_WALLET_ADDRESS="$(prompt "x402 EVM/Base USDC receiver wallet address" "$X402_WALLET_ADDRESS")"
    is_evm_address "$X402_WALLET_ADDRESS" || die "x402 requires a valid EVM/Base address like 0x..."
    X402_FACILITATOR_URL="$(prompt "x402 facilitator URL" "$X402_FACILITATOR_URL")"
    X402_PER_BYTE_PRICE="$(prompt "x402 per-byte price" "$X402_PER_BYTE_PRICE")"
    X402_MIN_PRICE="$(prompt "x402 min price" "$X402_MIN_PRICE")"
    X402_MAX_PRICE="$(prompt "x402 max price" "$X402_MAX_PRICE")"
    X402_CAPACITY_MULTIPLIER="$(prompt "x402 capacity multiplier" "$X402_CAPACITY_MULTIPLIER")"
    [[ "$X402_FACILITATOR_URL" =~ ^https?://[^[:space:]]+$ ]] || die "x402 facilitator must be an HTTP(S) URL."
    is_decimal "$X402_PER_BYTE_PRICE" && is_decimal "$X402_MIN_PRICE" && is_decimal "$X402_MAX_PRICE" || die "x402 prices must be non-negative decimal numbers."
    [[ "$X402_CAPACITY_MULTIPLIER" =~ ^[1-9][0-9]*$ ]] || die "x402 capacity multiplier must be a positive whole number."
    awk -v min="$X402_MIN_PRICE" -v max="$X402_MAX_PRICE" 'BEGIN { exit !(min <= max) }' || die "x402 minimum charge cannot exceed maximum charge."

    X402_APP_NAME="$(prompt "Paywall app name" "${DOMAIN:-My ar.io Gateway}")"
    X402_APP_LOGO="$(prompt "Paywall app logo URL, blank allowed" "")"
    CHUNK_GET_BASE64_SIZE_BYTES="$(prompt "CHUNK_GET_BASE64_SIZE_BYTES" "$CHUNK_GET_BASE64_SIZE_BYTES")"
    [[ "$CHUNK_GET_BASE64_SIZE_BYTES" =~ ^[0-9]+$ ]] || die "CHUNK_GET_BASE64_SIZE_BYTES must be a whole number."
    RATE_LIMITER_IP_ALLOWLIST="$(prompt "IP/CIDR allowlist, comma-separated, blank allowed" "")"
    RATE_LIMITER_ARNS_ALLOWLIST="$(prompt "ArNS allowlist, comma-separated, blank allowed" "")"

    if confirm "Enable x402 debug logging / LOG_LEVEL=debug" "n"; then
      ENABLE_DEBUG_LOGS="true"
    fi

    if confirm "Configure optional Coinbase CDP onramp keys now" "n"; then
      CDP_API_KEY_ID="$(prompt "CDP_API_KEY_ID" "")"
      X402_CDP_CLIENT_KEY="$(prompt "X_402_CDP_CLIENT_KEY public client key" "")"
      printf "Paste CDP API secret key (hidden, blank to skip): " >&2
      read -r -s CDP_SECRET_VALUE < /dev/tty
      printf "\n" >&2
    fi
  fi

  echo
  echo "Kurulum ozeti:"
  echo "  Domain:            ${DOMAIN}"
  echo "  Operator wallet:   ${AR_IO_WALLET}"
  echo "  Observer wallet:   ${OBSERVER_WALLET}"
  echo "  Depolama korumasi: ${STORAGE_PROTECTION_ENABLED} (${STORAGE_PROFILE})"
  echo "  SSL:               ${CERT_MODE}"
  echo "  Epoch cranking:    ${ENABLE_EPOCH_CRANKING}"
  echo "  x402:              ${X402_ENABLED}"
  confirm "Bu ayarlarla kurulumu baslatayim mi" "y" || die "Kurulum kullanici tarafindan iptal edildi."
}

preflight() {
  log "Kurulum oncesi kontroller"
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *[[:space:]]* ]] || die "INSTALL_DIR must be an absolute path without whitespace."
  command -v apt-get >/dev/null 2>&1 || die "This installer requires a Debian/Ubuntu system with apt-get."
  [[ -f /etc/os-release ]] || die "Cannot identify the operating system."
  local os_id cpu_count memory_gib disk_gib disk_probe warnings=0
  os_id="$(. /etc/os-release && printf "%s" "${ID:-unknown}")"
  [[ "$os_id" == "ubuntu" || "$os_id" == "debian" ]] || die "Supported operating systems are Ubuntu and Debian (detected: $os_id)."
  cpu_count="$(nproc)"
  memory_gib="$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))"
  disk_probe="$(dirname "$INSTALL_DIR")"
  while [[ ! -e "$disk_probe" && "$disk_probe" != "/" ]]; do disk_probe="$(dirname "$disk_probe")"; done
  disk_gib="$(( $(df -Pk "$disk_probe" | awk 'NR==2 {print $2}') / 1024 / 1024 ))"
  echo "Tespit edilen: ${cpu_count} CPU, ${memory_gib} GiB RAM, ${disk_gib} GiB disk"
  (( cpu_count >= 4 )) || { warn "Resmi minimum 4 CPU core."; warnings=$((warnings+1)); }
  (( memory_gib >= 4 )) || { warn "Resmi minimum 4 GiB RAM."; warnings=$((warnings+1)); }
  (( disk_gib >= 500 )) || { warn "Resmi minimum 500 GB; onerilen depolama 2 TB SSD."; warnings=$((warnings+1)); }
  if (( warnings > 0 )); then
    confirm "Resmi minimumlardan dusuk olmasina ragmen devam edilsin mi" "n" || die "Kurulum on kontrolde iptal edildi."
  fi

  if command -v ss >/dev/null 2>&1; then
    local port listener
    for port in 3000 4000 5050; do
      listener="$(ss -H -ltnp 2>/dev/null | awk -v suffix=":${port}" '$4 ~ suffix "$" { print; exit }')"
      [[ -z "$listener" ]] || die "Port ${port} is already in use by another project: ${listener}"
    done
    for port in 80 443; do
      listener="$(ss -H -ltnp 2>/dev/null | awk -v suffix=":${port}" '$4 ~ suffix "$" { print; exit }')"
      if [[ -n "$listener" && "$listener" != *nginx* ]]; then
        die "Port ${port} is already used by a non-NGINX service: ${listener}. The installer will not replace or interrupt it."
      fi
    done
  else
    warn "Port conflicts could not be checked because the ss command is unavailable."
  fi

  if [[ -d /etc/nginx/sites-enabled ]]; then
    local site intended_site
    intended_site="/etc/nginx/sites-available/ar-io-${DOMAIN//./-}.conf"
    while IFS= read -r site; do
      [[ "$(readlink -f "$site" 2>/dev/null || true)" == "$intended_site" ]] && continue
      if grep -Fq "$DOMAIN" "$site" 2>/dev/null; then
        die "Another NGINX site already mentions ${DOMAIN}: ${site}. The installer will not overwrite it."
      fi
    done < <(find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -print)
  fi

  local apex_dns wildcard_dns
  apex_dns="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')"
  wildcard_dns="$(getent ahostsv4 "gateway-check-${RANDOM}.${DOMAIN}" 2>/dev/null | awk 'NR==1 {print $1}')"
  echo "DNS ana domain: ${apex_dns:-cozumlenemedi} | wildcard: ${wildcard_dns:-cozumlenemedi}"
  if [[ -z "$apex_dns" || -z "$wildcard_dns" ]]; then
    warn "Sertifika icin ana domain ve wildcard DNS kayitlarinin ikisi de cozumlenmeli."
    confirm "DNS hala yayiliyor; yine de devam edilsin mi" "n" || die "DNS kayitlarini duzeltip kurulumu tekrar calistirin."
  fi
}

install_packages() {
  log "[2/8] Installing base packages"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install --no-upgrade -y \
    curl openssh-server git certbot nginx sqlite3 build-essential \
    ca-certificates gnupg jq ufw lsb-release openssl dnsutils python3
  if [[ "$CERT_MODE" == "cloudflare" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get install --no-upgrade -y python3-certbot-dns-cloudflare
  elif [[ "$CERT_MODE" == "namecheap" ]]; then
    local pip_args=()
    DEBIAN_FRONTEND=noninteractive apt-get install --no-upgrade -y python3-pip
    if python3 -m pip help install 2>/dev/null | grep -q -- '--break-system-packages'; then
      pip_args=(--break-system-packages)
    fi
    python3 -m pip install "${pip_args[@]}" certbot-dns-namecheap
    certbot plugins | grep -q 'dns-namecheap' || die "Certbot could not load the Namecheap plugin."
  fi
  systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true
}

install_docker() {
  log "[3/8] Installing Docker"
  if command -v docker >/dev/null 2>&1; then
    docker compose version >/dev/null 2>&1 || die "Docker is already installed, but the Compose plugin is missing. Install Docker Compose 2.24.4 or newer; this installer will not replace a shared Docker engine."
    local compose_version
    compose_version="$(docker compose version --short 2>/dev/null | tr -d '[:space:]')"
    version_at_least "$compose_version" "2.24.4" || die "Docker Compose ${compose_version:-unknown} is too old. Version 2.24.4 or newer is required for safe port isolation."
    ok "Existing Docker engine kept unchanged; compatible Docker Compose ${compose_version} found."
    systemctl is-active --quiet docker || systemctl start docker
    systemctl enable docker >/dev/null 2>&1 || true
    return
  fi

  install -m 0755 -d /etc/apt/keyrings
  . /etc/os-release
  local distro="${ID:-ubuntu}"
  local codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || codename="$(lsb_release -cs)"
  curl -fsSL "https://download.docker.com/linux/${distro}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro} ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

clone_node() {
  log "[4/8] Installing ar-io-node"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    cd "$INSTALL_DIR"
    git checkout main
    git pull --ff-only origin main
  else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone -b main https://github.com/ar-io/ar-io-node "$INSTALL_DIR"
  fi
}

write_env() {
  log "[5/8] Writing .env"
  cd "$INSTALL_DIR"
  local admin_key compose_project
  local existing_admin_key=""
  local log_level="info"
  if [[ -f .env ]]; then
    existing_admin_key="$(grep -E '^ADMIN_API_KEY=' .env | tail -n1 | cut -d= -f2- || true)"
    cp .env ".env.backup.$(date +%Y%m%d-%H%M%S)"
  fi
  admin_key="${existing_admin_key:-$(openssl rand -hex 32)}"
  compose_project="ario_gateway_$(printf "%s" "$DOMAIN" | tr '.' '_' | tr -cd 'a-z0-9_-')"
  [[ "$ENABLE_DEBUG_LOGS" == "true" ]] && log_level="debug"

  umask 077
  cat > .env <<EOF
# Generated by Vevivo AR.IO Gateway Manager
COMPOSE_PROJECT_NAME=${compose_project}
COMPOSE_FILE=docker-compose.yaml:docker-compose.ario.yaml
DOCKER_NETWORK_NAME=${compose_project}_ar-io-network
NODE_ENV=production
LOG_LEVEL=${log_level}
ADMIN_API_KEY=${admin_key}

GRAPHQL_HOST=${GRAPHQL_HOST}
GRAPHQL_PORT=${GRAPHQL_PORT}
START_HEIGHT=${START_HEIGHT}
START_WRITERS=true

RUN_OBSERVER=true
ARNS_ROOT_HOST=${DOMAIN}
AR_IO_WALLET=${AR_IO_WALLET}
OBSERVER_WALLET=${OBSERVER_WALLET}
SOLANA_RPC_URL=${SOLANA_RPC_URL}
SOLANA_KEYPAIR_PATH=/app/wallets/${AR_IO_WALLET}.json
OBSERVER_KEYPAIR_PATH=/app/wallets/${OBSERVER_WALLET}.json
SOLANA_UPLOAD_KEYPAIR_PATH=/app/wallets/${OBSERVER_WALLET}.json
ENABLE_EPOCH_CRANKING=${ENABLE_EPOCH_CRANKING}

ARIO_CORE_PROGRAM_ID=${ARIO_CORE_PROGRAM_ID}
ARIO_GAR_PROGRAM_ID=${ARIO_GAR_PROGRAM_ID}
ARIO_ARNS_PROGRAM_ID=${ARIO_ARNS_PROGRAM_ID}
ARIO_ANT_PROGRAM_ID=${ARIO_ANT_PROGRAM_ID}

SANDBOX_PROTOCOL=https
HTTPSIG_ENABLED=true
HTTPSIG_BIND_REQUEST=true

ARNS_RESOLVER_PRIORITY_ORDER=on-demand,gateway
ARNS_COMPOSITE_RESOLVER_TIMEOUT_MS=3000
ARNS_CACHE_TTL_SECONDS=3600
TRUSTED_GATEWAYS_REQUEST_TIMEOUT_MS=10000
GRAPHQL_ON_DEMAND_RESOLUTION_ENABLED=true
GRAPHQL_ON_DEMAND_RESOLUTION_TIMEOUT_MS=5000
GRAPHQL_ON_DEMAND_RESOLUTION_MAX_CONCURRENT=1
PEER_HEDGE_DELAY_MS=500
PEER_MAX_HEDGED_REQUESTS=2
BUNDLE_REPAIR_RETRY_INTERVAL_SECONDS=60
BUNDLE_REPAIR_RETRY_BATCH_SIZE=100
CACHE_NOT_FOUND_MAX_AGE=60
CACHE_APEX_MAX_AGE=3600
GRAPHQL_RESOLVER_DEADLINE_MS=12000
BUNDLE_DATA_ITEM_DRAIN_BATCH=100
DATA_ITEM_INDEXER_QUEUE_SIZE=500000
ANS104_DATA_INDEXER_QUEUE_SIZE=500000

RUN_AUTOHEAL=true
EOF

  if [[ "$STORAGE_PROTECTION_ENABLED" == "true" ]]; then
    local reserve_bytes backfill="false"
    reserve_bytes=$((STORAGE_MIN_FREE_GIB * 1024 * 1024 * 1024))
    if [[ "$STORAGE_PROFILE" == "indexed" ]] && find data/contiguous/data data/chunks -type f -print -quit 2>/dev/null | grep -q .; then
      backfill="true"
      warn "Existing cache data found. Resumable cache-index backfill will run once after startup."
    fi
    if [[ "$STORAGE_PROFILE" == "indexed" ]]; then
      cat >> .env <<EOF

# Native disk-pressure protection (ar-io-node indexed cache evictors)
ENABLE_CONTIGUOUS_DATA_CACHE_INDEX=true
CONTIGUOUS_DATA_CACHE_LOW_WATERMARK_PERCENT=${STORAGE_LOW_WATERMARK}
CONTIGUOUS_DATA_CACHE_HIGH_WATERMARK_PERCENT=${STORAGE_HIGH_WATERMARK}
CONTIGUOUS_DATA_CACHE_MIN_FREE_BYTES=${reserve_bytes}
CONTIGUOUS_DATA_CACHE_INDEX_EVICTION_INTERVAL_MS=60000
ENABLE_CONTIGUOUS_DATA_CACHE_INDEX_BACKFILL=${backfill}
ENABLE_CONTIGUOUS_DATA_CACHE_TEMP_CLEANUP=true

ENABLE_CHUNK_DATA_CACHE_INDEX=true
CHUNK_DATA_CACHE_LOW_WATERMARK_PERCENT=${STORAGE_LOW_WATERMARK}
CHUNK_DATA_CACHE_HIGH_WATERMARK_PERCENT=${STORAGE_HIGH_WATERMARK}
CHUNK_DATA_CACHE_MIN_FREE_BYTES=${reserve_bytes}
CHUNK_DATA_CACHE_INDEX_EVICTION_INTERVAL_MS=60000
ENABLE_CHUNK_DATA_CACHE_INDEX_BACKFILL=${backfill}
# Keep the official filesystem walker available to reconcile unindexed chunks.
ENABLE_CHUNK_DATA_CACHE_CLEANUP=true
CHUNK_DATA_CACHE_CLEANUP_THRESHOLD=14400
CHUNK_SYMLINK_CLEANUP_INTERVAL=21600
EOF
    else
      cat >> .env <<EOF

# Native disk-pressure protection (filesystem-walk TTL profile)
ENABLE_CONTIGUOUS_DATA_CACHE_INDEX=false
ENABLE_CONTIGUOUS_DATA_CACHE_INDEX_BACKFILL=false
CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD=${STORAGE_TTL_SECONDS}
CONTIGUOUS_DATA_CACHE_LOW_WATERMARK_PERCENT=${STORAGE_LOW_WATERMARK}
CONTIGUOUS_DATA_CACHE_HIGH_WATERMARK_PERCENT=${STORAGE_HIGH_WATERMARK}
CONTIGUOUS_DATA_CACHE_MIN_FREE_BYTES=${reserve_bytes}
ENABLE_CONTIGUOUS_DATA_CACHE_TEMP_CLEANUP=true

ENABLE_CHUNK_DATA_CACHE_INDEX=false
ENABLE_CHUNK_DATA_CACHE_INDEX_BACKFILL=false
ENABLE_CHUNK_DATA_CACHE_CLEANUP=true
CHUNK_DATA_CACHE_CLEANUP_THRESHOLD=${STORAGE_TTL_SECONDS}
CHUNK_DATA_CACHE_LOW_WATERMARK_PERCENT=${STORAGE_LOW_WATERMARK}
CHUNK_DATA_CACHE_HIGH_WATERMARK_PERCENT=${STORAGE_HIGH_WATERMARK}
CHUNK_DATA_CACHE_MIN_FREE_BYTES=${reserve_bytes}
EOF
    fi
  fi

  if [[ "$REPORT_DATA_SINK" == "arweave" ]]; then
    printf "REPORT_DATA_SINK=arweave\n" >> .env
  fi

  if [[ "$X402_ENABLED" == "true" ]]; then
    mkdir -p secrets
    chmod 700 secrets
    if [[ -n "$CDP_SECRET_VALUE" ]]; then
      printf "%s" "$CDP_SECRET_VALUE" > secrets/cdp_secret_key
      chmod 600 secrets/cdp_secret_key
      unset CDP_SECRET_VALUE
    fi

    cat >> .env <<EOF

# x402 mainnet configuration. x402 requires the rate limiter.
ENABLE_RATE_LIMITER=true
RATE_LIMITER_TYPE=${RATE_LIMITER_TYPE}
RATE_LIMITER_IP_TOKENS_PER_BUCKET=${RATE_LIMITER_IP_BUCKET}
RATE_LIMITER_IP_REFILL_PER_SEC=${RATE_LIMITER_IP_REFILL}
RATE_LIMITER_RESOURCE_TOKENS_PER_BUCKET=${RATE_LIMITER_RESOURCE_BUCKET}
RATE_LIMITER_RESOURCE_REFILL_PER_SEC=${RATE_LIMITER_RESOURCE_REFILL}

ENABLE_X_402_USDC_DATA_EGRESS=true
X_402_USDC_NETWORK=${X402_NETWORK}
X_402_USDC_WALLET_ADDRESS=${X402_WALLET_ADDRESS}
X_402_USDC_FACILITATOR_URL=${X402_FACILITATOR_URL}
X_402_USDC_PER_BYTE_PRICE=${X402_PER_BYTE_PRICE}
X_402_USDC_DATA_EGRESS_MIN_PRICE=${X402_MIN_PRICE}
X_402_USDC_DATA_EGRESS_MAX_PRICE=${X402_MAX_PRICE}
X_402_RATE_LIMIT_CAPACITY_MULTIPLIER=${X402_CAPACITY_MULTIPLIER}
X_402_APP_NAME=${X402_APP_NAME}
X_402_APP_LOGO=${X402_APP_LOGO}
CHUNK_GET_BASE64_SIZE_BYTES=${CHUNK_GET_BASE64_SIZE_BYTES}
EOF

    if [[ "$RATE_LIMITER_TYPE" == "redis" ]]; then
      {
        printf "RATE_LIMITER_REDIS_ENDPOINT=%s\n" "$RATE_LIMITER_REDIS_ENDPOINT"
        printf "EXTRA_REDIS_FLAGS=%s\n" "$EXTRA_REDIS_FLAGS"
      } >> .env
    fi
    [[ -n "$RATE_LIMITER_IP_ALLOWLIST" ]] && printf "RATE_LIMITER_IPS_AND_CIDRS_ALLOWLIST=%s\n" "$RATE_LIMITER_IP_ALLOWLIST" >> .env
    [[ -n "$RATE_LIMITER_ARNS_ALLOWLIST" ]] && printf "RATE_LIMITER_ARNS_ALLOWLIST=%s\n" "$RATE_LIMITER_ARNS_ALLOWLIST" >> .env
    [[ -n "$CDP_API_KEY_ID" ]] && printf "CDP_API_KEY_ID=%s\n" "$CDP_API_KEY_ID" >> .env
    [[ -n "$X402_CDP_CLIENT_KEY" ]] && printf "X_402_CDP_CLIENT_KEY=%s\n" "$X402_CDP_CLIENT_KEY" >> .env
    [[ -f secrets/cdp_secret_key ]] && printf "CDP_API_KEY_SECRET_FILE=/app/secrets/cdp_secret_key\n" >> .env
  else
    cat >> .env <<EOF

ENABLE_RATE_LIMITER=false
ENABLE_X_402_USDC_DATA_EGRESS=false
EOF
  fi

  chmod 600 .env
  cat > docker-compose.ario.yaml <<'YAML'
# Host isolation for shared servers. NGINX is the only public entry point.
services:
  envoy:
    ports: !override
      - "127.0.0.1:3000:3000"
  core:
    ports: !override
      - "127.0.0.1:4000:4000"
  observer:
    ports: !override
      - "127.0.0.1:5050:5050"
  redis:
    ports: !override []
YAML
  chmod 644 docker-compose.ario.yaml
  ok ".env written at ${INSTALL_DIR}/.env"
  ok "Gateway files and Docker services are isolated under ${INSTALL_DIR}."
}

convert_key_material() {
  local target="$1"
  local expected_wallet="$2"
  local converter
  converter="$(mktemp)"

  cat > "$converter" <<'PY'
import hashlib
import hmac
import json
import os
import sys
import unicodedata

ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493

def inv(x):
    return pow(x, P - 2, P)

D = (-121665 * inv(121666)) % P
I = pow(2, (P - 1) // 4, P)

def xrecover(y):
    xx = (y * y - 1) * inv(D * y * y + 1)
    x = pow(xx, (P + 3) // 8, P)
    if (x * x - xx) % P != 0:
        x = (x * I) % P
    if x % 2 != 0:
        x = P - x
    return x

BY = (4 * inv(5)) % P
BX = xrecover(BY)
B = (BX, BY)

def edwards_add(p1, p2):
    x1, y1 = p1
    x2, y2 = p2
    denom_x = inv(1 + D * x1 * x2 * y1 * y2)
    denom_y = inv(1 - D * x1 * x2 * y1 * y2)
    x3 = (x1 * y2 + x2 * y1) * denom_x
    y3 = (y1 * y2 + x1 * x2) * denom_y
    return (x3 % P, y3 % P)

def scalarmult(point, scalar):
    result = (0, 1)
    addend = point
    while scalar:
        if scalar & 1:
            result = edwards_add(result, addend)
        addend = edwards_add(addend, addend)
        scalar >>= 1
    return result

def encode_point(point):
    x, y = point
    value = y | ((x & 1) << 255)
    return value.to_bytes(32, "little")

def public_from_seed(seed):
    digest = hashlib.sha512(seed).digest()
    scalar = int.from_bytes(digest[:32], "little")
    scalar &= (1 << 254) - 8
    scalar |= (1 << 254)
    return encode_point(scalarmult(B, scalar))

def bip39_seed(mnemonic, passphrase=""):
    mnemonic = unicodedata.normalize("NFKD", mnemonic.strip())
    salt = "mnemonic" + unicodedata.normalize("NFKD", passphrase)
    return hashlib.pbkdf2_hmac(
        "sha512",
        mnemonic.encode("utf-8"),
        salt.encode("utf-8"),
        2048,
        dklen=64,
    )

def slip10_master(seed):
    digest = hmac.new(b"ed25519 seed", seed, hashlib.sha512).digest()
    return digest[:32], digest[32:]

def slip10_child(key, chain_code, index):
    hardened = index | 0x80000000
    data = b"\x00" + key + hardened.to_bytes(4, "big")
    digest = hmac.new(chain_code, data, hashlib.sha512).digest()
    return digest[:32], digest[32:]

def derive_path(seed, path):
    if not path.startswith("m/"):
        raise ValueError("path must start with m/")
    key, chain = slip10_master(seed)
    for part in path[2:].split("/"):
        if not part:
            continue
        if not part.endswith("'"):
            raise ValueError("only hardened ed25519 derivation path components are supported")
        index = int(part[:-1])
        key, chain = slip10_child(key, chain, index)
    return key

def b58decode(text):
    value = 0
    for char in text:
        value *= 58
        index = ALPHABET.find(char)
        if index == -1:
            raise ValueError("invalid base58 character")
        value += index
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big") if value else b""
    pad = 0
    for char in text:
        if char == "1":
            pad += 1
        else:
            break
    return b"\0" * pad + raw

def b58encode(raw):
    value = int.from_bytes(raw, "big")
    output = ""
    while value:
        value, rem = divmod(value, 58)
        output = ALPHABET[rem] + output
    pad = 0
    for byte in raw:
        if byte == 0:
            pad += 1
        else:
            break
    return "1" * pad + (output or "")

def parse_material(text):
    stripped = text.strip()
    if not stripped:
        raise ValueError("empty key material")
    if stripped.startswith("["):
        arr = json.loads(stripped)
        if not isinstance(arr, list) or not all(isinstance(x, int) for x in arr):
            raise ValueError("JSON keypair must be an array of numbers")
        raw = bytes(arr)
    elif len(stripped.split()) in (12, 15, 18, 21, 24):
        seed = bip39_seed(" ".join(stripped.split()))
        expected = os.environ.get("EXPECTED_WALLET", "")
        candidates = []
        for index in range(20):
            candidates.append((f"m/44'/501'/{index}'/0'", derive_path(seed, f"m/44'/501'/{index}'/0'")))
            candidates.append((f"m/44'/501'/{index}'", derive_path(seed, f"m/44'/501'/{index}'")))
            candidates.append((f"m/501'/{index}'/0'/0'", derive_path(seed, f"m/501'/{index}'/0'/0'")))
        if expected:
            for path, child_seed in candidates:
                secret = child_seed + public_from_seed(child_seed)
                if b58encode(secret[32:]) == expected:
                    print(f"matched mnemonic derivation path: {path}", file=sys.stderr)
                    return secret
            raise ValueError(
                "mnemonic did not derive the expected wallet address in the common Phantom paths. "
                "Export the private key for the exact Phantom account and use that instead."
            )
        child_seed = candidates[0][1]
        return child_seed + public_from_seed(child_seed)
    else:
        raw = b58decode("".join(stripped.split()))

    if len(raw) == 64:
        seed = raw[:32]
        pub = raw[32:]
        derived = public_from_seed(seed)
        if pub != derived:
            raise ValueError("64-byte secret key public half does not match derived public key")
        return raw
    if len(raw) == 32:
        return raw + public_from_seed(raw)
    raise ValueError(f"expected 32 or 64 bytes, got {len(raw)} bytes")

def main():
    target = sys.argv[1]
    expected_wallet = sys.argv[2]
    if expected_wallet:
        os.environ["EXPECTED_WALLET"] = expected_wallet
    material = sys.stdin.read()
    secret = parse_material(material)
    address = b58encode(secret[32:])
    if expected_wallet and address != expected_wallet:
        raise SystemExit(
            f"key belongs to {address}, but OBSERVER_WALLET is {expected_wallet}"
        )
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(list(secret), handle)
        handle.write("\n")
    os.chmod(target, 0o600)
    print(f"saved Solana keypair JSON for {address}")

if __name__ == "__main__":
    main()
PY

  set +e
  python3 "$converter" "$target" "$expected_wallet"
  local status=$?
  set -e
  rm -f "$converter"
  return "$status"
}

try_convert_key_material() {
  local target="$1"
  local expected_wallet="$2"
  set +e
  convert_key_material "$target" "$expected_wallet"
  local status=$?
  set -e
  return "$status"
}

configure_wallet() {
  local role_label="$1"
  local wallet_address="$2"
  log "[6/8] ${role_label} Solana keyfile"
  cd "$INSTALL_DIR"
  mkdir -p wallets
  chmod 700 wallets
  local target="wallets/${wallet_address}.json"

  if [[ -f "$target" ]]; then
    chmod 600 "$target"
    ok "Existing keyfile found: ${INSTALL_DIR}/${target}"
    return
  fi

  echo "Beklenen public adres: ${wallet_address}"
  echo "Anahtar dogrulanip su dosyaya guvenli izinlerle kaydedilecek:"
  echo "  ${INSTALL_DIR}/${target}"
  echo

  while true; do
    cat <<'KEY_OPTIONS'
Anahtari nasil vereceksiniz?
  1) Sunucudaki keypair JSON dosyasinin yolu (onerilen)
  2) JSON array, seed phrase veya base58 private key yapistir
  3) Simdilik atla
KEY_OPTIONS
    local key_choice key_material
    key_choice="$(prompt "Seciminiz" "1")"
    case "$key_choice" in
      1)
        echo "Ornek dosya yolu: /root/id.json"
        key_material="$(prompt "Keypair JSON dosya yolu" "")"
        if [[ -f "$key_material" ]] && try_convert_key_material "${INSTALL_DIR}/${target}" "$wallet_address" < "$key_material"; then
          ok "Keyfile kuruldu: ${INSTALL_DIR}/${target}"
          return
        fi
        warn "Dosya bulunamadi, gecersiz veya public adres ${wallet_address} ile eslesmiyor."
        ;;
      2)
        echo "Gizli degeri tek satir olarak yapistirip Enter'a basin; ekranda gorunmez."
        printf "Key material: " >&2
        read -r -s key_material < /dev/tty
        printf "\n" >&2
        if printf "%s" "$key_material" | try_convert_key_material "${INSTALL_DIR}/${target}" "$wallet_address"; then
          unset key_material
          ok "Keyfile kuruldu: ${INSTALL_DIR}/${target}"
          return
        fi
        unset key_material
        warn "Anahtar gecersiz veya public adres ${wallet_address} ile eslesmiyor."
        ;;
      3)
        warn "Keyfile atlandi. Gateway veri sunabilir fakat ${role_label} protokol islemleri calismaz."
        echo "Daha sonra eklenmesi gereken yer: ${INSTALL_DIR}/${target}"
        return
        ;;
      *) warn "1, 2 veya 3 secin." ;;
    esac

    confirm "Anahtar adimini tekrar denemek ister misiniz" "y" && continue
    warn "Keyfile atlandi. Daha sonra ${INSTALL_DIR}/${target} konumuna ekleyin."
    return
  done
}

start_gateway() {
  log "[7/8] Starting gateway"
  cd "$INSTALL_DIR"
  docker compose config --quiet || die "Docker Compose 2.24.4 or newer is required for safe port isolation. Update Docker Compose and run the installer again."
  docker compose pull
  docker compose up -d
}

configure_firewall_ssl_nginx() {
  log "[8/8] Firewall, SSL, nginx"
  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow OpenSSH >/dev/null || true
    ufw allow 80/tcp >/dev/null || true
    ufw allow 443/tcp >/dev/null || true
    ok "Existing UFW firewall updated for SSH, HTTP and HTTPS."
  else
    warn "UFW is inactive; the installer left it unchanged. Configure your provider firewall for TCP 22, 80 and 443."
  fi

  if [[ "$CERT_MODE" == "namecheap" ]]; then
    local domain_slug="${DOMAIN//./-}"
    local credentials="/etc/letsencrypt/ar-io-${domain_slug}-namecheap.ini"
    local force_args=()
    local renewal_auth=""
    umask 077
    printf "dns_namecheap_username = %s\ndns_namecheap_api_key = %s\n" "$NAMECHEAP_USERNAME" "$NAMECHEAP_API_KEY" > "$credentials"
    chmod 600 "$credentials"
    unset NAMECHEAP_API_KEY
    if [[ -f "/etc/letsencrypt/renewal/${DOMAIN}.conf" ]]; then
      renewal_auth="$(sed -n 's/^authenticator = //p' "/etc/letsencrypt/renewal/${DOMAIN}.conf" | tail -n1)"
    fi
    if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" && "$renewal_auth" == "dns-namecheap" ]]; then
      ok "Existing Namecheap-renewable certificate found for ${DOMAIN}."
    else
      [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]] && force_args=(--force-renewal)
      certbot certonly \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --dns-namecheap \
        --dns-namecheap-credentials "$credentials" \
        --cert-name "$DOMAIN" \
        "${force_args[@]}" \
        -d "$DOMAIN" \
        -d "*.${DOMAIN}"
    fi
    ok "Namecheap DNS wildcard certificate configured."
  elif [[ "$CERT_MODE" == "cloudflare" ]]; then
    local domain_slug="${DOMAIN//./-}"
    local credentials="/etc/letsencrypt/ar-io-${domain_slug}-cloudflare.ini"
    local force_args=()
    local renewal_auth=""
    umask 077
    printf "dns_cloudflare_api_token = %s\n" "$CLOUDFLARE_API_TOKEN" > "$credentials"
    chmod 600 "$credentials"
    unset CLOUDFLARE_API_TOKEN
    if [[ -f "/etc/letsencrypt/renewal/${DOMAIN}.conf" ]]; then
      renewal_auth="$(sed -n 's/^authenticator = //p' "/etc/letsencrypt/renewal/${DOMAIN}.conf" | tail -n1)"
    fi
    if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" && "$renewal_auth" == "dns-cloudflare" ]]; then
      ok "Existing Cloudflare-renewable certificate found for ${DOMAIN}."
    else
      [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]] && force_args=(--force-renewal)
      certbot certonly \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$credentials" \
        --dns-cloudflare-propagation-seconds 30 \
        --cert-name "$DOMAIN" \
        "${force_args[@]}" \
        -d "$DOMAIN" \
        -d "*.${DOMAIN}"
    fi
    ok "Cloudflare DNS wildcard certificate configured."
  elif [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    ok "Existing Let's Encrypt certificate found for ${DOMAIN}."
  else
    echo
    echo "Certbot will ask you to create a DNS TXT record for:"
    echo "  _acme-challenge.${DOMAIN}"
    echo "Wait for DNS propagation before continuing."
    echo
    certbot certonly \
      --manual \
      --preferred-challenges dns \
      --agree-tos \
      --register-unsafely-without-email \
      --cert-name "$DOMAIN" \
      -d "${DOMAIN}" \
      -d "*.${DOMAIN}"
  fi

  install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
  local nginx_slug="${DOMAIN//./-}"
  local nginx_site="/etc/nginx/sites-available/ar-io-${nginx_slug}.conf"
  local nginx_link="/etc/nginx/sites-enabled/ar-io-${nginx_slug}.conf"
  local deploy_hook="/etc/letsencrypt/renewal-hooks/deploy/ar-io-${nginx_slug}-reload-nginx"
  local nginx_backup=""
  cat > "$deploy_hook" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
nginx -t
systemctl reload nginx
HOOK
  chmod 755 "$deploy_hook"
  local active_auth=""
  if [[ -f "/etc/letsencrypt/renewal/${DOMAIN}.conf" ]]; then
    active_auth="$(sed -n 's/^authenticator = //p' "/etc/letsencrypt/renewal/${DOMAIN}.conf" | tail -n1)"
  fi
  if [[ "$active_auth" != "manual" && -n "$active_auth" ]]; then
    systemctl enable --now certbot.timer >/dev/null 2>&1 || true
  else
    warn "Manual DNS certificates require a new TXT record at renewal. Run gateway-cert-setup to enable unattended renewal."
  fi

  if [[ -e "$nginx_site" ]]; then
    nginx_backup="${nginx_site}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$nginx_site" "$nginx_backup"
  fi
  cat > "$nginx_site" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} *.${DOMAIN};

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN} *.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    client_max_body_size 250m;
    proxy_connect_timeout 75s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_http_version 1.1;
        proxy_set_header X-AR-IO-Origin \$http_x_ar_io_origin;
        proxy_set_header X-AR-IO-Origin-Node-Release \$http_x_ar_io_origin_node_release;
        proxy_set_header X-AR-IO-Hops \$http_x_ar_io_hops;
    }
}
EOF
  ln -sfn "$nginx_site" "$nginx_link"

  if ! nginx -t; then
    rm -f "$nginx_link"
    if [[ -n "$nginx_backup" ]]; then
      cp -a "$nginx_backup" "$nginx_site"
      ln -sfn "$nginx_site" "$nginx_link"
    else
      rm -f "$nginx_site"
    fi
    die "NGINX configuration validation failed; the previous site configuration was restored."
  fi
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
  else
    systemctl enable --now nginx
  fi
  if [[ "$active_auth" != "manual" && -n "$active_auth" ]]; then
    log "Validating unattended certificate renewal"
    certbot renew --dry-run --cert-name "$DOMAIN"
  fi
  ok "nginx configured for https://${DOMAIN}"
}

install_manager() {
  log "Installing gateway operator manager"
  local manager_dir="/usr/local/lib/ar-io-gateway"
  local manager_path="${manager_dir}/manager.sh"
  local temp
  temp="$(mktemp)"
  curl -fsSL "$MANAGER_URL" -o "$temp"
  bash -n "$temp"
  install -d -m 755 "$manager_dir"
  install -m 755 "$temp" "$manager_path"
  rm -f "$temp"
  INSTALL_DIR="$INSTALL_DIR" "$manager_path" install-links "$INSTALL_DIR"
}

finish() {
  echo
  echo -e "${GREEN}Kurulum tamamlandi.${NC}"
  echo "Gateway: https://${DOMAIN}"
  echo
  echo "Simdi sirayla calistirin:"
  echo "  gateway-doctor"
  echo "  gateway-check"
  echo "  gateway-observer-check"
  echo "  gateway-cert-check"
  echo "  gateway-balance"
  echo
  echo "Tum komutlar: gateway-help"
  echo "Interaktif yonetim: gateway"
  echo
  echo "Bu kurulum gateway'i AR.IO Network'e kaydetmedi ve stake islemi yapmadi."
  echo
  /usr/local/bin/gateway-check || true
}

main() {
  require_root
  header
  guard_new_install
  collect_config
  preflight
  install_packages
  install_docker
  clone_node
  write_env
  configure_wallet "main/operator" "$AR_IO_WALLET"
  if [[ "$OBSERVER_WALLET" == "$AR_IO_WALLET" ]]; then
    ok "Observer wallet matches main/operator wallet; reusing the same keyfile."
  else
    configure_wallet "observer" "$OBSERVER_WALLET"
  fi
  start_gateway
  configure_firewall_ssl_nginx
  install_manager
  finish
}

main "$@"
