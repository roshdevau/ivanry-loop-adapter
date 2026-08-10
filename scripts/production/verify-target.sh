#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SHA="$(production_release_sha)"
RUN_DIRECTORY="$(production_run_directory)"
production_require_contract
production_verify_aws_target

PLAN_PATH="$(production_plan_path)"
PLAN_TEMPORARY="${PLAN_PATH}.tmp-$$"
mkdir -p "$(dirname "$PLAN_PATH")"
node "$PRODUCTION_ADAPTER_ROOT/scripts/production/release-plan.mjs" > "$PLAN_TEMPORARY"
chmod 600 "$PLAN_TEMPORARY"
mv "$PLAN_TEMPORARY" "$PLAN_PATH"
node -e 'const fs=require("fs");const [path,sha,base,manifest]=process.argv.slice(1);const x=JSON.parse(fs.readFileSync(path,"utf8"));if(x.candidateSha!==sha||x.baseSha!==base||x.releaseManifestSha256!==require("crypto").createHash("sha256").update(fs.readFileSync(manifest)).digest("hex"))throw new Error("production plan binding mismatch")' "$PLAN_PATH" "$SHA" "$LOOP_BASE_SHA" "$LOOP_RELEASE_MANIFEST"

node -e '
const [accountId, region, stackName, bucketName, distributionId, host, sha] = process.argv.slice(1);
process.stdout.write(`${JSON.stringify({
  accountId,
  region,
  stackName,
  bucketName,
  distributionId,
  host,
  environment: "production",
  resourceAllowlist: ["ivanry-frontend-static"],
  sourceSha: sha
})}\n`);
' "$PRODUCTION_ACCOUNT_ID" "$PRODUCTION_AWS_REGION" "$PRODUCTION_STACK_NAME" "$PRODUCTION_BUCKET" "$PRODUCTION_DISTRIBUTION_ID" "finance.ivanry.com" "$SHA"
