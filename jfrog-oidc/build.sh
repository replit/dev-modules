#!/usr/bin/env bash
set -euo pipefail
OIDC_MODULE_NAME=jfrog-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args platform-url provider-name audience project-key -- "$@"
oidc_require OPT_platform_url platform-url
oidc_require OPT_provider_name provider-name
oidc_require OPT_audience audience
: "${OPT_project_key:=}"

origin='https://[a-zA-Z0-9.-]+(:[0-9]+)?'
[[ "$OPT_platform_url" =~ ^${origin}/?$ ]] \
  || oidc_die "--platform-url must be an HTTPS origin without credentials, query, or fragment"

source "${MODULE_DIR}/../lib/dependencies.sh"
oidc_dependencies jf 2.128.0 jq curl

AUDIENCE="$OPT_audience"
PLATFORM_URL="${OPT_platform_url%/}"
PROVIDER_NAME="$OPT_provider_name"
PROJECT_KEY="$OPT_project_key"
STATE_DIR="${OIDC_STATE_DIR}/jfrog"
CACHE_FILE="${STATE_DIR}/access-token.json"
CLI_HOME="${STATE_DIR}/cli"
mkdir -p "$STATE_DIR" "$CLI_HOME"
chmod 0700 "$STATE_DIR" "$CLI_HOME"
# Reconfiguration must not reuse credentials for a previous provider or audience.
rm -f "$CACHE_FILE"
TOKEN_HELPER="$(oidc_install_helper jfrog-token "${MODULE_DIR}/templates/token-helper.sh" \
  AUDIENCE PLATFORM_URL PROVIDER_NAME PROJECT_KEY CACHE_FILE)"
oidc_install_helper jf "${MODULE_DIR}/templates/jf-wrapper.sh" \
  TOKEN_HELPER PLATFORM_URL CLI_HOME >/dev/null

oidc_env_prepend_path "$OIDC_BIN_DIR"
oidc_log "configured JFrog provider '${PROVIDER_NAME}'; jf wrapper at ${OIDC_BIN_DIR}/jf"
