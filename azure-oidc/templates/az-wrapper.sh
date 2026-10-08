#!/usr/bin/env bash
# Refresh the federated token for Azure SDKs and authenticate the Azure CLI.
MODULE=azure-oidc
source "$(dirname "$0")/../runtime.sh"

AUDIENCE='{{AUDIENCE}}'
TOKEN_FILE='{{TOKEN_FILE}}'
LOGIN_STAMP='{{STATE_DIR}}/azure-login.stamp'
real_az="$(find_cli az)"

# Explicit session commands bypass federation and invalidate our login cache.
case "${1:-}" in
  login|logout)
    rm -f "$LOGIN_STAMP"
    exec "$real_az" "$@"
    ;;
esac

token="$(mint_token)"
printf '%s' "$token" | write_private "$TOKEN_FILE"

if ! cache_fresh "$LOGIN_STAMP" 3000; then
  "$real_az" login --service-principal \
    --username '{{CLIENT_ID}}' --tenant '{{TENANT_ID}}' \
    --federated-token "$token" --allow-no-subscriptions --output none \
    || die "Azure login failed"
  if [[ -n '{{SUBSCRIPTION_ID}}' ]]; then
    "$real_az" account set --subscription '{{SUBSCRIPTION_ID}}' --output none \
      || die "Azure subscription selection failed"
  fi
  printf 'authenticated\n' | write_private "$LOGIN_STAMP"
fi

exec "$real_az" "$@"
