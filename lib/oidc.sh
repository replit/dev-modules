#!/usr/bin/env bash
# Shared installation helpers; runtime credential logic lives in runtime.sh.

set -Eeuo pipefail
trap 'status=$?; printf "%s: error: setup failed at line %s (exit %s)\n" "${OIDC_MODULE_NAME:-oidc}" "$LINENO" "$status" >&2; exit "$status"' ERR

OIDC_STATE_DIR="${REPLIT_OIDC_STATE_DIR:-${HOME}/.config/replit-oidc}"
OIDC_BIN_DIR="${OIDC_STATE_DIR}/bin"
OIDC_ENV_FILE="${OIDC_STATE_DIR}/env.sh"
OIDC_MANAGED_MARKER='# Managed by replit oidc modules.'

oidc_log() { printf '%s: %s\n' "${OIDC_MODULE_NAME:-oidc}" "$*" >&2; }
oidc_die() { oidc_log "error: $*"; exit 1; }

# Parse declared --key=value or --key value options into OPT_key variables.
oidc_parse_args() {
  local -a names=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do names+=("$1"); shift; done
  names+=(disable-deps-install cli-release)
  if [[ "${1:-}" == "--" ]]; then shift; fi
  local arg key value known n
  while [[ $# -gt 0 ]]; do
    arg="$1"; shift
    [[ "$arg" == --* ]] || oidc_die "unexpected argument: $arg"
    arg="${arg#--}"
    if [[ "$arg" == disable-deps-install ]]; then
      key="$arg"; value=true
    elif [[ "$arg" == *=* ]]; then
      key="${arg%%=*}"; value="${arg#*=}"
    else
      key="$arg"
      [[ $# -gt 0 && "$1" != --* ]] || oidc_die "--$key needs a value"
      value="$1"; shift
    fi
    known=0
    for n in "${names[@]}"; do
      if [[ "$n" == "$key" ]]; then known=1; fi
    done
    [[ "$known" == 1 ]] || oidc_die "unknown flag --$key"
    [[ "$value" != *"'"* && "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
      || oidc_die "--$key contains unsupported quote or newline characters"
    printf -v "OPT_${key//-/_}" '%s' "$value"
  done
}

# oidc_require OPT_VAR FLAG — fail unless the flag was given.
oidc_require() { [[ -n "${!1:-}" ]] || oidc_die "--${2:-${1#OPT_}} is required"; }

# Restrict arithmetic options to positive decimal integers.
oidc_positive_integer() {
  [[ "$2" =~ ^[1-9][0-9]{0,8}$ ]] || oidc_die "--$1 must be a positive integer (at most 9 digits)"
}

# oidc_write_file PATH [MODE] < content — atomic write, owner-only directory.
oidc_write_file() (
  local path="$1" mode="${2:-0600}" dir tmp
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  chmod 0700 "$dir"
  tmp="$(mktemp "${dir}/.$(basename "$path").XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  cat >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
)

# Render named placeholders, rejecting any left unresolved.
oidc_render() {
  local template="$1" content name
  shift
  content="$(cat "$template")"
  for name in "$@"; do
    content="${content//\{\{${name}\}\}/${!name:-}}"
  done
  if [[ "$content" == *"{{"* ]]; then
    oidc_die "unrendered placeholder in $(basename "$template"): $(grep -o '{{[A-Z_]*}}' <<<"$content" | head -1)"
  fi
  printf '%s\n' "$content"
}

# Install a helper and its shared runtime, then print the helper path.
oidc_install_helper() {
  local name="$1" template="$2"
  shift 2
  oidc_write_file "${OIDC_STATE_DIR}/runtime.sh" <"${MODULE_DIR}/../lib/runtime.sh"
  oidc_render "$template" "$@" | oidc_write_file "${OIDC_BIN_DIR}/${name}" 0700
  printf '%s\n' "${OIDC_BIN_DIR}/${name}"
}

# Prepend the wrapper directory once, even if PATH already contains it later.
oidc_env_prepend_path() {
  local dir="$1"
  # Keep this POSIX-compatible because .profile may be read by a non-Bash shell.
  local line
  line="$(cat <<EOF
_oidc_path=":\${PATH:-}:"
while :; do
  case \$_oidc_path in
    *":${dir}:"*) _oidc_path="\${_oidc_path%%:${dir}:*}:\${_oidc_path#*:${dir}:}" ;;
    *) break ;;
  esac
done
_oidc_path=\${_oidc_path#:}
_oidc_path=\${_oidc_path%:}
export PATH="${dir}\${_oidc_path:+:\$_oidc_path}"
unset _oidc_path
EOF
)"
  oidc_env_set --raw "$line"
}

# Persist exports or a literal block and source them from interactive shells.
oidc_env_set() {
  local line current="" rc
  mkdir -p "$OIDC_STATE_DIR"
  if [[ "$1" == "--raw" ]]; then
    line="$2"
    if [[ -f "$OIDC_ENV_FILE" ]]; then
      current="$(cat "$OIDC_ENV_FILE")"
      current="${current//"$line"/}"
    fi
  else
    printf -v line 'export %s=%q' "$1" "$2"
    if [[ -f "$OIDC_ENV_FILE" ]]; then current="$(grep -v "^export $1=" "$OIDC_ENV_FILE" || true)"; fi
  fi
  {
    if [[ -n "$current" ]]; then printf '%s\n' "$current"; fi
    printf '%s\n' "$line"
  } | oidc_write_file "$OIDC_ENV_FILE" 0600

  local hook="[ -f \"${OIDC_ENV_FILE}\" ] && . \"${OIDC_ENV_FILE}\" ${OIDC_MANAGED_MARKER}"
  for rc in "${HOME}/.bashrc" "${HOME}/.profile"; do
    touch "$rc"
    grep -qF "$OIDC_MANAGED_MARKER" "$rc" || printf '\n%s\n' "$hook" >>"$rc"
  done
}

# Replace only our marked block, preserving unrelated provider config.
oidc_replace_block() (
  local file="$1" begin="$2" end="$3" content tmp
  content="$(cat)"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp "${file}.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  awk -v b="$begin" -v e="$end" -v c="$content" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
    END { print b; print c; print e }
  ' "$file" >"$tmp"
  chmod --reference="$file" "$tmp"
  mv -f "$tmp" "$file"
)
