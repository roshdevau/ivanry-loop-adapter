#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

verify_local_contract
verify_aws_target

aws cloudformation get-template --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --template-stage Processed --output json > "$REPAIR_STATE_DIR/template-response.json"
node -e 'const fs=require("fs");const input=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const body=typeof input.TemplateBody==="string"?input.TemplateBody:JSON.stringify(input.TemplateBody,null,2);fs.writeFileSync(process.argv[2],body+"\n",{mode:0o600})' "$REPAIR_STATE_DIR/template-response.json" "$REPAIR_STATE_DIR/template.json"
stack_json > "$REPAIR_STATE_DIR/stack-before.json"
node -e 'const fs=require("fs");const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const p=(s.Parameters??[]).map(x=>{if(!x.ParameterKey||x.ParameterValue==="****")throw new Error("Cannot capture an exact rollback parameter");return {ParameterKey:x.ParameterKey,ParameterValue:x.ParameterValue}});fs.writeFileSync(process.argv[2],JSON.stringify(p,null,2)+"\n",{mode:0o600})' "$REPAIR_STATE_DIR/stack-before.json" "$REPAIR_STATE_DIR/parameters.json"

readonly CERTIFICATE_ARN="$(certificate_arn)"
[[ "$CERTIFICATE_ARN" =~ ^arn:aws:acm:us-east-1:109837541383:certificate/[a-f0-9-]+$ ]]

(cd "$REPAIR_ROOT/infrastructure" && \
  AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" \
  CDK_ACCOUNT="$AWS_ACCOUNT_ID" CDK_REGION="$AWS_REGION" \
  SANDBOX_CERTIFICATE_ARN="$CERTIFICATE_ARN" \
  npx cdk --app "node $SANDBOX_APP" \
  deploy "$STACK_NAME" --exclusively --require-approval never)

stack_json > "$REPAIR_STATE_DIR/stack-after.json"
