# `jfrog-oidc`

Installs a JFrog CLI (`jf`) wrapper that uses Replit workload identity to obtain
short-lived JFrog access tokens, without a stored JFrog password/API key.
Also provides a token helper for direct API access.

## JFrog setup

JFrog documents OIDC integration as requiring an **Enterprise X** or
**Enterprise+** license. A JFrog administrator must configure the trust
relationship before using this module:

1. Create an OpenID Connect integration with provider type **Generic OpenID
   Connect**, a provider name such as `replit`, and provider URL
   `https://sts.replit.com`.
2. Set a dedicated audience, such as `jfrog-replit`, and use exactly that value
   for the module's `--audience`.
3. Add an identity mapping with a claim restriction such as
   `{"org_id": "<org-id>"}` and only the repository permissions needed. For
   strict group-scoped permissions, leave Username blank to avoid permissions
   inherited through automatically joined groups. Add narrower workload claims
   when required by your access policy.

Replit publishes discovery at
`https://sts.replit.com/.well-known/openid-configuration` and keys at
`https://sts.replit.com/.well-known/jwks.json`. See
[How OIDC works](../README.md#how-oidc-works) for the organization claim and
subject format. Do not bind the mapping to a full sandbox-specific subject if
new sandboxes should inherit access.

The sandbox must be able to reach the JFrog platform, and JFrog
must be able to verify Replit's signing keys. Authentication cannot fix a
private-network routing problem. Verify generic OIDC availability against your
JFrog deployment and version; the public integration guide does not establish
a minimum version for this flow.

## Usage

Setup reuses an existing JFrog CLI or installs a pinned release when missing.
It installs missing `jq` and `curl` through the shared system-package installer,
which requires root or passwordless sudo. Use `--cli-release` to select a
specific JFrog CLI version, or `--disable-deps-install` to manage tools yourself.
The CLI must support `jf config add --access-token-stdin`; the default release
is 2.128.0. The Replit identity CLI is platform-provided.

```bash
bash ./dev-modules/jfrog-oidc/build.sh \
  --platform-url=https://example.jfrog.io \
  --provider-name=replit \
  --audience=jfrog-replit

source ~/.config/replit-oidc/env.sh
jf rt ping
jf rt download 'my-repository/path/to/artifact' ./downloads/
```

Source `env.sh` explicitly before using `jf` in a noninteractive build step.
Opening a new interactive shell also activates the wrapper.

| Flag | Required | Description |
| --- | --- | --- |
| `--platform-url` | yes | HTTPS platform origin, without `/artifactory` |
| `--provider-name` | yes | Name of the configured JFrog OIDC integration |
| `--audience` | yes | Audience configured for the integration |
| `--project-key` | no | JFrog project key when selecting project-scoped identity mappings |
| `--cli-release` | no | JFrog CLI version to install; default `2.128.0` when missing |
| `--disable-deps-install` | no | Skip installing JFrog CLI, `jq`, and `curl`; default `false` |

One JFrog configuration is supported per OIDC state directory. Set
`REPLIT_OIDC_STATE_DIR` before setup to use a different state directory.

### Package-manager commands

Use JFrog's per-tool configuration to select repositories, then run commands
through `jf`. For example, with Node.js/npm already installed:

```bash
jf npm-config --server-id-resolve=replit-oidc --repo-resolve=npm-virtual
jf npm ci
```

The same authenticated CLI supports `jf pip`, `jf mvn`, `jf docker`, and other
[JFrog build-tool commands](https://docs.jfrog.com/artifactory/docs/build-tool-commands).
Install the corresponding native tools and configure their repositories as
JFrog requires. Bare `npm`, `pip`, Maven, and Docker commands do not use this
wrapper's authentication automatically.

### Direct API access

`jfrog-token` prints a valid access token to stdout. Capture its output privately
for clients that accept Bearer tokens; do not print it in shared terminals or
logs. The helper uses the same token cache as the CLI wrapper.

## How it works

Setup writes `jfrog-token` and `jf` under `~/.config/replit-oidc/bin/` without
minting credentials. Before a CLI command, the helper exchanges a Replit
identity token at `/access/api/v1/oidc/token` with the configured provider name.
It caches the JFrog token and expiration in a private file, refreshing when
fewer than 60 seconds remain.

The wrapper passes the token through stdin to `jf config add`, using server ID
`replit-oidc` in a private, module-owned CLI home under
`~/.config/replit-oidc/jfrog/cli/`. The normal `~/.jfrog` configuration is
unchanged. The CLI home is selected only for wrapped commands.

Version and top-level help commands run without authentication. Exchange or
configuration failures stop the command. Re-running setup invalidates the
cached token. Refresh happens before commands, not during an ongoing operation;
configure the identity mapping's token lifetime to cover the expected duration.
Access to JFrog services and repositories follows the identity mapping's
permissions.

## References

- [JFrog OIDC integration and identity mappings](https://docs.jfrog.com/administration/docs/openid-connect-integration)
- [JFrog OIDC token exchange API](https://docs.jfrog.com/administration/reference/oidctokenexchange)
- [JFrog CLI authentication](https://docs.jfrog.com/integrations/docs/authenticating-via-the-cli)
