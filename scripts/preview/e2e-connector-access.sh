#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
RUNTIME="$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
test "${AWS_PROFILE:-ivanry-sandbox}" = 'ivanry-sandbox'
test "${AWS_REGION:-us-east-1}" = 'us-east-1'
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
trap 'rm -f "$RUNTIME"' EXIT
test -f "$RUNTIME"
node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));if(r.environment!=="sandbox"||r.baseUrl!=="https://preview.ivanry.com"||!r.email?.endsWith(".invalid")||r.e2eSynthetic!==true)throw new Error("sandbox runtime is invalid")' "$RUNTIME"
(cd "$ROOT_DIR" && E2E_BASE_URL='https://preview.ivanry.com' E2E_RUNTIME_PATH="$RUNTIME" npx playwright test --config="$ROOT_DIR/e2e/playwright.config.ts" "$ROOT_DIR/e2e/specs/connector-access-settings.spec.ts")
