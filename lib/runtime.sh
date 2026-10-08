#!/usr/bin/env bash
# Shared runtime for generated credential helpers; keep stdout for credentials.
set -Eeuo pipefail
umask 077

log() { printf '%s: %s\n' "$MODULE" "$*" >&2; }
die() { log "error: $*"; exit 1; }
trap 'status=$?; log "error: operation failed at line $LINENO (exit $status)"; exit "$status"' ERR

require() {
  local command
  for command in "$@"; do
    command -v "$command" >/dev/null || die "required command not found: $command"
  done
}

mint_token() {
  require replit
  local token
  token="$(replit identityv2 create --audience "$AUDIENCE")" || die "could not mint Replit identity token"
  [[ -n "$token" ]] || die "Replit returned an empty identity token"
  printf '%s' "$token"
}

# Publish complete private files without predictable temporary filenames.
write_private() (
  local path="$1" tmp
  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp "${path}.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  cat >"$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$path"
)

cache_fresh() {
  local modified now age
  [[ -s "$1" ]] || return 1
  modified="$(stat -c %Y "$1")" || die "cannot read cache timestamp"
  now="$(date +%s)" || die "cannot read current time"
  age=$((now - modified))
  (( age >= 0 && age < $2 ))
}

# Ignore this wrapper, including equivalent PATH spellings.
find_cli() {
  local name="$1" dir candidate
  local -a entries
  IFS=: read -ra entries <<<"$PATH"
  for dir in "${entries[@]}"; do
    candidate="${dir:-.}/$name"
    if [[ -x "$candidate" && ! "$candidate" -ef "$0" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
  die "real $name CLI not found on PATH"
}

# Do not log request or response bodies: either can contain credentials.
post_json() {
  require curl
  curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
    -H 'Content-Type: application/json' --data-binary @- "$@" \
    || die "credential exchange failed"
}
