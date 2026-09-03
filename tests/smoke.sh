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
  gateway-network-info gateway-network-readiness gateway-verification gateway-cdb64-check gateway-cache-advisor \
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
grep -q 'ENABLE_CHUNK_DATA_CACHE_CLEANUP true' gateway-manager.sh || fail "chunk drift reconciler is not enabled"
grep -q 'CONTIGUOUS_DATA_CACHE_CLEANUP_THRESHOLD "$ttl"' gateway-manager.sh || fail "TTL storage profile is missing"
grep -q "error.code !== 'ENOENT'" gateway-manager.sh || fail "indexed eviction version guard is missing"
! grep -q '^  write_helpers$' install-gateway.sh || fail "legacy helper generator must not run before the manager"
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

echo "All smoke tests passed."
