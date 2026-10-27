#!/usr/bin/env bash
MODULE=jfrog-oidc
# shellcheck source=../../lib/runtime.sh
source "$(dirname "$0")/../runtime.sh"

real_npm="$(find_cli npm)"
TOKEN_HELPER='{{TOKEN_HELPER}}'
case "${1:-}" in
  --version|-v|--help|-h|help) exec "$real_npm" "$@" ;;
esac
REPLIT_JFROG_TOKEN="$("$TOKEN_HELPER")"
export REPLIT_JFROG_TOKEN
exec "$real_npm" "$@"
