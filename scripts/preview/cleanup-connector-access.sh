#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
RUNTIME_TARGET="$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
trap 'rm -f "$RUNTIME_TARGET"' EXIT

# The focused journey is GET-only. Preserve durable test evidence and remove
# only the private credential copy created by the preview E2E command.
AUDIT_PATH="$(find "$ROOT_DIR/e2e/artifacts/playwright" -name connector-access-request-audit.json -type f -print | sort | tail -n 1)"
test -n "$AUDIT_PATH"
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1]));if(!Array.isArray(x.observedRequests)||x.observedRequests.some(r=>!["GET","HEAD","OPTIONS"].includes(r.method)))throw new Error("preview made a non-read-only request");if(x.connectorConfigured&&(!x.beforeFingerprint||x.beforeFingerprint!==x.afterFingerprint))throw new Error("connector preferences changed during preview")' "$AUDIT_PATH"
rm -f "$RUNTIME_TARGET"
test ! -e "$RUNTIME_TARGET"
printf 'cleanup=PASS\nsource_sha=%s\n' "$SHA"
