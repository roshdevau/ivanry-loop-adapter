#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
AWS_PROFILE="${AWS_PROFILE:-roshanpersonal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="PortfolioPreviewFrontendStack"
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
RUNTIME_TARGET="$ROOT_DIR/e2e/.secrets/preview-runtime.json"
test "$AWS_PROFILE" = "roshanpersonal"
test "$AWS_REGION" = "us-east-1"
test "$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)" = "473968112686"
STACK_SHA="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='SourceSha'].OutputValue | [0]" --output text)"
test "$STACK_SHA" = "$SHA"
BUCKET="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewBucketName'].OutputValue | [0]" --output text)"
DIST_ID="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewDistributionId'].OutputValue | [0]" --output text)"
test "$BUCKET" != "None" && test "$DIST_ID" != "None"
rm -f "$RUNTIME_TARGET"

# Withdraw only the failed release assets. Retain the verified reusable target
# so the configured origin remains stable for the bounded repair attempt.
aws s3 rm "s3://$BUCKET/" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION"
INVALIDATION_ID="$(aws cloudfront create-invalidation --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --id "$INVALIDATION_ID"
printf 'rollback=PASS\nsource_sha=%s\ninvalidation_id=%s\n' "$SHA" "$INVALIDATION_ID"
