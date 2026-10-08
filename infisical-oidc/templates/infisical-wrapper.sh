#!/usr/bin/env bash
# Exchange Replit identity for a cached Infisical machine-identity token.
MODULE=infisical-oidc
source "$(dirname "$0")/../runtime.sh"

AUDIENCE='{{AUDIENCE}}'
CACHE_FILE='{{ACCESS_TOKEN_FILE}}'
real_infisical="$(find_cli infisical)"

case "${1:-}" in
  login|logout)
    rm -f "$CACHE_FILE"
    exec "$real_infisical" "$@"
    ;;
esac

if ! cache_fresh "$CACHE_FILE" '{{LOGIN_TTL}}'; then
  require jq
  jwt="$(mint_token)"
  response="$(jq -n --arg identityId '{{IDENTITY_ID}}' --arg jwt "$jwt" \
    '{identityId: $identityId, jwt: $jwt}' \
    | post_json '{{API_URL}}/v1/auth/jwt-auth/login')"
  token="$(jq -er '.accessToken | select(type == "string" and length > 0)' <<<"$response")" \
    || die "Infisical response contains no valid access token"
  printf '%s' "$token" | write_private "$CACHE_FILE"
fi

INFISICAL_TOKEN="$(cat "$CACHE_FILE")"
export INFISICAL_TOKEN
exec "$real_infisical" "$@"
