#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-ivanry-sandbox}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="IvanrySandboxCoreStack"
EXPECTED_ACCOUNT="109837541383"
EXPECTED_HOST="preview.ivanry.com"
test "$AWS_PROFILE" = "ivanry-sandbox"
test "$AWS_REGION" = "us-east-1"
ACCOUNT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)"
test "$ACCOUNT" = "$EXPECTED_ACCOUNT"
STACK="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query 'Stacks[0]' --output json)"
read -r STATUS ENVIRONMENT HOST BUCKET DIST_ID API_URL < <(node -e 'const x=JSON.parse(process.argv[1]);const o=new Map((x.Outputs??[]).map(v=>[v.OutputKey,v.OutputValue]));process.stdout.write([x.StackStatus,o.get("Environment"),o.get("WebHost"),o.get("FrontendBucketName"),o.get("DistributionId"),o.get("ApiUrl")].join(" ")+"\n")' "$STACK")
[[ "$STATUS" =~ ^(CREATE|UPDATE)_COMPLETE$ ]]
test "$ENVIRONMENT" = "sandbox" && test "$HOST" = "$EXPECTED_HOST"
test "$BUCKET" != "None" && test "$DIST_ID" != "None" && [[ "$API_URL" == https://*.execute-api.us-east-1.amazonaws.com/v1/ ]]
test "$(aws s3api get-bucket-versioning --profile "$AWS_PROFILE" --region "$AWS_REGION" --bucket "$BUCKET" --query Status --output text)" = "Enabled"
CONFIG="$(aws cloudfront get-distribution --profile "$AWS_PROFILE" --region "$AWS_REGION" --id "$DIST_ID" --query Distribution --output json)"
node -e 'const d=JSON.parse(process.argv[1]);const c=d.DistributionConfig;const host=process.argv[2];const bucket=process.argv[3];if(d.Status!=="Deployed"||c.Enabled!==true||!(c.Aliases?.Items??[]).includes(host))throw new Error("sandbox distribution identity mismatch");const api=c.CacheBehaviors?.Items?.find(x=>x.PathPattern==="/api/*");if(!api)throw new Error("sandbox API behavior is missing");const assets=c.Origins.Items.find(x=>x.Id===c.DefaultCacheBehavior.TargetOriginId);if(!assets?.OriginAccessControlId||!assets.DomainName.startsWith(bucket+".s3."))throw new Error("sandbox assets are not in the approved private OAC bucket")' "$CONFIG" "$HOST" "$BUCKET"
printf '{"accountId":"%s","region":"%s","environment":"sandbox","host":"%s","stackName":"%s","bucketName":"%s","distributionId":"%s","origin":"https://%s","healthUrl":"https://%s/api/health","resourceAllowlist":["%s"]}\n' "$ACCOUNT" "$AWS_REGION" "$HOST" "$STACK_NAME" "$BUCKET" "$DIST_ID" "$HOST" "$HOST" "$STACK_NAME"
