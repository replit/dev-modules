#!/usr/bin/env bash
# Emit executable credentials using Google's AIP-4117 protocol.
MODULE=gcp-oidc
source "$(dirname "$0")/../runtime.sh"

AUDIENCE='{{AUDIENCE}}'
require jq base64
token="$(mint_token)"
[[ "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] \
  || die "Replit returned a malformed JWT"

# Use the actual expiry; never invent a lifetime for an invalid token.
payload="${token#*.}"
payload="${payload%%.*}"
while (( ${#payload} % 4 )); do payload+="="; done
claims="$(printf '%s' "$payload" | tr '_-' '/+' | base64 -d)" \
  || die "JWT payload is not valid base64"
expiry="$(jq -er '.exp | select(type == "number" and floor == .)' <<<"$claims")" \
  || die "JWT has no valid expiration"
(( expiry > $(date +%s) )) || die "Replit returned an expired token"
jq -n --arg token "$token" --argjson expiry "$expiry" \
  '{version: 1, success: true, token_type: "urn:ietf:params:oauth:token-type:jwt",
    id_token: $token, expiration_time: $expiry}'
