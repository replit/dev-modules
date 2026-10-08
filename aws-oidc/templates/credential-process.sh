#!/usr/bin/env bash
# Exchange a Replit token for AWS credential_process JSON.
MODULE=aws-oidc
source "$(dirname "$0")/../runtime.sh"

AUDIENCE='{{AUDIENCE}}'
require aws
token="$(mint_token)"

# Avoid recursively invoking this profile during the unsigned exchange.
env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
  aws sts assume-role-with-web-identity \
    --role-arn '{{ROLE_ARN}}' \
    --role-session-name '{{SESSION_NAME}}' \
    --web-identity-token "$token" \
    --duration-seconds '{{DURATION_SECONDS}}' \
    --query 'Credentials.{Version: `1`, AccessKeyId: AccessKeyId, SecretAccessKey: SecretAccessKey, SessionToken: SessionToken, Expiration: Expiration}' \
    --output json || die "AWS role exchange failed"
