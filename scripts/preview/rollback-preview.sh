#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
AWS_PROFILE="${AWS_PROFILE:-ivanry-sandbox}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME='IvanrySandboxCoreStack'
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
test "$AWS_PROFILE" = 'ivanry-sandbox' && test "$AWS_REGION" = 'us-east-1'
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
DIST_ID="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue | [0]" --output text)"
test "$DIST_ID" != 'None'
SNAPSHOT="${LOOP_RUN_DIRECTORY:?LOOP_RUN_DIRECTORY is required}/preview/sandbox-frontend-before.json"
PLAN_PATH="${LOOP_RUN_DIRECTORY}/preview/release-plan.json"
if [[ -s "$PLAN_PATH" ]] && node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-research-backend")?0:1)' "$PLAN_PATH"; then
  AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" IVANRY_RELEASE_STACK="$STACK_NAME" IVANRY_RELEASE_ACCOUNT='109837541383' node "$ADAPTER_ROOT/scripts/release/stack-snapshot.mjs" restore
fi
if [[ -f "$SNAPSHOT" ]]; then
  node "$ADAPTER_ROOT/scripts/preview/frontend-snapshot.mjs" restore
else
  printf 'rollback=NO_FRONTEND_WRITE\nsource_sha=%s\n' "$SHA"
fi
INVALIDATION_ID="$(aws cloudfront create-invalidation --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --id "$INVALIDATION_ID"
rm -f "$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
curl --fail --silent --show-error 'https://preview.ivanry.com/api/health' | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x?.success!==true||x?.data?.environment!=="sandbox")throw new Error("sandbox rollback health mismatch")'
printf 'rollback=PASS\nsource_sha=%s\ninvalidation_id=%s\n' "$SHA" "$INVALIDATION_ID"
