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
node -e 'const fs=require("fs");const crypto=require("crypto");const [plan,sha,base,manifest]=process.argv.slice(1);const x=JSON.parse(fs.readFileSync(plan));if(x.candidateSha!==sha||x.baseSha!==base||JSON.stringify(x.lanes)!==JSON.stringify(["ivanry-frontend-static"])||x.releaseManifestSha256!==crypto.createHash("sha256").update(fs.readFileSync(manifest)).digest("hex"))throw new Error("production plan binding mismatch")' "$PLAN_PATH" "$SHA" "$LOOP_BASE_SHA" "$LOOP_RELEASE_MANIFEST"
mkdir -p "$BACKUP_ROOT"
if [[ ! -s "$BACKUP_ROOT/frontend-backup.json" ]]; then
  node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" capture "$BACKUP_ROOT/frontend-backup.json"
fi
node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" verify "$BACKUP_ROOT/frontend-backup.json"
bash "$PRODUCTION_ADAPTER_ROOT/scripts/production/deploy-frontend.sh"
