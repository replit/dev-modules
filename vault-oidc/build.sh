#!/usr/bin/env bash
# Install Vault's JWT token helper and connection settings.
set -euo pipefail
OIDC_MODULE_NAME=vault-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args address role auth-mount namespace audience cache-ttl -- "$@"
oidc_require OPT_address address
oidc_require OPT_role role
: "${OPT_auth_mount:=jwt}" "${OPT_namespace:=}" "${OPT_cache_ttl:=300}"
oidc_positive_integer cache-ttl "$OPT_cache_ttl"
OPT_address="${OPT_address%/}"
host="${OPT_address#*://}"; host="${host%%/*}"
: "${OPT_audience:=$host}"

source "${MODULE_DIR}/../lib/dependencies.sh"
oidc_dependencies vault 2.1.2 jq curl stat

AUDIENCE="$OPT_audience"
VAULT_ADDR="$OPT_address"
VAULT_NAMESPACE="$OPT_namespace"
ROLE="$OPT_role"
AUTH_MOUNT="$OPT_auth_mount"
CACHE_TTL="$OPT_cache_ttl"
HELPER="$(oidc_install_helper vault-token-helper "${MODULE_DIR}/templates/token-helper.sh" \
  VAULT_ADDR VAULT_NAMESPACE ROLE AUTH_MOUNT AUDIENCE CACHE_TTL)"

# ~/.vault must be a plain file for token_helper to be honoured.
if [[ -d "${HOME}/.vault" ]]; then
  oidc_die "${HOME}/.vault is a directory; the vault CLI expects a config file there"
fi
printf 'token_helper = "%s"\n' "$HELPER" | oidc_write_file "${HOME}/.vault" 0600

oidc_env_set VAULT_ADDR "$VAULT_ADDR"
if [[ -n "$VAULT_NAMESPACE" ]]; then oidc_env_set VAULT_NAMESPACE "$VAULT_NAMESPACE"; fi

if ! command -v vault >/dev/null 2>&1; then
  oidc_log "note: vault CLI not installed; the token helper only matters once it is"
fi
oidc_log "configured Vault JWT login for role '${ROLE}' at ${VAULT_ADDR} via ${HELPER}"
