#!/usr/bin/env bash

set -euo pipefail

PRODUCTION_ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PRODUCTION_ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
PRODUCTION_AWS_PROFILE="${AWS_PROFILE:-roshanpersonal}"
PRODUCTION_AWS_REGION="${AWS_REGION:-us-east-1}"
PRODUCTION_ACCOUNT_ID="473968112686"
PRODUCTION_STACK_NAME="PortfolioMgmtStack"
PRODUCTION_BUCKET="portfoliomgmtstack-datastackfrontendbucketdef42f2f-qtmcve9ayiga"
PRODUCTION_DISTRIBUTION_ID="E2XZ59I9T4UX70"
PRODUCTION_ORIGIN="https://finance.ivanry.com"
PRODUCTION_RESOURCE_ALLOWLIST='["PortfolioMgmtStack"]'
export PRODUCTION_ADAPTER_ROOT PRODUCTION_ROOT_DIR PRODUCTION_AWS_PROFILE PRODUCTION_AWS_REGION PRODUCTION_ACCOUNT_ID PRODUCTION_STACK_NAME PRODUCTION_BUCKET PRODUCTION_DISTRIBUTION_ID PRODUCTION_ORIGIN PRODUCTION_RESOURCE_ALLOWLIST

production_release_sha() {
  local resolved
  resolved="$(node "$PRODUCTION_ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
  test -n "${LOOP_RELEASE_SHA:-}"
  test "$LOOP_RELEASE_SHA" = "$resolved"
  test "$(git -C "$PRODUCTION_ROOT_DIR" rev-parse HEAD)" = "$resolved"
  printf '%s\n' "$resolved"
}

production_run_directory() {
  local resolved
  resolved="$(node "$PRODUCTION_ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --run-directory)"
  test -n "${LOOP_RUN_DIRECTORY:-}"
  test "$LOOP_RUN_DIRECTORY" = "$resolved"
  printf '%s\n' "$resolved"
}

production_require_contract() {
  test "$PRODUCTION_AWS_PROFILE" = "roshanpersonal"
  test "$PRODUCTION_AWS_REGION" = "us-east-1"
  test -z "${IVANRY_PREVIEW_ORIGIN:-}"
  test "${LOOP_DELIVERY_TARGET:-}" = "ivanry-production"
  test "${LOOP_RESOURCE_ALLOWLIST:-}" = "$PRODUCTION_RESOURCE_ALLOWLIST"
  test -n "${LOOP_RELEASE_MANIFEST:-}"
  test "$LOOP_RELEASE_MANIFEST" = "$(production_run_directory)/release/manifest.json"
  test -s "$LOOP_RELEASE_MANIFEST"
  test -z "$(git -C "$PRODUCTION_ROOT_DIR" status --porcelain=v1 --untracked-files=all)"
}

production_verify_aws_target() {
  local account stack_status stack_bucket stack_distribution distribution_json
  account="$(aws sts get-caller-identity --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --query Account --output text)"
  test "$account" = "$PRODUCTION_ACCOUNT_ID"
  stack_status="$(aws cloudformation describe-stacks --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --stack-name "$PRODUCTION_STACK_NAME" --query 'Stacks[0].StackStatus' --output text)"
  test "$stack_status" = "UPDATE_COMPLETE" || test "$stack_status" = "CREATE_COMPLETE"
  stack_bucket="$(aws cloudformation describe-stacks --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --stack-name "$PRODUCTION_STACK_NAME" --query "Stacks[0].Outputs[?contains(OutputKey, 'FrontendBucketName')].OutputValue | [0]" --output text)"
  stack_distribution="$(aws cloudformation describe-stacks --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --stack-name "$PRODUCTION_STACK_NAME" --query "Stacks[0].Outputs[?contains(OutputKey, 'DistributionId')].OutputValue | [0]" --output text)"
  test "$stack_bucket" = "$PRODUCTION_BUCKET"
  test "$stack_distribution" = "$PRODUCTION_DISTRIBUTION_ID"
  distribution_json="$(aws cloudfront get-distribution --profile "$PRODUCTION_AWS_PROFILE" --id "$PRODUCTION_DISTRIBUTION_ID" --output json)"
  node -e 'const value=JSON.parse(process.argv[1]).Distribution;const bucket=process.argv[2];if(value?.Status!=="Deployed"||value?.DistributionConfig?.Enabled!==true)throw new Error("production distribution is not deployed and enabled");if(!(value.DistributionConfig.Aliases?.Items??[]).includes("finance.ivanry.com"))throw new Error("production distribution alias mismatch");if(!(value.DistributionConfig.Origins?.Items??[]).some(x=>x.DomainName===`${bucket}.s3.us-east-1.amazonaws.com`))throw new Error("production bucket origin mismatch")' "$distribution_json" "$PRODUCTION_BUCKET"
  aws s3api get-public-access-block --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --bucket "$PRODUCTION_BUCKET" --output json \
    | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8")).PublicAccessBlockConfiguration;if(!x||Object.values(x).some(value=>value!==true))throw new Error("production bucket public-access block mismatch")'
  aws s3api get-bucket-encryption --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --bucket "$PRODUCTION_BUCKET" --output json \
    | node -e 'const fs=require("fs");const rules=JSON.parse(fs.readFileSync(0,"utf8")).ServerSideEncryptionConfiguration?.Rules??[];if(!rules.some(rule=>rule.ApplyServerSideEncryptionByDefault?.SSEAlgorithm==="aws:kms"))throw new Error("production bucket encryption mismatch")'
}

production_invalidate() {
  local invalidation_id
  invalidation_id="$(aws cloudfront create-invalidation --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --distribution-id "$PRODUCTION_DISTRIBUTION_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
  aws cloudfront wait invalidation-completed --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --distribution-id "$PRODUCTION_DISTRIBUTION_ID" --id "$invalidation_id"
  printf '%s\n' "$invalidation_id"
}

production_plan_path() {
  printf '%s\n' "$(production_run_directory)/release/production-plan.json"
}
