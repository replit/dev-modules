#!/usr/bin/env bash
# Install the Azure wrapper and SDK identity settings.
set -euo pipefail
OIDC_MODULE_NAME=azure-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args client-id tenant-id subscription-id audience -- "$@"
oidc_require OPT_client_id client-id
oidc_require OPT_tenant_id tenant-id
: "${OPT_subscription_id:=}" "${OPT_audience:=api://AzureADTokenExchange}"

source "${MODULE_DIR}/../lib/dependencies.sh"
oidc_dependencies az 2.91.0 stat

AUDIENCE="$OPT_audience"
CLIENT_ID="$OPT_client_id"
TENANT_ID="$OPT_tenant_id"
SUBSCRIPTION_ID="$OPT_subscription_id"
STATE_DIR="$OIDC_STATE_DIR"
BIN_DIR="$OIDC_BIN_DIR"
TOKEN_FILE="${OIDC_STATE_DIR}/azure-federated-token"
oidc_install_helper az "${MODULE_DIR}/templates/az-wrapper.sh" \
  BIN_DIR AUDIENCE TOKEN_FILE CLIENT_ID TENANT_ID SUBSCRIPTION_ID STATE_DIR >/dev/null


oidc_env_prepend_path "$BIN_DIR"
oidc_env_set AZURE_CLIENT_ID "$CLIENT_ID"
oidc_env_set AZURE_TENANT_ID "$TENANT_ID"
oidc_env_set AZURE_FEDERATED_TOKEN_FILE "$TOKEN_FILE"
if [[ -n "$SUBSCRIPTION_ID" ]]; then oidc_env_set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION_ID"; fi

if ! command -v az >/dev/null 2>&1; then
  oidc_log "note: az CLI not installed; the wrapper needs it at call time"
fi
oidc_log "configured workload identity for client ${CLIENT_ID}; az wrapper at ${BIN_DIR}/az"
