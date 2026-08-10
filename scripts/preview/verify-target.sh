#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
AWS_PROFILE="${AWS_PROFILE:-roshanpersonal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="PortfolioPreviewFrontendStack"
EXPECTED_ACCOUNT="473968112686"
EXPECTED_API_HOST="y2a0146ujh.execute-api.us-east-1.amazonaws.com"
EXPECTED_CONNECTOR_HOST="mcp.ivanry.com"
test "$AWS_PROFILE" = "roshanpersonal"
test "$AWS_REGION" = "us-east-1"
ACCOUNT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)"
test "$ACCOUNT" = "$EXPECTED_ACCOUNT"
STACK_SHA="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='SourceSha'].OutputValue | [0]" --output text)"
[[ "$STACK_SHA" =~ ^[a-f0-9]{40,64}$ ]]
BUCKET="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewBucketName'].OutputValue | [0]" --output text)"
DIST_ID="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewDistributionId'].OutputValue | [0]" --output text)"
ORIGIN="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewOrigin'].OutputValue | [0]" --output text)"
test "$BUCKET" != "None" && test "$DIST_ID" != "None" && test "$ORIGIN" != "None"
CONFIG="$(aws cloudfront get-distribution-config --profile "$AWS_PROFILE" --region "$AWS_REGION" --id "$DIST_ID" --query DistributionConfig --output json)"
node -e 'const c=JSON.parse(process.argv[1]);const coreHost=process.argv[2];const connectorHost=process.argv[3];const bucket=process.argv[4];const readOnly=x=>[...(x?.AllowedMethods?.Items??[])].sort().join(",")==="GET,HEAD,OPTIONS";const apiBehavior=c.CacheBehaviors?.Items?.find(x=>x.PathPattern==="/api/*");const connectorBehavior=c.CacheBehaviors?.Items?.find(x=>x.PathPattern==="/connector/*");if(!readOnly(c.DefaultCacheBehavior)||!readOnly(apiBehavior)||!readOnly(connectorBehavior))throw new Error("preview behaviors are not GET/HEAD/OPTIONS-only");const api=c.Origins.Items.find(x=>x.Id===apiBehavior.TargetOriginId);if(!api||api.DomainName!==coreHost||api.OriginPath!=="/v1")throw new Error("preview API origin is not the approved core API");const connector=c.Origins.Items.find(x=>x.Id===connectorBehavior.TargetOriginId);if(!connector||connector.DomainName!==connectorHost||connector.OriginPath)throw new Error("preview connector origin is not approved");const assets=c.Origins.Items.find(x=>x.Id===c.DefaultCacheBehavior.TargetOriginId);if(!assets?.OriginAccessControlId||!assets.DomainName.startsWith(bucket+".s3."))throw new Error("preview assets are not in the approved private OAC bucket");if(c.Aliases?.Quantity)throw new Error("preview must not claim a customer DNS alias")' "$CONFIG" "$EXPECTED_API_HOST" "$EXPECTED_CONNECTOR_HOST" "$BUCKET"
HOST="${ORIGIN#https://}"
printf '{"accountId":"%s","region":"%s","environment":"preview","host":"%s","sourceSha":"%s","stackName":"%s","bucketName":"%s","distributionId":"%s","origin":"%s","resourceAllowlist":["%s"]}\n' "$ACCOUNT" "$AWS_REGION" "$HOST" "$STACK_SHA" "$STACK_NAME" "$BUCKET" "$DIST_ID" "$ORIGIN" "$STACK_NAME"
