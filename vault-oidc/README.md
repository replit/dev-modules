# `vault-oidc`

Gives the HashiCorp Vault CLI short-lived Vault tokens through the JWT auth
method, using a Replit OIDC token.

## How it works

The module installs a Vault token helper and sets `VAULT_ADDR`. The CLI asks
the helper for a token before every command. When the cached Vault token is
older than `--cache-ttl`, the helper mints a fresh Replit token and logs in
again. `vault login` and `vault logout` still work as usual.

Setup writes the helper under `~/.config/replit-oidc/` and configures it in
`~/.vault`, which must be a file, not a directory. Tokens are minted on use
and cached in `~/.vault-token`.

## Usage

Setup installs missing `jq`, `curl`, and the Vault CLI by default, reusing
existing tools. Use `--cli-release=2.1.2` to select an exact release (also the
default for a missing CLI), or `--disable-deps-install` to manage all tools
yourself. Managed releases live under `~/.local/share/replit-clis/`; repeat
builds reuse them.

Automatic installs support glibc Linux x86-64/ARM64; system packages use apt,
dnf, yum, zypper, or pacman and require root or passwordless sudo when missing.
The Replit identity CLI must already be available.

```bash
bash ./dev-modules/vault-oidc/build.sh \
  --address=https://vault.example.com \
  --role=replit
```

Open a new shell or run `source ~/.config/replit-oidc/env.sh` to load
`VAULT_ADDR` and the optional `VAULT_NAMESPACE` in the current shell.

```bash
vault kv get secret/my-app/config
```

| Flag | Required | Default | Description |
| --- | --- | --- | --- |
| `--cli-release` | no | Existing CLI, else `2.1.2` | Exact CLI version; installs a managed copy if the existing version differs |
| `--disable-deps-install` | no | `false` | Skip all dependency and CLI installation; use preinstalled tools |
| `--address` | yes | | Vault address |
| `--role` | yes | | JWT auth role |
| `--auth-mount` | no | `jwt` | Mount path of the JWT auth method |
| `--namespace` | no | | Vault namespace (Enterprise and HCP) |
| `--audience` | no | host of `--address` | Token audience; must match the role's `bound_audiences` |
| `--cache-ttl` | no | `300` | Seconds to reuse a Vault token before logging in again |

## Vault setup

Enable JWT auth with Replit as the discovery URL, and create a role bound to
your organization:

```bash
vault auth enable jwt
vault write auth/jwt/config oidc_discovery_url=https://sts.replit.com

vault write auth/jwt/role/replit - <<'JSON'
{
  "role_type": "jwt",
  "user_claim": "sub",
  "bound_audiences": ["vault.example.com"],
  "bound_claims": { "org_id": "<org-id>" },
  "token_policies": ["<policy>"]
}
JSON
```

`bound_audiences` is the host (and port, if any) of `--address`. Write the role
from JSON, because `bound_claims` is a map.

See [How OIDC works](../README.md#how-oidc-works) to find `<org-id>`.
