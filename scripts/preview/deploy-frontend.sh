#!/usr/bin/env bash
set -euo pipefail

ADAPTER_ROOT="${IVANRY_LOOP_ADAPTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT_DIR="${LOOP_PROJECT_ROOT:?LOOP_PROJECT_ROOT is required}"
AWS_PROFILE="${AWS_PROFILE:-roshanpersonal}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="PortfolioPreviewFrontendStack"
SHA="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --sha)"
RUNTIME_SOURCE="$ROOT_DIR/e2e/.secrets/runtime.json"
test "$AWS_PROFILE" = "roshanpersonal"
test "$AWS_REGION" = "us-east-1"
test "$(git -C "$ROOT_DIR" rev-parse HEAD)" = "$SHA"
test -z "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)"
test -f "$RUNTIME_SOURCE"
node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));if(!r.email?.endsWith(".invalid")||r.desktopSession?.e2eSynthetic!==true)throw new Error("preview requires the reserved .invalid e2eSynthetic runtime before deployment")' "$RUNTIME_SOURCE"
test "$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)" = "473968112686"

(cd "$ADAPTER_ROOT/infrastructure" && AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" CDK_DEFAULT_REGION="$AWS_REGION" IVANRY_PREVIEW_SHA="$SHA" npx cdk --app 'npx ts-node --prefer-ts-exts bin/preview-frontend.ts' deploy "$STACK_NAME" --exclusively --require-approval never)
ORIGIN="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewOrigin'].OutputValue | [0]" --output text)"
BUCKET="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewBucketName'].OutputValue | [0]" --output text)"
DIST_ID="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='PreviewDistributionId'].OutputValue | [0]" --output text)"
test "$ORIGIN" != "None" && test "$BUCKET" != "None" && test "$DIST_ID" != "None"
bash "$ADAPTER_ROOT/scripts/preview/verify-target.sh" >/dev/null

(cd "$ROOT_DIR" && AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" node scripts/generate-frontend-runtime-config.mjs)
node "$ADAPTER_ROOT/scripts/preview/configure-runtime.mjs" "$ORIGIN" >/dev/null
(cd "$ROOT_DIR" && npm run build --workspace frontend)
test -s "$ROOT_DIR/frontend/out/runtime-config.js"
grep -Fq "${ORIGIN}/api" "$ROOT_DIR/frontend/out/runtime-config.js"
MANIFEST_PATH="$(node "$ADAPTER_ROOT/scripts/preview/resolve-release.mjs" --path)"
MANIFEST_DIGEST="$(shasum -a 256 "$MANIFEST_PATH" | awk '{print $1}')"
ASSET_DIGEST="$(tar -C "$ROOT_DIR/frontend/out" -cf - . | shasum -a 256 | awk '{print $1}')"
node -e 'const fs=require("fs");const [path,sha,asset,manifest]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({sourceSha:sha,assetSha256:asset,releaseManifestSha256:manifest},null,2)+"\n")' "$ROOT_DIR/frontend/out/release.json" "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
node -e 'const fs=require("fs");const [path,sha,asset]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({status:"ok",sourceSha:sha,assetSha256:asset},null,2)+"\n")' "$ROOT_DIR/frontend/out/health.json" "$SHA" "$ASSET_DIGEST"
aws s3 sync "$ROOT_DIR/frontend/out" "s3://$BUCKET/" --profile "$AWS_PROFILE" --region "$AWS_REGION" --delete
INVALIDATION_ID="$(aws cloudfront create-invalidation --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --profile "$AWS_PROFILE" --region "$AWS_REGION" --distribution-id "$DIST_ID" --id "$INVALIDATION_ID"
mkdir -p "$ROOT_DIR/.loop/preview-artifacts"
printf '%s\n' "$ASSET_DIGEST" > "$ROOT_DIR/.loop/preview-artifacts/${SHA}.frontend.sha256"
curl --fail --silent --show-error "$ORIGIN/release.json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.sourceSha!==process.argv[1]||x.assetSha256!==process.argv[2]||x.releaseManifestSha256!==process.argv[3])throw new Error("preview release binding mismatch")' "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
curl --fail --silent --show-error "$ORIGIN/health.json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.status!=="ok"||x.sourceSha!==process.argv[1]||x.assetSha256!==process.argv[2])throw new Error("preview health binding mismatch")' "$SHA" "$ASSET_DIGEST"
printf 'preview_origin=%s\nsource_sha=%s\ninvalidation_id=%s\n' "$ORIGIN" "$SHA" "$INVALIDATION_ID"
