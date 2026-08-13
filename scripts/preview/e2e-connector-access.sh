#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
RUN_DIRECTORY="${LOOP_RUN_DIRECTORY:?LOOP_RUN_DIRECTORY is required}"
RUNTIME="$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
EVIDENCE_DIRECTORY="$RUN_DIRECTORY/preview-e2e"
MARKER="$EVIDENCE_DIRECTORY/started.marker"
PLAN_PATH="$RUN_DIRECTORY/preview/release-plan.json"
test "${AWS_PROFILE:-ivanry-sandbox}" = 'ivanry-sandbox'
test "${AWS_REGION:-us-east-1}" = 'us-east-1'
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
trap 'rm -f "$RUNTIME"' EXIT
test -f "$RUNTIME"
test -s "$PLAN_PATH"
node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));if(r.environment!=="sandbox"||r.baseUrl!=="https://preview.ivanry.com"||!r.email?.endsWith(".invalid")||r.e2eSynthetic!==true)throw new Error("sandbox runtime is invalid")' "$RUNTIME"
mkdir -p "$EVIDENCE_DIRECTORY"
chmod 700 "$EVIDENCE_DIRECTORY"
: > "$MARKER"
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-frontend-static")?0:1)' "$PLAN_PATH"; then
  (cd "$ROOT_DIR" && E2E_BASE_URL='https://preview.ivanry.com' E2E_RUNTIME_PATH="$RUNTIME" npx playwright test --config="$ROOT_DIR/e2e/playwright.config.ts" "$ROOT_DIR/e2e/specs/connector-access-settings.spec.ts")
  AUDIT_PATHS="$(find "$ROOT_DIR/e2e/artifacts/playwright" -name connector-access-request-audit.json -type f -newer "$MARKER" -print)"
  test -n "$AUDIT_PATHS"
  test "$(printf '%s\n' "$AUDIT_PATHS" | wc -l | tr -d ' ')" -eq 1
  node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));x.sourceSha=process.argv[3];x.kind="loop-preview-request-audit";fs.writeFileSync(process.argv[2],JSON.stringify(x,null,2)+"\n",{mode:0o600})' "$AUDIT_PATHS" "$EVIDENCE_DIRECTORY/connector-access-request-audit.json" "$SHA"
fi
if node -e 'const x=require(process.argv[1]);process.exit(x.lanes.includes("ivanry-research-backend")?0:1)' "$PLAN_PATH"; then
  test -f "$ROOT_DIR/e2e/specs/sandbox-quick-scan-export.spec.ts"
  (cd "$ROOT_DIR" && E2E_BASE_URL='https://preview.ivanry.com' E2E_RUNTIME_PATH="$RUNTIME" LOOP_RELEASE_SHA="$SHA" npx playwright test --config="$ROOT_DIR/e2e/playwright.config.ts" "$ROOT_DIR/e2e/specs/sandbox-quick-scan-export.spec.ts")
fi
