# `aws-oidc`

Gives the AWS CLI and SDKs short-lived credentials for an IAM role, using a
Replit OIDC token.

## How it works

The module writes an AWS profile with a `credential_process` helper. Whenever
AWS tooling needs credentials, the helper mints a Replit token for the
`sts.amazonaws.com` audience and exchanges it with `AssumeRoleWithWebIdentity`.
No AWS credentials are stored.

Setup writes the helper to `~/.config/replit-oidc/bin/aws-credentials-<profile>`
and a managed profile in `~/.aws/config`; tokens are minted only when used.

## Usage

Setup installs missing dependencies and the AWS CLI by default, reusing existing
tools. Use `--cli-release=2.37.10` to select an exact release (also the default
for a missing CLI), or `--disable-deps-install` to manage all tools yourself.
Managed CLI releases live under `~/.local/share/replit-clis/`; repeat builds
reuse them. Open a new shell or source `~/.config/replit-oidc/env.sh` if a CLI
was installed.

Automatic installs support glibc Linux x86-64/ARM64; system packages use apt,
dnf, yum, zypper, or pacman and require root or passwordless sudo when missing.
The Replit identity CLI must already be available.

```bash
bash ./dev-modules/aws-oidc/build.sh \
  --role-arn=arn:aws:iam::123456789012:role/replit-dev \
  --region=us-east-1
```

```bash
aws sts get-caller-identity
```

| Flag | Required | Default | Description |
| --- | --- | --- | --- |
| `--cli-release` | no | Existing CLI, else `2.37.10` | Exact CLI version; installs a managed copy if the existing version differs |
| `--disable-deps-install` | no | `false` | Skip all dependency and CLI installation; use preinstalled tools |
| `--role-arn` | yes | | IAM role to assume |
| `--region` | no | | Default region |
| `--profile` | no | `default` | AWS profile to write |
| `--audience` | no | `sts.amazonaws.com` | Token audience; must match the provider's client ID |
| `--session-name` | no | `replit` | Role session name |
| `--duration-seconds` | no | `3600` | Role session duration |

For a non-default profile, use `aws --profile <profile> ...`.

## AWS setup

1. Register Replit as an OIDC provider:

   ```bash
   aws iam create-open-id-connect-provider \
     --url https://sts.replit.com \
     --client-id-list sts.amazonaws.com
   ```

2. Create a role that trusts tokens from your organization, then attach the
   permissions you need:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<account-id>:oidc-provider/sts.replit.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": { "sts.replit.com:aud": "sts.amazonaws.com" },
         "StringLike":   { "sts.replit.com:sub": "//replit.com/customer/<customer-id>/org/<org-id>/*" }
       }
     }]
   }
   ```

See [How OIDC works](../README.md#how-oidc-works) to find `<customer-id>` and
`<org-id>`.
