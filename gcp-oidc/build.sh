#!/usr/bin/env bash
# Install Google's executable credential source and external-account config.
set -euo pipefail
OIDC_MODULE_NAME=gcp-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args workload-identity-provider service-account project audience -- "$@"
oidc_require OPT_workload_identity_provider workload-identity-provider
: "${OPT_service_account:=}" "${OPT_project:=}"
: "${OPT_audience:=//iam.googleapis.com/${OPT_workload_identity_provider}}"
# GCP's canonical audience is //iam.googleapis.com/<provider>; accept the https:// spelling.
OPT_audience="${OPT_audience#https:}"

source "${MODULE_DIR}/../lib/dependencies.sh"
oidc_dependencies gcloud 588.0.0 jq base64

AUDIENCE="$OPT_audience"
HELPER="$(oidc_install_helper gcp-subject-token "${MODULE_DIR}/templates/subject-token.sh" AUDIENCE)"

IMPERSONATION_LINE=""
if [[ -n "$OPT_service_account" ]]; then
  IMPERSONATION_LINE="\"service_account_impersonation_url\": \"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${OPT_service_account}:generateAccessToken\","
fi
CRED="${OIDC_STATE_DIR}/gcp-external-account.json"
oidc_render "${MODULE_DIR}/templates/external-account.json" AUDIENCE HELPER IMPERSONATION_LINE \
  | sed '/^  $/d' | oidc_write_file "$CRED" 0600

if command -v gcloud >/dev/null 2>&1; then
  gcloud config set auth/credential_file_override "$CRED" --quiet >/dev/null \
    || oidc_die "gcloud credential registration failed"
  if [[ -n "$OPT_project" ]]; then
    gcloud config set project "$OPT_project" --quiet >/dev/null \
      || oidc_die "gcloud project selection failed"
  fi
else
  oidc_log "note: gcloud not installed; SDKs can use ${CRED}"
fi

# Google libraries refuse executable credential sources unless this is set.
oidc_env_set GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES 1
oidc_env_set GOOGLE_APPLICATION_CREDENTIALS "$CRED"
if [[ -n "$OPT_project" ]]; then oidc_env_set GOOGLE_CLOUD_PROJECT "$OPT_project"; fi

oidc_log "configured Workload Identity Federation via ${CRED} (helper ${HELPER})"
