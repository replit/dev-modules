# `infisical-oidc`

Gives the Infisical CLI short-lived access tokens for a machine identity,
using a Replit OIDC token.

## How it works

The module puts an `infisical` wrapper ahead of the real `infisical` on
`PATH`. When the cached access token is older than `--login-ttl`, the wrapper
mints a Replit token and logs in through JWT auth. It then runs the real CLI
with `INFISICAL_TOKEN` set for that command, not for the parent shell or
separately launched SDKs. Explicit `login` and `logout` pass through and clear
the wrapper's cached token.

Setup writes the wrapper and settings under `~/.config/replit-oidc/` without
minting tokens. The access token is cached there when the CLI is used.

## Usage

Setup installs missing `jq`, `curl`, and the Infisical CLI by default, reusing
existing tools. Use `--cli-release=0.43.139` to select an exact release (also
the default for a missing CLI), or `--disable-deps-install` to manage all
tools yourself. Managed releases live under `~/.local/share/replit-clis/`;
repeat builds reuse them.

Automatic installs support glibc Linux x86-64/ARM64; system packages use apt,
dnf, yum, zypper, or pacman and require root or passwordless sudo when missing.
The Replit identity CLI must already be available. Authentication failures
stop the command rather than falling back to another identity.

```bash
bash ./dev-modules/infisical-oidc/build.sh \
  --identity-id=<machine-identity-id> \
  --project-id=<project-id> \
  --environment=dev
```

Open a new shell or run `source ~/.config/replit-oidc/env.sh` to activate the
wrapper and `INFISICAL_API_URL`, `INFISICAL_PROJECT_ID`, and
`INFISICAL_ENVIRONMENT` settings.

```bash
infisical secrets --projectId "$INFISICAL_PROJECT_ID" --env "$INFISICAL_ENVIRONMENT"
```

| Flag | Required | Default | Description |
| --- | --- | --- | --- |
| `--cli-release` | no | Existing CLI, else `0.43.139` | Exact CLI version; installs a managed copy if the existing version differs |
| `--disable-deps-install` | no | `false` | Skip all dependency and CLI installation; use preinstalled tools |
| `--identity-id` | yes | | Machine identity ID |
| `--project-id` | yes | | Project ID |
| `--environment` | no | `dev` | Environment slug |
| `--domain` | no | `https://app.infisical.com` | Infisical instance |
| `--audience` | no | `infisical` | Token audience; must match the identity's audiences |
| `--login-ttl` | no | `3000` | Seconds to reuse an access token before logging in again |

## Infisical setup

Create a machine identity with **JWT** auth, then add it to the project with
the role it needs:

| Field | Value |
| --- | --- |
| Configuration type | JWKS |
| JWKS URL | `https://sts.replit.com/.well-known/jwks.json` |
| Issuer | `https://sts.replit.com` |
| Audiences | `infisical` |
| Claims | `org_id` = `<org-id>` |

Use the full JWKS URL; Infisical rejects the bare issuer host.

See [How OIDC works](../README.md#how-oidc-works) to find `<org-id>`.
