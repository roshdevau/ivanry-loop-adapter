#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

RUN_DIRECTORY="$(production_run_directory)"
BACKUP_ROOT="$RUN_DIRECTORY/release/production-backup"
if [[ ! -s "$BACKUP_ROOT/frontend-backup.json" || ! -s "$BACKUP_ROOT/frontend-candidate.json" ]]; then
  printf 'rollback=NOT_NEEDED\nreason=no-production-mutation-evidence\n'
  exit 0
fi
production_verify_aws_target
bash "$PRODUCTION_ADAPTER_ROOT/scripts/production/rollback-frontend.sh"
