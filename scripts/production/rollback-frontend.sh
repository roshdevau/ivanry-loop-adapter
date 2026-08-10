#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SHA="$(production_release_sha)"
RUN_DIRECTORY="$(production_run_directory)"
BACKUP_ROOT="$RUN_DIRECTORY/release/production-backup"
test -s "$BACKUP_ROOT/frontend-backup.json"
test -s "$BACKUP_ROOT/frontend-candidate.json"
node "$PRODUCTION_ADAPTER_ROOT/scripts/production/frontend-backup.mjs" restore "$BACKUP_ROOT/frontend-backup.json" "$BACKUP_ROOT/frontend-candidate.json"
INVALIDATION_ID="$(production_invalidate)"
curl --fail --silent --show-error --output /dev/null "$PRODUCTION_ORIGIN/index.html"
printf 'lane=ivanry-frontend-static\nrollback=PASS\nsource_sha=%s\ninvalidation_id=%s\n' "$SHA" "$INVALIDATION_ID"
