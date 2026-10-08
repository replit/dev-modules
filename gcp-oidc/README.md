# `gcp-oidc`

Gives gcloud and the Google Cloud SDKs short-lived credentials through
Workload Identity Federation, using a Replit OIDC token.

## How it works

The module writes an `external_account` credential whose subject token comes
from a helper executable, and points `GOOGLE_APPLICATION_CREDENTIALS` (and
gcloud, if installed) at it. When a token is needed, gcloud or the SDK runs
the helper, which mints a Replit token. Google STS exchanges that token and
can then impersonate a service account.

The helper and credential file live under `~/.config/replit-oidc/`. If gcloud
is installed, setup sets `auth/credential_file_override` without minting a token;
registration or project-selection failures stop setup.

## Usage

Setup installs missing `jq`, `base64`, and gcloud dependencies and tooling by
default, reusing existing tools. Use `--cli-release=588.0.0` to select an exact
release (also the default for missing gcloud), or `--disable-deps-install` to
manage tools yourself or configure SDK-only access. Managed releases live
under `~/.local/share/replit-clis/`; repeat builds reuse them.

Automatic installs support glibc Linux x86-64/ARM64; system packages use apt,
dnf, yum, zypper, or pacman and require root or passwordless sudo when missing.
The Replit identity CLI must already be available.

```bash
bash ./dev-modules/gcp-oidc/build.sh \
  --workload-identity-provider=projects/123456789/locations/global/workloadIdentityPools/replit/providers/replit-oidc \
  --service-account=replit-dev@my-project.iam.gserviceaccount.com \
  --project=my-project
```

Open a new shell or run `source ~/.config/replit-oidc/env.sh` to load
`GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES=1`,
and the optional `GOOGLE_CLOUD_PROJECT`. If you install gcloud later, register
the credential with `gcloud config set auth/credential_file_override "$GOOGLE_APPLICATION_CREDENTIALS"`.

```bash
gcloud secrets versions access latest --secret=my-secret
```

| Flag | Required | Default | Description |
| --- | --- | --- | --- |
| `--cli-release` | no | Existing CLI, else `588.0.0` | Exact CLI version; installs a managed copy if the existing version differs |
| `--disable-deps-install` | no | `false` | Skip all dependency and CLI installation; use preinstalled tools |
| `--workload-identity-provider` | yes | | Full provider resource name |
| `--service-account` | no | | Service account to impersonate; omit to use the federated identity directly |
| `--project` | no | | Default project |
| `--audience` | no | `//iam.googleapis.com/<provider>` | Token audience; must match the provider's allowed audiences |

If `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` is set, unset it, or gcloud keeps
using that credential instead of this one.

## Google Cloud setup

1. Create a pool and a provider that trusts Replit and only accepts your
   organization:

   ```bash
   gcloud iam workload-identity-pools create replit --location=global

   gcloud iam workload-identity-pools providers create-oidc replit-oidc \
     --location=global --workload-identity-pool=replit \
     --issuer-uri=https://sts.replit.com \
     --attribute-mapping='google.subject=assertion.sub,attribute.org_id=assertion.org_id' \
     --attribute-condition='assertion.org_id == "<org-id>"'
   ```

2. Let the pool impersonate a service account that has the permissions you
   need:

   ```bash
   gcloud iam service-accounts add-iam-policy-binding <service-account-email> \
     --role=roles/iam.workloadIdentityUser \
     --member='principalSet://iam.googleapis.com/projects/<project-number>/locations/global/workloadIdentityPools/replit/attribute.org_id/<org-id>'
   ```

See [How OIDC works](../README.md#how-oidc-works) to find `<org-id>`.
