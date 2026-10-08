#!/usr/bin/env bash
# Install the Infisical wrapper and project settings.
set -euo pipefail
OIDC_MODULE_NAME=infisical-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args identity-id project-id environment domain audience login-ttl -- "$@"
oidc_require OPT_identity_id identity-id
oidc_require OPT_project_id project-id
: "${OPT_environment:=dev}" "${OPT_domain:=https://app.infisical.com}" "${OPT_audience:=infisical}"
: "${OPT_login_ttl:=3000}"
oidc_positive_integer login-ttl "$OPT_login_ttl"

source "${MODULE_DIR}/../lib/dependencies.sh"
oidc_dependencies infisical 0.43.139 jq curl stat

AUDIENCE="$OPT_audience"
API_URL="${OPT_domain%/}/api"
IDENTITY_ID="$OPT_identity_id"
LOGIN_TTL="$OPT_login_ttl"
ACCESS_TOKEN_FILE="${OIDC_STATE_DIR}/infisical-access-token"
BIN_DIR="$OIDC_BIN_DIR"
oidc_install_helper infisical "${MODULE_DIR}/templates/infisical-wrapper.sh" \
  BIN_DIR AUDIENCE API_URL IDENTITY_ID ACCESS_TOKEN_FILE LOGIN_TTL >/dev/null


oidc_env_prepend_path "$BIN_DIR"
oidc_env_set INFISICAL_API_URL "$API_URL"
oidc_env_set INFISICAL_PROJECT_ID "$OPT_project_id"
oidc_env_set INFISICAL_ENVIRONMENT "$OPT_environment"

if ! command -v infisical >/dev/null 2>&1; then
  oidc_log "note: infisical CLI not installed; the wrapper needs it at call time"
fi
oidc_log "configured machine identity ${IDENTITY_ID} for project ${OPT_project_id}/${OPT_environment}; infisical wrapper at ${BIN_DIR}/infisical"
