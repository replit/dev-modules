# `jfrog-oidc`

Installs an npm wrapper that uses Replit workload identity to obtain short-lived
JFrog tokens for an Artifactory npm repository. It does not require JFrog CLI or
a stored JFrog password/API key.

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

The sandbox must be able to reach the JFrog platform and registry, and JFrog
must be able to verify Replit's signing keys. Authentication cannot fix a
private-network routing problem. Verify generic OIDC availability against your
JFrog deployment and version; the public integration guide does not establish
a minimum version for this flow.

## Usage

Use an environment with Node.js/npm already installed. Setup installs missing
`jq` and `curl` by default, using the shared system-package installer; it
requires root or passwordless sudo when packages are missing. On NixOS, install
those tools in the environment first. Use `--disable-deps-install` to manage
them yourself. The Replit identity CLI is platform-provided.

```bash
bash ./dev-modules/jfrog-oidc/build.sh \
  --platform-url=https://example.jfrog.io \
  --provider-name=replit \
  --audience=jfrog-replit \
  --registry=https://example.jfrog.io/artifactory/api/npm/npm-virtual/

source ~/.config/replit-oidc/env.sh
npm ci
```

Source `env.sh` explicitly before an install in a noninteractive build step.
Opening a new interactive shell also activates the wrapper.

| Flag | Required | Description |
| --- | --- | --- |
| `--platform-url` | yes | HTTPS platform origin, without `/artifactory` |
| `--provider-name` | yes | Name of the configured JFrog OIDC integration |
| `--audience` | yes | Audience configured for the integration |
| `--registry` | yes | Full HTTPS npm repository URL |
| `--scope` | no | Route only this npm scope, such as `@myorg`; otherwise set the default registry |
| `--project-key` | no | JFrog project key when selecting project-scoped identity mappings |
| `--disable-deps-install` | no | Skip installing `jq` and `curl`; default `false` |

`--cli-release` is not applicable: the module uses the environment's npm.
One JFrog configuration is supported per OIDC state directory. Set
`REPLIT_OIDC_STATE_DIR` before setup to use a different state directory.

## How it works

Setup writes a token helper and an `npm` wrapper under
`~/.config/replit-oidc/bin/`. It adds a marked block to the user npm config
(`NPM_CONFIG_USERCONFIG`, otherwise `~/.npmrc`), preserving unrelated settings.
The block contains a repository-scoped `_authToken=${REPLIT_JFROG_TOKEN}`
reference, not a token.

Setup does not mint credentials. On npm use, the helper mints a Replit identity
token and exchanges it at `/access/api/v1/oidc/token` with the configured
provider name. It caches the resulting JFrog token and expiration in a private
file, refreshing when fewer than 60 seconds remain. The wrapper supplies the
token only to the child npm process. Version and help commands run without
authentication. Exchange failures stop npm rather than falling back to another
identity. Re-running setup invalidates the cached credentials.

Refresh happens before starting npm, not during an ongoing install. Configure
the JFrog mapping's token lifetime to cover the expected command duration.
Project `.npmrc` settings take precedence over user settings, and lockfiles may
pin a different registry URL. Match the configured URL to the actual registry
paths used by the project; no project config, source, or lockfile is rewritten.
npm may reuse registry credentials for other paths on the same host; the
configuration path is not an authorization boundary. Enforce repository access
in the JFrog identity mapping and permissions.
The wrapper covers `npm` invocations through the activated PATH, not absolute
npm paths or other package managers.

## Local validation

With Python 3, OpenSSL, Node.js/npm, `jq`, and `curl` on PATH:

```bash
python3 jfrog-oidc/tests/integration.py
```

This runs real npm against a local HTTPS token-exchange and package-registry
fixture, with a fake Replit identity command. It checks a lockfile-based private
package install, lazy authentication, token caching and refresh, safe failures,
cross-host credential scoping, file permissions, repeat setup, and wrapper
priority. It does not verify a live JFrog deployment's trust configuration.

## References

- [JFrog OIDC integration and identity mappings](https://docs.jfrog.com/administration/docs/openid-connect-integration)
- [JFrog OIDC token exchange API](https://docs.jfrog.com/administration/reference/oidctokenexchange)
- [Artifactory npm repositories](https://docs.jfrog.com/artifactory/docs/npm-repositories)
- [npm user configuration and authentication scope](https://docs.npmjs.com/cli/v11/configuring-npm/npmrc)
