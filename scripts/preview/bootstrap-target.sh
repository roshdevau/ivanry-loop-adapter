#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
AWS_PROFILE="${AWS_PROFILE:-roshanpersonal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="PortfolioPreviewFrontendStack"
SEED_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"

test "$AWS_PROFILE" = "roshanpersonal"
test "$AWS_REGION" = "us-east-1"
test "$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)" = "473968112686"
test -z "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)"

# Bootstrap only the reusable frontend target so its generated CloudFront
# origin can be bound into the external adapter config. No application assets are uploaded.
(cd "$ADAPTER_ROOT/infrastructure" && AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" CDK_ACCOUNT="473968112686" CDK_REGION="$AWS_REGION" IVANRY_PREVIEW_CORE_API_URL="https://y2a0146ujh.execute-api.us-east-1.amazonaws.com/v1" IVANRY_PREVIEW_SHA="$SEED_SHA" npx cdk --app 'npx ts-node --prefer-ts-exts bin/preview-frontend.ts' deploy "$STACK_NAME" --exclusively --require-approval never)

bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh"
