#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
production_require_contract
production_verify_aws_target
bash "$PRODUCTION_ADAPTER_ROOT/scripts/production/smoke-frontend.sh"
