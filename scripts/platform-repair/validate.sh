#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

verify_local_contract
npm run build --workspace infrastructure
git -C "$REPAIR_ROOT" diff --check HEAD^ -- infrastructure/
(cd "$REPAIR_ROOT/infrastructure" && \
  CDK_ACCOUNT="$AWS_ACCOUNT_ID" CDK_REGION="$AWS_REGION" \
  SANDBOX_CERTIFICATE_ARN="arn:aws:acm:us-east-1:109837541383:certificate/00000000-0000-0000-0000-000000000000" \
  npx cdk --app "node $SANDBOX_APP" \
  synth "$STACK_NAME" --exclusively --quiet >/dev/null)
