#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
RUNTIME_TARGET="$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
RUN_DIRECTORY="${LOOP_RUN_DIRECTORY:?LOOP_RUN_DIRECTORY is required}"
trap 'rm -f "$RUNTIME_TARGET"' EXIT

# A successful connector E2E writes one audit under this exact run directory.
# A failed/deploy-stage preview can have no audit; cleanup still removes the
# private runtime without borrowing evidence from another run.
AUDIT_PATH="$RUN_DIRECTORY/preview-e2e/connector-access-request-audit.json"
if [[ -e "$AUDIT_PATH" ]]; then
  node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1]));if(x.kind!=="loop-preview-request-audit"||x.sourceSha!==process.argv[2])throw new Error("preview audit is not bound to this run SHA");if(!Array.isArray(x.observedRequests)||x.observedRequests.some(r=>!["GET","HEAD","OPTIONS"].includes(r.method)))throw new Error("preview made a non-read-only request");if(x.connectorConfigured&&(!x.beforeFingerprint||x.beforeFingerprint!==x.afterFingerprint))throw new Error("connector preferences changed during preview")' "$AUDIT_PATH" "$SHA"
fi
rm -f "$RUNTIME_TARGET"
test ! -e "$RUNTIME_TARGET"
printf 'cleanup=PASS\nsource_sha=%s\n' "$SHA"
