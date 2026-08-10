#!/usr/bin/env bash
set -euo pipefail

readonly REPAIR_ROOT="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
readonly ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:?IVANRY_LOOP_ADAPTER_ROOT is required}"
readonly RUN_DIRECTORY="${LOOP_RUN_DIRECTORY:?LOOP_RUN_DIRECTORY is required}"
readonly REPAIR_SHA="${LOOP_REPAIR_SHA:?LOOP_REPAIR_SHA is required}"
readonly PARENT_SHA="${LOOP_PARENT_SHA:?LOOP_PARENT_SHA is required}"
readonly AWS_PROFILE='ivanry-sandbox'
readonly AWS_REGION='us-east-1'
readonly AWS_ACCOUNT_ID='109837541383'
readonly STACK_NAME='IvanrySandboxCoreStack'
readonly REPAIR_STATE_DIR="$RUN_DIRECTORY/platform-repair/controller"
readonly SANDBOX_APP="$ADAPTER_ROOT/scripts/platform-repair/sandbox-app.cjs"

verify_local_contract() {
  test "$LOOP_DELIVERY_TARGET" = 'ivanry-sandbox'
  test "$LOOP_RESOURCE_ALLOWLIST" = '["IvanrySandboxCoreStack"]'
  test "$(git -C "$REPAIR_ROOT" rev-parse HEAD)" = "$REPAIR_SHA"
  test -z "$(git -C "$REPAIR_ROOT" status --porcelain=v1 --untracked-files=all)"
  test "$REPAIR_SHA" != "$PARENT_SHA"
  mkdir -p "$REPAIR_STATE_DIR"
  chmod 700 "$REPAIR_STATE_DIR"
}

verify_aws_target() {
  local account
  account="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)"
  test "$account" = "$AWS_ACCOUNT_ID"
}

stack_json() {
  aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query 'Stacks[0]' --output json
}

certificate_arn() {
  local distribution_id
  distribution_id="$(stack_json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const x=JSON.parse(s);const o=new Map((x.Outputs??[]).map(v=>[v.OutputKey,v.OutputValue]));process.stdout.write(o.get("DistributionId")??"")})')"
  aws cloudfront get-distribution --profile "$AWS_PROFILE" --id "$distribution_id" --query 'Distribution.DistributionConfig.ViewerCertificate.ACMCertificateArn' --output text
}
