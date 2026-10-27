#!/usr/bin/env bash
set -euo pipefail
OIDC_MODULE_NAME=jfrog-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args platform-url provider-name audience registry scope project-key -- "$@"
oidc_require OPT_platform_url platform-url
oidc_require OPT_provider_name provider-name
oidc_require OPT_audience audience
oidc_require OPT_registry registry
: "${OPT_scope:=}" "${OPT_project_key:=}"
[[ -z "${OPT_cli_release:-}" ]] || oidc_die "--cli-release is not supported; use your environment's npm installation"

origin='https://[a-zA-Z0-9.-]+(:[0-9]+)?'
[[ "$OPT_platform_url" =~ ^${origin}/?$ ]] \
  || oidc_die "--platform-url must be an HTTPS origin without credentials, query, or fragment"
[[ "$OPT_registry" =~ ^${origin}/[a-zA-Z0-9._~/%+-]+(/[a-zA-Z0-9._~/%+-]+)*/?$ ]] \
  || oidc_die "--registry must be an HTTPS repository URL without credentials, query, or fragment"
[[ -z "$OPT_scope" || "$OPT_scope" =~ ^@[a-z0-9][a-z0-9._-]*$ ]] \
  || oidc_die "--scope must be an npm scope such as @myorg"
case "${OPT_disable_deps_install:-false}" in
  true) oidc_log "dependency installation disabled; required tools: replit jq curl npm" ;;
  false)
    source "${MODULE_DIR}/../lib/dependencies.sh"
    command -v replit >/dev/null || oidc_die "run this module where the Replit identity CLI is available"
    oidc_commands jq curl
    ;;
  *) oidc_die "--disable-deps-install accepts only true or false" ;;
esac

AUDIENCE="$OPT_audience"
PLATFORM_URL="${OPT_platform_url%/}"
PROVIDER_NAME="$OPT_provider_name"
PROJECT_KEY="$OPT_project_key"
STATE_DIR="${OIDC_STATE_DIR}/jfrog"
CACHE_FILE="${STATE_DIR}/access-token.json"
mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"
# Reconfiguration must not reuse credentials for a previous provider or audience.
rm -f "$CACHE_FILE"
TOKEN_HELPER="$(oidc_install_helper jfrog-token "${MODULE_DIR}/templates/token-helper.sh" \
  AUDIENCE PLATFORM_URL PROVIDER_NAME PROJECT_KEY CACHE_FILE)"
oidc_install_helper npm "${MODULE_DIR}/templates/npm-wrapper.sh" TOKEN_HELPER >/dev/null

REGISTRY="${OPT_registry%/}/"
AUTH_KEY="//${REGISTRY#https://}:_authToken"
{
  printf '%sregistry=%s\n' "${OPT_scope:+${OPT_scope}:}" "$REGISTRY"
  printf "%s=\${REPLIT_JFROG_TOKEN}\n" "$AUTH_KEY"
} | oidc_replace_block "${NPM_CONFIG_USERCONFIG:-${HOME}/.npmrc}" \
  '# BEGIN replit jfrog-oidc' '# END replit jfrog-oidc'

oidc_env_prepend_path "$OIDC_BIN_DIR"
oidc_log "configured JFrog provider '${PROVIDER_NAME}' and npm registry ${REGISTRY}; activate ${OIDC_ENV_FILE} before using npm"
