#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
AWS_PROFILE="${AWS_PROFILE:-ivanry-sandbox}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME='IvanrySandboxCoreStack'
ORIGIN='https://preview.ivanry.com'
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
test "$AWS_PROFILE" = 'ivanry-sandbox' && test "$AWS_REGION" = 'us-east-1'
test "$(git -C "$ROOT_DIR" rev-parse HEAD)" = "$SHA"
test -z "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)"
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null
RUNTIME="$ROOT_DIR/e2e/.secrets/sandbox-preview-runtime.json"
if [[ ! -f "$RUNTIME" ]]; then
  LOOP_ALLOW_SANDBOX_IDENTITY_WRITE=true node "$ADAPTER_ROOT/scripts/preview/provision-synthetic.mjs"
fi
node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));if(r.environment!=="sandbox"||r.baseUrl!=="https://preview.ivanry.com"||!r.email?.endsWith(".invalid")||r.e2eSynthetic!==true)throw new Error("sandbox runtime is invalid")' "$RUNTIME"
BUCKET="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='FrontendBucketName'].OutputValue | [0]" --output text)"
DIST_ID="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue | [0]" --output text)"
test "$BUCKET" != 'None' && test "$DIST_ID" != 'None'

node "$ADAPTER_ROOT/scripts/preview/frontend-snapshot.mjs" capture
node "$ADAPTER_ROOT/scripts/preview/configure-sandbox-runtime.mjs" >/dev/null
(cd "$ROOT_DIR" && npm run build --workspace frontend)
OUT_DIR="$ROOT_DIR/frontend/out"
test -s "$OUT_DIR/runtime-config.js"
node -e 'const fs=require("fs");const raw=fs.readFileSync(process.argv[1],"utf8");if(!raw.includes("preview.ivanry.com")||!raw.includes("environment\": \"sandbox")||raw.includes("finance.ivanry.com")||raw.includes("mcpApiUrl"))throw new Error("sandbox runtime binding mismatch")' "$OUT_DIR/runtime-config.js"
MANIFEST_PATH="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --path)"
MANIFEST_DIGEST="$(shasum -a 256 "$MANIFEST_PATH" | awk '{print $1}')"
ASSET_DIGEST="$(tar -C "$OUT_DIR" -cf - . | shasum -a 256 | awk '{print $1}')"
node -e 'const fs=require("fs");const [path,sha,asset,manifest]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({sourceSha:sha,assetSha256:asset,releaseManifestSha256:manifest},null,2)+"\n")' "$OUT_DIR/release.json" "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
node -e 'const fs=require("fs");const [path,sha,asset]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({status:"ok",sourceSha:sha,assetSha256:asset,environment:"sandbox"},null,2)+"\n")' "$OUT_DIR/health.json" "$SHA" "$ASSET_DIGEST"
aws s3 sync "$OUT_DIR" "s3://$BUCKET/" --profile "$AWS_PROFILE" --region "$AWS_REGION" --delete
INVALIDATION_ID="$(aws cloudfront create-invalidation --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --id "$INVALIDATION_ID"
curl --fail --silent --show-error "$ORIGIN/api/health" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x?.success!==true||x?.data?.environment!=="sandbox")throw new Error("sandbox API health mismatch")'
curl --fail --silent --show-error "$ORIGIN/release.json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.sourceSha!==process.argv[1]||x.assetSha256!==process.argv[2]||x.releaseManifestSha256!==process.argv[3])throw new Error("sandbox release binding mismatch")' "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
printf 'preview_origin=%s\nsource_sha=%s\ninvalidation_id=%s\n' "$ORIGIN" "$SHA" "$INVALIDATION_ID"
