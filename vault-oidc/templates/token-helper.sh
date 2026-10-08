#!/usr/bin/env bash
# Implement Vault's get/store/erase token-helper protocol.
MODULE=vault-oidc
source "$(dirname "$0")/../runtime.sh"

AUDIENCE='{{AUDIENCE}}'
CACHE_FILE="${HOME}/.vault-token"

case "${1:-}" in
  get)
    if ! cache_fresh "$CACHE_FILE" '{{CACHE_TTL}}'; then
      require jq
      jwt="$(mint_token)"
      headers=()
      if [[ -n '{{VAULT_NAMESPACE}}' ]]; then
        headers+=(-H 'X-Vault-Namespace: {{VAULT_NAMESPACE}}')
      fi
      response="$(jq -n --arg role '{{ROLE}}' --arg jwt "$jwt" \
        '{role: $role, jwt: $jwt}' \
        | post_json '{{VAULT_ADDR}}/v1/auth/{{AUTH_MOUNT}}/login' "${headers[@]}")"
      token="$(jq -er '.auth.client_token | select(type == "string" and length > 0)' <<<"$response")" \
        || die "Vault response contains no valid client token"
      printf '%s' "$token" | write_private "$CACHE_FILE"
    fi
    cat "$CACHE_FILE"
    ;;
  store) write_private "$CACHE_FILE" ;;
  erase) rm -f "$CACHE_FILE" ;;
  *) die "usage: $0 get|store|erase" ;;
esac
