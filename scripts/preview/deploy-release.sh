#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
RUN_DIRECTORY="${LOOP_RUN_DIRECTORY:?LOOP_RUN_DIRECTORY is required}"
AWS_PROFILE="${AWS_PROFILE:-ivanry-sandbox}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME='IvanrySandboxCoreStack'
ACCOUNT='109837541383'
CERTIFICATE_ARN='arn:aws:acm:us-east-1:109837541383:certificate/ed25f6bf-39fb-44e6-8afc-6b4bd5257a63'
test "$AWS_PROFILE" = ivanry-sandbox && test "$AWS_REGION" = us-east-1
test "${LOOP_DELIVERY_TARGET:-}" = ivanry-sandbox
test "${LOOP_RESOURCE_ALLOWLIST:-}" = '["IvanrySandboxCoreStack"]'
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
PLAN_PATH="$(bash "$ADAPTER_ROOT/scripts/preview/create-release-plan.sh")"
node -e 'const fs=require("fs");const [path,sha,base]=process.argv.slice(1);const x=JSON.parse(fs.readFileSync(path));if(x.candidateSha!==sha||x.baseSha!==base)throw new Error("preview plan exact-SHA binding mismatch")' "$PLAN_PATH" "$LOOP_RELEASE_SHA" "$LOOP_BASE_SHA"

# Both E2E paths use only the reserved synthetic Sandbox tenant.  Preparing it
# here ensures a backend-only change never borrows a human or production user.
RUNTIME="$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
if [[ ! -f "$RUNTIME" ]]; then LOOP_ALLOW_SANDBOX_IDENTITY_WRITE=true node "$ADAPTER_ROOT/scripts/preview/provision-synthetic.mjs"; fi

if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-frontend-static")?0:1)' "$PLAN_PATH"; then
  bash "$ADAPTER_ROOT/scripts/preview/deploy-frontend.sh"
fi
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-research-backend")?0:1)' "$PLAN_PATH"; then
  AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" IVANRY_RELEASE_STACK="$STACK_NAME" IVANRY_RELEASE_ACCOUNT="$ACCOUNT" node "$ADAPTER_ROOT/scripts/release/stack-snapshot.mjs" capture
  (cd "$ROOT_DIR/infrastructure" && AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" CDK_ACCOUNT="$ACCOUNT" CDK_REGION="$AWS_REGION" SANDBOX_CERTIFICATE_ARN="$CERTIFICATE_ARN" npx cdk --app "node $ADAPTER_ROOT/scripts/platform-repair/sandbox-app.cjs" deploy "$STACK_NAME" --exclusively --require-approval never)
  bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
  aws lambda get-function-configuration --function-name portfolio-portfolios-insights --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'Environment.Variables' --output json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.INSIGHTS_AGENTCORE_ENABLED!=="true"||!/^arn:aws:bedrock-agentcore:us-east-1:109837541383:runtime\//.test(x.AGENTCORE_INSIGHTS_RUNTIME_ARN??""))throw new Error("Sandbox Quick Scan AgentCore binding is missing")'
fi
printf 'preview_release=PASS\nsource_sha=%s\nplan=%s\n' "$LOOP_RELEASE_SHA" "$PLAN_PATH"
