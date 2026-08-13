#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SHA="$(production_release_sha)"
RUN_DIRECTORY="$(production_run_directory)"
production_require_contract
production_verify_aws_target
PLAN_PATH="$(production_plan_path)"
BACKUP_ROOT="$RUN_DIRECTORY/release/production-backup"
test -s "$PLAN_PATH"
node -e 'const fs=require("fs");const crypto=require("crypto");const [plan,sha,base,manifest]=process.argv.slice(1);const x=JSON.parse(fs.readFileSync(plan));if(x.candidateSha!==sha||x.baseSha!==base||!Array.isArray(x.lanes)||!x.lanes.length||x.releaseManifestSha256!==crypto.createHash("sha256").update(fs.readFileSync(manifest)).digest("hex"))throw new Error("production plan binding mismatch")' "$PLAN_PATH" "$SHA" "$LOOP_BASE_SHA" "$LOOP_RELEASE_MANIFEST"
mkdir -p "$BACKUP_ROOT"
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-research-backend")?0:1)' "$PLAN_PATH"; then
  AWS_PROFILE="$PRODUCTION_AWS_PROFILE" AWS_REGION="$PRODUCTION_AWS_REGION" IVANRY_RELEASE_STACK="$PRODUCTION_STACK_NAME" IVANRY_RELEASE_ACCOUNT="$PRODUCTION_ACCOUNT_ID" node "$PRODUCTION_ADAPTER_ROOT/scripts/release/stack-snapshot.mjs" capture
  (cd "$PRODUCTION_ROOT_DIR/infrastructure" && AWS_PROFILE="$PRODUCTION_AWS_PROFILE" AWS_REGION="$PRODUCTION_AWS_REGION" CDK_ACCOUNT="$PRODUCTION_ACCOUNT_ID" CDK_REGION="$PRODUCTION_AWS_REGION" npx cdk --app 'npx ts-node --prefer-ts-exts bin/portfolio-mgmt.ts' deploy "$PRODUCTION_STACK_NAME" --exclusively --require-approval never)
fi
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-frontend-static")?0:1)' "$PLAN_PATH"; then
  if [[ ! -s "$BACKUP_ROOT/frontend-backup.json" ]]; then
    node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" capture "$BACKUP_ROOT/frontend-backup.json"
  fi
  node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" verify "$BACKUP_ROOT/frontend-backup.json"
  bash "$PRODUCTION_ADAPTER_ROOT/scripts/production/deploy-frontend.sh"
fi
printf 'production_release=PASS\nsource_sha=%s\n' "$SHA"
