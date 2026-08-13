#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

RUN_DIRECTORY="$(production_run_directory)"
BACKUP_ROOT="$RUN_DIRECTORY/release/production-backup"
PLAN_PATH="$(production_plan_path)"
production_require_contract
production_verify_aws_target
if [[ -s "$PLAN_PATH" ]] && node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-research-backend")?0:1)' "$PLAN_PATH"; then
  AWS_PROFILE="$PRODUCTION_AWS_PROFILE" AWS_REGION="$PRODUCTION_AWS_REGION" IVANRY_RELEASE_STACK="$PRODUCTION_STACK_NAME" IVANRY_RELEASE_ACCOUNT="$PRODUCTION_ACCOUNT_ID" node "$PRODUCTION_ADAPTER_ROOT/scripts/release/stack-snapshot.mjs" restore
fi
if [[ -s "$BACKUP_ROOT/frontend-backup.json" && -s "$BACKUP_ROOT/frontend-candidate.json" ]]; then
  bash "$PRODUCTION_ADAPTER_ROOT/scripts/production/rollback-frontend.sh"
fi
printf 'rollback=PASS\nsource_sha=%s\n' "$(production_release_sha)"
