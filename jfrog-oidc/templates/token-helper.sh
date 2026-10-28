#!/usr/bin/env bash
MODULE=jfrog-oidc
# shellcheck source=../../lib/runtime.sh
source "$(dirname "$0")/../runtime.sh"

AUDIENCE='{{AUDIENCE}}'
CACHE_FILE='{{CACHE_FILE}}'
require jq
now="$(date +%s)"

if [[ -s "$CACHE_FILE" ]] && token="$(jq -er --argjson now "$now" '
  select(.issued_at <= $now and .expires_at > ($now + 60))
  | .access_token | select(type == "string" and length > 0)
' "$CACHE_FILE" 2>/dev/null)"; then
  printf '%s' "$token"
  exit 0
fi

jwt="$(mint_token)"
response="$(printf '%s' "$jwt" | jq -Rs \
  --arg provider '{{PROVIDER_NAME}}' --arg project '{{PROJECT_KEY}}' '
  {
    grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
    subject_token_type: "urn:ietf:params:oauth:token-type:id_token",
    subject_token: .,
    provider_name: $provider
  } + (if $project == "" then {} else {project_key: $project} end)
' | post_json '{{PLATFORM_URL}}/access/api/v1/oidc/token')"
cache="$(jq -ce --argjson now "$now" '
  select(
    (.access_token | type == "string" and test("^[A-Za-z0-9._~+/-]+=*$"))
    and (.token_type | ascii_downcase == "bearer")
    and (.expires_in | type == "number" and . > 0 and . == floor)
  )
  | {access_token, issued_at: $now, expires_at: ($now + .expires_in)}
' <<<"$response" 2>/dev/null)" || die "JFrog response contains no valid Bearer token or expiry"
printf '%s\n' "$cache" | write_private "$CACHE_FILE"
jq -r '.access_token' <<<"$cache"
