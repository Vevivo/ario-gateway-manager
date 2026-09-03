#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for script in install-gateway.sh gateway-manager.sh update-tools.sh; do
  bash -n "$script"
done

help_output="$(./gateway-manager.sh help)"
for command in \
  gateway-doctor gateway-storage-setup gateway-cert-setup gateway-enable-x402 \
  gateway-network-info gateway-network-readiness gateway-verification gateway-cdb64-check gateway-cache-advisor gateway-release-check \
  gateway-guides; do
  grep -q "$command" <<< "$help_output" || fail "$command is missing from gateway-help"
done

if rg -n 'docker system prune|docker compose down -v|rm -rf .*(data/(sqlite|redis|contiguous|chunks)|ar-io-node/data)' \
  install-gateway.sh gateway-manager.sh update-tools.sh; then
  fail "destructive gateway cleanup command found"
fi

if rg -n '(^|[;&|[:space:]])(source|\.)[[:space:]]+[^[:space:]]*\.env' --glob '*.sh' .; then
  fail ".env must not be executed as shell code"
fi

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
printf 'ARNS_ROOT_HOST=example.com\nDUPLICATE=old\nDUPLICATE=older\nREMOVE_ME=yes\n' > "$test_root/.env"
touch "$test_root/docker-compose.yaml"

GATEWAY_MANAGER_LIB_ONLY=true
INSTALL_DIR="$test_root"
source ./gateway-manager.sh
set_env DUPLICATE new
[[ "$(grep -c '^DUPLICATE=' "$test_root/.env")" == "1" ]] || fail "set_env did not de-duplicate the key"
[[ "$(get_env DUPLICATE)" == "new" ]] || fail "set_env did not update the value"
remove_env REMOVE_ME
! grep -q '^REMOVE_ME=' "$test_root/.env" || fail "remove_env did not remove the key"
[[ "$(stat -c '%a' "$test_root/.env")" == "600" ]] || fail ".env mode is not 600"

storage_values_valid 85 90 || fail "recommended watermarks rejected"
! storage_values_valid 90 85 || fail "invalid watermarks accepted"
grep -q 'STORAGE_PROFILE="${STORAGE_PROFILE:-indexed}"' install-gateway.sh || fail "indexed storage profile is not the installer default"
grep -q 'CERT_MODE="${CERT_MODE:-namecheap}"' install-gateway.sh || fail "Namecheap is not the installer certificate default"
grep -q 'Whitelisted IPs' install-gateway.sh || fail "Namecheap IPv4 whitelist guidance is missing"
grep -q 'INSTALL_MODE="easy"' install-gateway.sh || fail "easy install mode is not the default"
grep -q 'Kolay kurulum (onerilen)' install-gateway.sh || fail "beginner install guidance is missing"
grep -q 'read -r value < /dev/tty' install-gateway.sh || fail "piped installer does not read answers from the terminal"
grep -q 'curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/install-gateway.sh | sudo bash' README.md || fail "one-command install is not prominent"
grep -q 'INSTALL_DIR="${INSTALL_DIR:-/opt/ar-io-gateway}"' install-gateway.sh || fail "shared-server install directory is not the default"
grep -q '^COMPOSE_PROJECT_NAME=' install-gateway.sh || fail "Docker Compose project isolation is missing"
grep -q '^COMPOSE_FILE=docker-compose.yaml:docker-compose.ario.yaml' install-gateway.sh || fail "gateway Compose override is not enabled"
grep -q '127.0.0.1:3000:3000' install-gateway.sh || fail "Envoy is not bound to localhost"
grep -q '127.0.0.1:4000:4000' install-gateway.sh || fail "core is not bound to localhost"
grep -q '127.0.0.1:5050:5050' install-gateway.sh || fail "observer is not bound to localhost"
grep -q 'ports: !override \[\]' install-gateway.sh || fail "Redis host port is still published"
grep -q 'sites-available/ar-io-' install-gateway.sh || fail "domain-specific NGINX site is missing"
! grep -q 'cat > /etc/nginx/sites-available/default' install-gateway.sh || fail "installer overwrites the default NGINX site"
! grep -q 'systemctl restart nginx' install-gateway.sh || fail "installer restarts the shared NGINX service"
! grep -q 'ufw --force enable' install-gateway.sh || fail "installer force-enables UFW"
! grep -q 'apt-get upgrade' install-gateway.sh || fail "installer upgrades unrelated system packages"
grep -q 'Install Docker Compose 2.24.4 or newer' install-gateway.sh || fail "shared Docker engine protection is missing"
grep -q 'ALLOW_EXISTING_INSTALL' install-gateway.sh || fail "existing gateway overwrite guard is missing"
grep -q '^ARNS_COMPOSITE_LAST_RESOLVER_TIMEOUT_MS=5000' install-gateway.sh || fail "r83 ArNS fallback timeout is missing"
grep -q '^SKIP_LEAVING_GATEWAYS=true' install-gateway.sh || fail "r83 leaving-peer policy is missing"
grep -q '^FOREGROUND_CACHE_COALESCE_MAX_ATTEMPTS=2' install-gateway.sh || fail "r83 request coalescing baseline is missing"
grep -q 'short_reads_rejected_total' gateway-manager.sh || fail "r83 short-read metric check is missing"
[[ "$(grep -c '^    cdb64-check)' gateway-manager.sh)" == "1" ]] || fail "duplicate cdb64 dispatch entry found"
[[ "$(grep -c 'name=.*ArNS name to unblock' gateway-manager.sh)" == "1" ]] || fail "duplicate unblock prompt found"
[[ -f docs/OPERATIONS.md ]] || fail "advanced operations guide is missing"
grep -q 'ENABLE_CHUNK_DATA_CACHE_CLEANUP true' gateway-manager.sh || fail "chunk drift reconciler is not enabled"
grep -q 'CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD "$ttl"' gateway-manager.sh || fail "TTL storage profile is missing"
grep -q "error.code !== 'ENOENT'" gateway-manager.sh || fail "indexed eviction version guard is missing"
! grep -q '^write_helpers()' install-gateway.sh || fail "legacy helper generator is still present"
is_tx_id 3lyxgbgEvqNSvJrTX2J7CfRychUD5KClFhhVLyTPNCQ || fail "valid transaction ID rejected"
! is_tx_id short || fail "invalid transaction ID accepted"

mkdir -p "$test_root/src/store" "$test_root/data/contiguous/data" "$test_root/data/chunks"
printf '%s\n' \
  'await fs.promises.writeFile(chunkPath, chunkData.chunk);' \
  "if (error.code !== 'ENOENT') {" \
  'throw error;' > "$test_root/src/store/fs-chunk-data-store.ts"
require_root() { :; }
docker() { return 0; }

cmd_storage_setup <<'INDEXED_INPUT' >/dev/null 2>&1
1
90
85
20
y
INDEXED_INPUT
[[ "$(get_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX)" == "true" ]] || fail "indexed contiguous profile was not applied"
[[ "$(get_env ENABLE_CHUNK_DATA_CACHE_INDEX)" == "true" ]] || fail "indexed chunk profile was not applied"
[[ "$(get_env ENABLE_CHUNK_DATA_CACHE_CLEANUP)" == "true" ]] || fail "indexed profile lost the chunk drift reconciler"
[[ -z "$(get_env CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD)" ]] || fail "indexed profile also enabled the contiguous filesystem walker"

set_env CHUNK_INGEST_CACHE_ENABLED true
set_env CHUNK_INGEST_CONFIRMATION_TIMEOUT_SECONDS 21600
set_env CHUNK_INGEST_ALLOWLIST_CONFIRMATION_TIMEOUT_SECONDS 86400
set_env CHUNK_DATA_CACHE_AGGRESSIVE_MIN_AGE_SECONDS 3600
cmd_storage_setup <<'TTL_INPUT' >/dev/null 2>&1
2
90
85
20
14400
y
TTL_INPUT
[[ "$(get_env ENABLE_CONTIGUOUS_DATA_CACHE_INDEX)" == "false" ]] || fail "TTL profile left the contiguous index enabled"
[[ "$(get_env ENABLE_CHUNK_DATA_CACHE_INDEX)" == "false" ]] || fail "TTL profile left the chunk index enabled"
[[ "$(get_env CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD)" == "14400" ]] || fail "TTL contiguous cleanup was not applied"
[[ "$(get_env CHUNK_DATA_CACHE_AGGRESSIVE_MIN_AGE_SECONDS)" == "86400" ]] || fail "chunk ingest cleanup floor was not protected"

curl() {
  if [[ "$*" == *'/ar-io/info'* ]]; then
    printf '{"release":83}\n'
  elif [[ "$*" == *'/releases/latest'* ]]; then
    printf '{"tag_name":"r83"}\n'
  elif [[ "$*" == *'/ar-io/__gateway_metrics'* ]]; then
    printf '%s\n' \
      '# HELP short_reads_rejected_total test' \
      '# HELP ar_io_peers_skipped_leaving_total test' \
      '# HELP foreground_cache_skipped_total test' \
      '# HELP foreground_cache_coalesced_outcome_total test' \
      '# HELP foreground_cache_re_elections_total test'
  fi
}
release_output="$(cmd_release_check)"
grep -q 'running release: 83' <<< "$release_output" || fail "release checker did not read the local release"
grep -q 'latest GitHub release: r83' <<< "$release_output" || fail "release checker did not read the latest release"
grep -q 'Metric available: short_reads_rejected_total' <<< "$release_output" || fail "release checker did not inspect r83 metrics"

echo "All smoke tests passed."
