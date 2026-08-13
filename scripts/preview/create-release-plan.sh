#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RUN_DIRECTORY="${LOOP_RUN_DIRECTORY:?LOOP_RUN_DIRECTORY is required}"
PLAN_PATH="$RUN_DIRECTORY/preview/release-plan.json"
mkdir -p "$(dirname "$PLAN_PATH")"
node "$ADAPTER_ROOT/scripts/release/create-plan.mjs" > "${PLAN_PATH}.tmp"
chmod 600 "${PLAN_PATH}.tmp"
mv "${PLAN_PATH}.tmp" "$PLAN_PATH"
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1]));if(!Array.isArray(x.lanes)||!x.lanes.length)throw new Error("preview plan has no lanes")' "$PLAN_PATH"
printf '%s\n' "$PLAN_PATH"
