#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

verify_local_contract
verify_aws_target
test -s "$REPAIR_STATE_DIR/template.json"
test -s "$REPAIR_STATE_DIR/parameters.json"

set +e
OUTPUT="$(aws cloudformation update-stack --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --template-body "file://$REPAIR_STATE_DIR/template.json" --parameters "file://$REPAIR_STATE_DIR/parameters.json" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM 2>&1)"
STATUS=$?
set -e
if [[ $STATUS -ne 0 ]]; then
  if [[ "$OUTPUT" != *'No updates are to be performed'* ]]; then
    printf '%s\n' "$OUTPUT" >&2
    exit "$STATUS"
  fi
else
  aws cloudformation wait stack-update-complete --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME"
fi
readonly STACK="$(stack_json)"
readonly STACK_STATUS="$(node -e 'const x=JSON.parse(process.argv[1]);process.stdout.write(x.StackStatus??"")' "$STACK")"
[[ "$STACK_STATUS" =~ ^(CREATE|UPDATE)_COMPLETE$ ]]
