# Replit Dev Modules

A collection of prebuilt modules for developing software with Replit.

## Modules

| Module | What it does |
| --- | --- |
| [`aws-oidc`](./aws-oidc/README.md) | Sets up the AWS CLI and SDKs with short-lived AWS credentials |
| [`gcp-oidc`](./gcp-oidc/README.md) | Sets up gcloud and the Google Cloud SDKs with short-lived Google Cloud credentials |
| [`azure-oidc`](./azure-oidc/README.md) | Sets up the Azure CLI and SDKs with short-lived Microsoft Entra credentials |
| [`vault-oidc`](./vault-oidc/README.md) | Sets up the HashiCorp Vault CLI with short-lived Vault tokens |
| [`infisical-oidc`](./infisical-oidc/README.md) | Sets up the Infisical CLI with short-lived Infisical access tokens |

Each module's README covers its usage and options.

## How OIDC works

Replit fully supports workload identity federation. Replit is an OpenID Connect
(OIDC) identity provider, so any service that accepts external OIDC tokens can
trust Replit workloads directly, with no long-lived credentials to store or
rotate.

Mint a short-lived token for an audience:

```bash
replit identityv2 create --audience <audience>
```

Tokens are issued by `https://sts.replit.com`. Services discover it at
`https://sts.replit.com/.well-known/openid-configuration` and verify
signatures against `https://sts.replit.com/.well-known/jwks.json`.

Every token carries at least these claims:

```json
{
  "iss": "https://sts.replit.com",
  "sub": "//replit.com/customer/<customer-id>/org/<org-id>/<kind>/<sandbox-id>",
  "aud": "<audience>",
  "exp": 1767225900,
  "jti": "00000000-0000-0000-0000-000000000000",
  "kind": "<kind>",
  "customer_id": "<customer-id>",
  "org_id": "<org-id>",
  "sandbox_id": "<sandbox-id>",
  "resource_group_id": "<resource-group-id>",
  ...
}
```

The `sub` prefix `//replit.com/customer/<customer-id>/org/<org-id>/` is the
same for every token in an organization; the rest identifies the workload that
minted it, and varies by kind. Additional claims depend on the kind of
workload. Bind trust to `org_id` (or the `sub` prefix), not to the full
subject.

To see your own values, decode a token's body:

```bash
replit identityv2 create --audience TEST \
  | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | python3 -m json.tool
```

## Security

Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
