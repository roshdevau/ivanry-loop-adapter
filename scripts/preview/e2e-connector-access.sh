#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
RUNTIME_SOURCE="$ROOT_DIR/e2e/.secrets/runtime.json"
RUNTIME_TARGET="$ROOT_DIR/e2e/.secrets/preview-runtime.json"
test "${AWS_PROFILE:-roshanpersonal}" = "roshanpersonal"
test "${AWS_REGION:-us-east-1}" = "us-east-1"
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
test -f "$RUNTIME_SOURCE"
node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));if(!r.email?.endsWith(".invalid")||r.desktopSession?.e2eSynthetic!==true)throw new Error("preview requires the reserved .invalid e2eSynthetic runtime")' "$RUNTIME_SOURCE"
ORIGIN="$(AWS_PROFILE="${AWS_PROFILE:-roshanpersonal}" AWS_REGION="${AWS_REGION:-us-east-1}" aws cloudformation describe-stacks --profile "${AWS_PROFILE:-roshanpersonal}" --region "${AWS_REGION:-us-east-1}" --stack-name PortfolioPreviewFrontendStack --query "Stacks[0].Outputs[?OutputKey=='PreviewOrigin'].OutputValue | [0]" --output text)"
test "$ORIGIN" != "None"
umask 077
cp "$RUNTIME_SOURCE" "$RUNTIME_TARGET"
(cd "$ROOT_DIR" && E2E_BASE_URL="$ORIGIN" E2E_RUNTIME_PATH="$RUNTIME_TARGET" npx playwright test --config="$ROOT_DIR/e2e/playwright.config.ts" "$ROOT_DIR/e2e/specs/connector-access-settings.spec.ts")
