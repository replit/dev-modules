#!/usr/bin/env bash
# Install the AWS credential process and managed profile.
set -euo pipefail
OIDC_MODULE_NAME=aws-oidc
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/oidc.sh
. "${MODULE_DIR}/../lib/oidc.sh"

oidc_parse_args role-arn region profile audience session-name duration-seconds -- "$@"
oidc_require OPT_role_arn role-arn
: "${OPT_region:=}" "${OPT_profile:=default}" "${OPT_audience:=sts.amazonaws.com}"
: "${OPT_session_name:=replit}" "${OPT_duration_seconds:=3600}"
oidc_positive_integer duration-seconds "$OPT_duration_seconds"
[[ "$OPT_profile" =~ ^[a-zA-Z0-9_-]+$ ]] || oidc_die "--profile must contain only letters, digits, underscores or hyphens"

source "${MODULE_DIR}/../lib/dependencies.sh"
oidc_dependencies aws 2.37.10

PROFILE="$OPT_profile"
ROLE_ARN="$OPT_role_arn"
AUDIENCE="$OPT_audience"
SESSION_NAME="$OPT_session_name"
DURATION_SECONDS="$OPT_duration_seconds"
HELPER="$(oidc_install_helper "aws-credentials-${PROFILE}" "${MODULE_DIR}/templates/credential-process.sh" \
  PROFILE ROLE_ARN AUDIENCE SESSION_NAME DURATION_SECONDS)"

PROFILE_HEADER="[default]"
if [[ "$PROFILE" != default ]]; then PROFILE_HEADER="[profile ${PROFILE}]"; fi
REGION_LINE=""
if [[ -n "$OPT_region" ]]; then REGION_LINE="region = ${OPT_region}"; fi
oidc_render "${MODULE_DIR}/templates/aws-config.ini" PROFILE_HEADER HELPER REGION_LINE \
  | oidc_replace_block "${HOME}/.aws/config" \
      "# BEGIN replit aws-oidc ${PROFILE}" "# END replit aws-oidc ${PROFILE}"


if ! command -v aws >/dev/null 2>&1; then
  oidc_log "note: aws CLI not installed; credential_process needs it at call time"
fi
oidc_log "configured AWS profile '${PROFILE}' -> ${ROLE_ARN} via ${HELPER}"
