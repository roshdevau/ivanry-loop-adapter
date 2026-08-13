#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
production_require_contract
production_verify_aws_target
PLAN_PATH="$(production_plan_path)"
test -s "$PLAN_PATH"
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-frontend-static")?0:1)' "$PLAN_PATH"; then
  bash "$PRODUCTION_ADAPTER_ROOT/scripts/production/smoke-frontend.sh"
fi
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-research-backend")?0:1)' "$PLAN_PATH"; then
  curl --fail --silent --show-error --output /dev/null "$PRODUCTION_ORIGIN/api/health"
  aws lambda get-function-configuration --function-name portfolio-portfolios-insights --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --query 'Environment.Variables' --output json | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.INSIGHTS_AGENTCORE_ENABLED!=="true"||!/^arn:aws:bedrock-agentcore:us-east-1:473968112686:runtime\//.test(x.AGENTCORE_INSIGHTS_RUNTIME_ARN??""))throw new Error("Production Quick Scan AgentCore binding is missing")'
fi
printf 'smoke=PASS\nsource_sha=%s\n' "$(production_release_sha)"
