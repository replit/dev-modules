#!/usr/bin/env bash
MODULE=jfrog-oidc
# shellcheck source=../../lib/runtime.sh
source "$(dirname "$0")/../runtime.sh"

real_jf="$(find_cli jf)"
case "${1:-}" in
  --version|-v|--help|-h|help) exec "$real_jf" "$@" ;;
esac

export JFROG_CLI_HOME_DIR='{{CLI_HOME}}'
export JFROG_CLI_SERVER_ID=replit-oidc
TOKEN_HELPER='{{TOKEN_HELPER}}'
token="$("$TOKEN_HELPER")"
printf '%s' "$token" | "$real_jf" config add "$JFROG_CLI_SERVER_ID" \
  --url='{{PLATFORM_URL}}' --access-token-stdin \
  --interactive=false --overwrite --disable-token-refresh >/dev/null

exec "$real_jf" "$@"
