#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SHA="$(production_release_sha)"
RUN_DIRECTORY="$(production_run_directory)"
DEPLOYMENT="$RUN_DIRECTORY/release/production-backup/frontend-deployment.json"
test -s "$DEPLOYMENT"

read -r ASSET_DIGEST MANIFEST_DIGEST < <(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(x.sourceSha!==process.argv[2]||x.status!=="PASS")throw new Error("frontend deployment evidence mismatch");process.stdout.write(`${x.assetSha256} ${x.releaseManifestSha256}\n`)' "$DEPLOYMENT" "$SHA")
curl --fail --silent --show-error "$PRODUCTION_ORIGIN/release.json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.sourceSha!==process.argv[1]||x.assetSha256!==process.argv[2]||x.releaseManifestSha256!==process.argv[3])throw new Error("production release smoke mismatch")' "$SHA" "$ASSET_DIGEST" "$MANIFEST_DIGEST"
curl --fail --silent --show-error "$PRODUCTION_ORIGIN/health.json" | node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(0,"utf8"));if(x.status!=="ok"||x.sourceSha!==process.argv[1]||x.assetSha256!==process.argv[2])throw new Error("production health smoke mismatch")' "$SHA" "$ASSET_DIGEST"
curl --fail --silent --show-error "$PRODUCTION_ORIGIN/runtime-config.js" | node -e 'const fs=require("fs");const x=fs.readFileSync(0,"utf8");if(x.includes("localhost")||x.includes("d2terd7fyqknvp.cloudfront.net")||!x.includes("finance.ivanry.com"))throw new Error("production runtime smoke mismatch")'
curl --fail --silent --show-error --output /dev/null "$PRODUCTION_ORIGIN/settings"
printf 'lane=ivanry-frontend-static\nsmoke=PASS\nsource_sha=%s\n' "$SHA"
