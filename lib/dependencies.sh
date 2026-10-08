#!/usr/bin/env bash
# Build-time only: credential helpers never install software.

oidc_as_root() {
  if (( EUID == 0 )); then
    "$@"
  elif command -v sudo >/dev/null; then
    sudo -n "$@"
  else
    oidc_die "installing system packages requires root or passwordless sudo; preinstall them and use --disable-deps-install"
  fi
}

oidc_packages() {
  (( $# )) || return 0
  oidc_log "installing missing packages: $*"
  if command -v apt-get >/dev/null; then
    oidc_as_root apt-get update
    oidc_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
  elif command -v dnf >/dev/null; then
    oidc_as_root dnf install -y "$@"
  elif command -v yum >/dev/null; then
    oidc_as_root yum install -y "$@"
  elif command -v zypper >/dev/null; then
    oidc_as_root zypper --non-interactive install "$@"
  elif command -v pacman >/dev/null; then
    oidc_as_root pacman -S --needed --noconfirm "$@"
  else
    oidc_die "no supported package manager; preinstall $* or use --disable-deps-install"
  fi
}

oidc_commands() {
  local command package
  local -a missing=()
  for command in "$@"; do
    command -v "$command" >/dev/null && continue
    case "$command" in
      base64|stat|install) package=coreutils ;;
      python3)
        package=python3
        if command -v pacman >/dev/null; then package=python; fi
        ;;
      *) package="$command" ;;
    esac
    [[ " ${missing[*]} " == *" $package "* ]] || missing+=("$package")
  done
  oidc_packages "${missing[@]}"
  for command in "$@"; do
    command -v "$command" >/dev/null || oidc_die "package installation did not provide $command"
  done
}

oidc_real_cli() {
  local cli="$1" dir
  local -a entries
  IFS=: read -ra entries <<<"$PATH"
  for dir in "${entries[@]}"; do
    dir="${dir:-.}"
    [[ "$dir" -ef "$OIDC_BIN_DIR" ]] && continue
    if [[ -x "$dir/$cli" && ! -d "$dir/$cli" && ! "$dir/$cli" -ef "$OIDC_BIN_DIR/$cli" ]]; then
      printf '%s\n' "$dir/$cli"
      return 0
    fi
  done
  return 1
}

oidc_cli_version() {
  local output
  output="$("$1" --version 2>&1)" || return 1
  [[ "$output" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

oidc_download() {
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 20 --max-time 300 "$1" --output "$2"
}

oidc_cli_install() (
  local cli="$1" release="$2" destination="$3" arch go_arch google_arch work
  [[ "$(uname -s)" == Linux ]] || oidc_die "automatic CLI installation requires Linux; use --disable-deps-install with preinstalled tools"
  [[ ! -e /etc/alpine-release ]] || oidc_die "vendor binaries require glibc; preinstall tools on Alpine and use --disable-deps-install"
  case "$(uname -m)" in
    x86_64) arch=x86_64; go_arch=amd64; google_arch=x86_64 ;;
    aarch64|arm64) arch=aarch64; go_arch=arm64; google_arch=arm ;;
    *) oidc_die "unsupported CLI architecture: $(uname -m)" ;;
  esac
  oidc_commands curl install
  if [[ ! -r /etc/ssl/certs/ca-certificates.crt && ! -r /etc/pki/tls/certs/ca-bundle.crt ]]; then
    oidc_packages ca-certificates
  fi
  case "$cli" in
    aws|vault) oidc_commands unzip ;;
    gcloud) oidc_commands tar gzip python3 ;;
    infisical) oidc_commands tar gzip ;;
    az)
      oidc_commands python3
      if ! python3 -c 'import venv, ensurepip' >/dev/null 2>&1; then
        if command -v apt-get >/dev/null; then
          oidc_packages python3-venv
        else
          oidc_die "Python venv and ensurepip are required; install them for your Python interpreter"
        fi
      fi
      ;;
  esac
  work="$(mktemp -d)"
  trap 'rm -rf -- "$work"' EXIT
  oidc_log "installing $cli $release"
  mkdir -p "$destination"
  case "$cli" in
    aws)
      oidc_download "https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${release}.zip" "$work/aws.zip"
      unzip -q "$work/aws.zip" -d "$work"
      "$work/aws/install" --install-dir "$destination/aws" --bin-dir "$destination/bin" --update
      ;;
    gcloud)
      oidc_download "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${release}-linux-${google_arch}.tar.gz" "$work/gcloud.tar.gz"
      tar -xzf "$work/gcloud.tar.gz" -C "$destination"
      mkdir -p "$destination/bin"
      ln -sfn "$destination/google-cloud-sdk/bin/gcloud" "$destination/bin/gcloud"
      ;;
    az)
      python3 -m venv "$destination"
      "$destination/bin/python" -m pip install --disable-pip-version-check "azure-cli==$release"
      ;;
    vault)
      oidc_download "https://releases.hashicorp.com/vault/${release}/vault_${release}_linux_${go_arch}.zip" "$work/vault.zip"
      unzip -q "$work/vault.zip" -d "$work"
      install -Dm755 "$work/vault" "$destination/bin/vault"
      ;;
    infisical)
      oidc_download "https://github.com/Infisical/cli/releases/download/v${release}/cli_${release}_linux_${go_arch}.tar.gz" "$work/infisical.tar.gz"
      tar -xzf "$work/infisical.tar.gz" -C "$work"
      install -Dm755 "$work/infisical" "$destination/bin/infisical"
      ;;
  esac
)

oidc_dependencies() {
  local cli="$1" default_release="$2"
  shift 2
  local release="${OPT_cli_release:-$default_release}" existing version destination
  [[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || oidc_die "--cli-release must be a version such as $default_release"
  case "${OPT_disable_deps_install:-false}" in
    true)
      oidc_log "dependency installation disabled; required tools: $cli replit $*"
      return 0
      ;;
    false) ;;
    *) oidc_die "--disable-deps-install accepts only true or false" ;;
  esac
  # Replit identity is platform-provided, not an installable provider package.
  command -v replit >/dev/null || oidc_die "run this module where the Replit identity CLI is available"
  oidc_commands "$@"
  existing="$(oidc_real_cli "$cli" || true)"
  if [[ -n "$existing" ]]; then
    if [[ -z "${OPT_cli_release:-}" ]]; then
      oidc_log "using existing $cli at $existing"
      return 0
    fi
    version="$(oidc_cli_version "$existing" || true)"
    [[ "$version" != "$release" ]] || return 0
  fi
  destination="${HOME}/.local/share/replit-clis/$cli/$release"
  version=""
  if [[ -x "$destination/bin/$cli" ]]; then
    version="$(oidc_cli_version "$destination/bin/$cli" || true)"
  fi
  if [[ "$version" != "$release" ]]; then
    oidc_cli_install "$cli" "$release" "$destination"
    version="$(oidc_cli_version "$destination/bin/$cli" || true)"
    [[ "$version" == "$release" ]] || oidc_die "$cli installation did not provide requested release $release"
  fi
  export PATH="$destination/bin:$PATH"
  oidc_env_prepend_path "$destination/bin"
  # Other modules may already have installed wrappers that must remain first.
  if [[ -x "$OIDC_BIN_DIR/az" || -x "$OIDC_BIN_DIR/infisical" ]]; then
    oidc_env_prepend_path "$OIDC_BIN_DIR"
  fi
}
