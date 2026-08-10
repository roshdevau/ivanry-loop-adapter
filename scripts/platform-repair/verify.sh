#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

verify_local_contract
verify_aws_target
readonly OPERATION="${LOOP_REPAIR_OPERATION:?LOOP_REPAIR_OPERATION is required}"
readonly PRINCIPAL_ARN="${LOOP_REPAIR_PRINCIPAL_ARN:?LOOP_REPAIR_PRINCIPAL_ARN is required}"
readonly RESOURCE_ARN="${LOOP_REPAIR_RESOURCE_ARN:?LOOP_REPAIR_RESOURCE_ARN is required}"
[[ "$OPERATION" =~ ^(iam|kms):[A-Za-z][A-Za-z0-9]+$ ]] && [[ "$OPERATION" != *'*'* ]]
[[ "$PRINCIPAL_ARN" == arn:aws:iam::109837541383:role/* ]] && [[ "$PRINCIPAL_ARN" != *'*'* ]]
[[ "$RESOURCE_ARN" =~ ^arn:aws:(kms:us-east-1|iam:):109837541383:.+$ ]] && [[ "$RESOURCE_ARN" != *'*'* ]]

readonly STACK="$(stack_json)"
readonly STATUS="$(node -e 'const x=JSON.parse(process.argv[1]);process.stdout.write(x.StackStatus??"")' "$STACK")"
[[ "$STATUS" =~ ^(CREATE|UPDATE)_COMPLETE$ ]]

readonly SIMULATION="$(aws iam simulate-principal-policy --profile "$AWS_PROFILE" --region "$AWS_REGION" --policy-source-arn "$PRINCIPAL_ARN" --action-names "$OPERATION" --resource-arns "$RESOURCE_ARN" --output json)"
node -e 'const x=JSON.parse(process.argv[1]);if(x.EvaluationResults?.length!==1||x.EvaluationResults[0].EvalDecision!=="allowed")throw new Error("Exact denied operation is not allowed by the repaired principal policy")' "$SIMULATION"
printf '{"status":"PASS","environment":"sandbox","accountId":"%s","region":"%s","stackName":"%s","repairSha":"%s","operation":"%s","principalArn":"%s","resourceArn":"%s"}\n' "$AWS_ACCOUNT_ID" "$AWS_REGION" "$STACK_NAME" "$REPAIR_SHA" "$OPERATION" "$PRINCIPAL_ARN" "$RESOURCE_ARN"
