# `azure-oidc`

Gives the Azure CLI and SDKs short-lived Microsoft Entra credentials, using a
Replit OIDC token and workload identity federation.

## How it works

The module puts an `az` wrapper ahead of the real `az` on `PATH`. On each call
it mints a Replit token for the `api://AzureADTokenExchange` audience, writes
it to `AZURE_FEDERATED_TOKEN_FILE`, and logs in again when the previous login
is older than 50 minutes. Azure SDKs read the same file through
`WorkloadIdentityCredential` or `DefaultAzureCredential`, so they are only as
fresh as the last `az` call.

Authentication failures stop the command. Explicit `az login` and `az logout`
pass through and invalidate the wrapper's login cache.

### Token subject

Entra matches the token's `sub` exactly and ignores every other claim. A
normal Replit subject ends with the workload that minted it
(`//replit.com/customer/<customer-id>/org/<org-id>/<kind>/<sandbox-id>`), so it
could never match one federated credential across workloads.

For the `api://AzureADTokenExchange` audience, Replit instead issues the
organization-scoped subject:

```
//replit.com/customer/<customer-id>/org/<org-id>
```

Every workload in the organization gets the same subject, so a single
federated credential covers them all. The workload stays identifiable through
the `sandbox_id` claim. If you pass a different `--audience`, you get the
normal per-workload subject.

## Usage

Setup installs missing dependencies and the Azure CLI by default, reusing
existing tools. Use `--cli-release=2.91.0` to select an exact release (also the
default for a missing CLI), or `--disable-deps-install` to manage all tools
yourself. Managed releases use Python virtual environments under
`~/.local/share/replit-clis/`; repeat builds reuse them.

Automatic installs support glibc Linux x86-64/ARM64; system packages use apt,
dnf, yum, zypper, or pacman and require root or passwordless sudo when missing.
Azure installation needs a Python version supported by the selected Azure
release, with `venv` and `ensurepip` (Debian/Ubuntu installs `python3-venv`
when missing). The Replit identity CLI must already be available.

Setup installs the wrapper and SDK settings under `~/.config/replit-oidc/`;
it does not log in or mint a token.

```bash
bash ./dev-modules/azure-oidc/build.sh \
  --client-id=<client-id> \
  --tenant-id=<tenant-id> \
  --subscription-id=<subscription-id>
```

Open a new shell or run `source ~/.config/replit-oidc/env.sh` to activate the
wrapper and `AZURE_*` settings in the current shell.

```bash
az account show
```

| Flag | Required | Default | Description |
| --- | --- | --- | --- |
| `--cli-release` | no | Existing CLI, else `2.91.0` | Exact CLI version; installs a managed copy if the existing version differs |
| `--disable-deps-install` | no | `false` | Skip all dependency and CLI installation; use preinstalled tools |
| `--client-id` | yes | | Client ID of the managed identity or app registration |
| `--tenant-id` | yes | | Entra tenant ID |
| `--subscription-id` | no | | Subscription to select after login |
| `--audience` | no | `api://AzureADTokenExchange` | Token audience; must match the federated credential |

## Azure setup

1. Create a user-assigned managed identity (or an app registration).
2. Add a federated credential for your organization's subject:

   ```bash
   az identity federated-credential create \
     --name replit \
     --identity-name <identity-name> \
     --resource-group <resource-group> \
     --issuer https://sts.replit.com \
     --subject "//replit.com/customer/<customer-id>/org/<org-id>" \
     --audiences api://AzureADTokenExchange
   ```

3. Grant the identity the Azure roles you need.

See [How OIDC works](../README.md#how-oidc-works) to find `<customer-id>` and
`<org-id>`.
