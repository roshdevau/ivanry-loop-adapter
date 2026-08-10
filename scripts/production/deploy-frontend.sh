#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SHA="$(production_release_sha)"
RUN_DIRECTORY="$(production_run_directory)"
BACKUP_ROOT="$RUN_DIRECTORY/release/production-backup"
OUT_DIR="$PRODUCTION_ROOT_DIR/frontend/out"
MANIFEST_DIGEST="$(shasum -a 256 "$LOOP_RELEASE_MANIFEST" | awk '{print $1}')"
test -s "$BACKUP_ROOT/frontend-backup.json"

cd "$PRODUCTION_ROOT_DIR"
node scripts/generate-frontend-runtime-config.mjs
npm run build --workspace frontend
test -s "$OUT_DIR/runtime-config.js"
node -e 'const fs=require("fs");const raw=fs.readFileSync(process.argv[1],"utf8");const match=raw.match(/Object\.freeze\((\{[\s\S]*\})\);/);if(!match)throw new Error("production runtime configuration cannot be parsed");const x=JSON.parse(match[1]);if(x.appUrl!=="https://finance.ivanry.com"||x.mcpApiUrl!=="https://mcp.ivanry.com"||x.previewReadOnly===true||!/^https:\/\//.test(x.apiUrl)||raw.includes("d2terd7fyqknvp.cloudfront.net")||raw.includes("localhost"))throw new Error("production frontend runtime configuration is unsafe")' "$OUT_DIR/runtime-config.js"

ASSET_DIGEST="$(tar -C "$OUT_DIR" -cf - . | shasum -a 256 | awk '{print $1}')"
node -e 'const fs=require("fs");const [path,sha,asset,manifest]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({sourceSha:sha,assetSha256:asset,releaseManifestSha256:manifest},null,2)+"\n")' "$OUT_DIR/release.json" "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
node -e 'const fs=require("fs");const [path,sha,asset]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({status:"ok",sourceSha:sha,assetSha256:asset},null,2)+"\n")' "$OUT_DIR/health.json" "$SHA" "$ASSET_DIGEST"

node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" verify "$BACKUP_ROOT/frontend-backup.json"
node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" candidate "$BACKUP_ROOT/frontend-backup.json" "$BACKUP_ROOT/frontend-candidate.json" "$OUT_DIR"
aws s3 sync "$OUT_DIR" "s3://$PRODUCTION_BUCKET/" --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --exclude 'downloads/*' --delete --metadata "ivanry-release-sha=$SHA" --only-show-errors
for file in runtime-config.js release.json health.json; do
  aws s3 cp "$OUT_DIR/$file" "s3://$PRODUCTION_BUCKET/$file" --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --cache-control 'no-cache' --metadata "ivanry-release-sha=$SHA" --only-show-errors
done
for route in admin about circle connections dashboard downloads help insights intelligence insider-trading login mailroom mobile/oauth/callback mobile/logout/callback news outlook performance portfolio portfolios properties privacy reports research settings stocks terms updates; do
  test -s "$OUT_DIR/$route.html"
  aws s3 cp "$OUT_DIR/$route.html" "s3://$PRODUCTION_BUCKET/$route" --profile "$PRODUCTION_AWS_PROFILE" --region "$PRODUCTION_AWS_REGION" --content-type 'text/html' --cache-control 'no-cache' --metadata "ivanry-release-sha=$SHA" --only-show-errors
done

INVALIDATION_ID="$(production_invalidate)"
node -e 'const fs=require("fs");const [path,sha,asset,manifest,invalidation]=process.argv.slice(1);fs.writeFileSync(path,JSON.stringify({schemaVersion:1,sourceSha:sha,assetSha256:asset,releaseManifestSha256:manifest,invalidationId:invalidation,status:"PASS",deployedAt:new Date().toISOString()},null,2)+"\n",{mode:0o600})' "$BACKUP_ROOT/frontend-deployment.json" "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST" "$INVALIDATION_ID"
curl --fail --silent --show-error "$PRODUCTION_ORIGIN/release.json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.sourceSha!==process.argv[1]||x.assetSha256!==process.argv[2]||x.releaseManifestSha256!==process.argv[3])throw new Error("production release binding mismatch")' "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
printf 'lane=ivanry-frontend-static\ndeploy=PASS\nsource_sha=%s\n' "$SHA"
