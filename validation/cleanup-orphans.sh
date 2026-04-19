#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Clean up orphaned resources from prior `run.sh` runs.
#
# Every resource the validator creates starts with "labval-" (S3, DynamoDB,
# Lambda, IAM, API Gateway, Cognito, CloudFormation, logs). This script
# finds and deletes any that are still present — useful if a previous run.sh
# was interrupted before its trap cleanup completed.
#
# Usage:
#   ./cleanup-orphans.sh             # dry run: list what would be deleted
#   ./cleanup-orphans.sh --delete    # actually delete
# -----------------------------------------------------------------------------
set -u

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

MODE="dry-run"
for arg in "$@"; do
  case "$arg" in
    --delete) MODE="delete" ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  esac
done

FOUND=0; DELETED=0; ERR=0

info() { printf "  • %s\n" "$1"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; DELETED=$((DELETED+1)); }
nope() { printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"; ERR=$((ERR+1)); }
step() { echo; printf "\033[1m── %s ──\033[0m\n" "$1"; }

do_delete() { [ "$MODE" = "delete" ]; }

# ----- CloudFormation stacks (SAM) -----
step "CloudFormation stacks: sam-labval-*"
STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'sam-labval-')].StackName" \
  --output text 2>/dev/null)
for S in $STACKS; do
  FOUND=$((FOUND+1))
  info "stack $S"
  if do_delete; then
    aws cloudformation delete-stack --stack-name "$S" >/dev/null 2>&1 \
      && ok "delete-stack $S (async; may take ~1 min)" \
      || nope "delete-stack $S" "non-zero"
  fi
done

# ----- Cognito user pools -----
step "Cognito user pools: labval-*"
POOLS=$(aws cognito-idp list-user-pools --max-results 60 \
  --query "UserPools[?starts_with(Name, 'labval-')].Id" --output text 2>/dev/null)
for P in $POOLS; do
  FOUND=$((FOUND+1))
  info "user pool $P"
  if do_delete; then
    aws cognito-idp delete-user-pool --user-pool-id "$P" >/dev/null 2>&1 \
      && ok "delete-user-pool $P" \
      || nope "delete-user-pool $P" "non-zero"
  fi
done

# ----- API Gateway REST APIs -----
step "API Gateway REST APIs: labval-*"
APIS=$(aws apigateway get-rest-apis \
  --query "items[?starts_with(name, 'labval-')].id" --output text 2>/dev/null)
for A in $APIS; do
  FOUND=$((FOUND+1))
  info "rest-api $A"
  if do_delete; then
    aws apigateway delete-rest-api --rest-api-id "$A" >/dev/null 2>&1 \
      && ok "delete-rest-api $A" \
      || nope "delete-rest-api $A" "non-zero"
  fi
done

# ----- Lambda functions -----
step "Lambda functions: lab4-labval-*"
FNS=$(aws lambda list-functions \
  --query "Functions[?starts_with(FunctionName, 'lab4-labval-')].FunctionName" \
  --output text 2>/dev/null)
for F in $FNS; do
  FOUND=$((FOUND+1))
  info "function $F"
  if do_delete; then
    aws lambda delete-function --function-name "$F" >/dev/null 2>&1 \
      && ok "delete-function $F" \
      || nope "delete-function $F" "non-zero"
  fi
done

# ----- IAM roles (StudentLambdaRole-labval-*) -----
step "IAM roles: StudentLambdaRole-labval-*"
ROLES=$(aws iam list-roles \
  --query "Roles[?starts_with(RoleName, 'StudentLambdaRole-labval-')].RoleName" \
  --output text 2>/dev/null)
for R in $ROLES; do
  FOUND=$((FOUND+1))
  info "role $R"
  if do_delete; then
    # Remove all inline policies
    for P in $(aws iam list-role-policies --role-name "$R" \
               --query "PolicyNames" --output text 2>/dev/null); do
      aws iam delete-role-policy --role-name "$R" --policy-name "$P" >/dev/null 2>&1 || true
    done
    # Detach all managed policies
    for PARN in $(aws iam list-attached-role-policies --role-name "$R" \
                  --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null); do
      aws iam detach-role-policy --role-name "$R" --policy-arn "$PARN" >/dev/null 2>&1 || true
    done
    aws iam delete-role --role-name "$R" >/dev/null 2>&1 \
      && ok "delete-role $R" \
      || nope "delete-role $R" "non-zero"
  fi
done

# ----- DynamoDB tables -----
step "DynamoDB tables: Items-labval-*"
TABLES=$(aws dynamodb list-tables \
  --query "TableNames[?starts_with(@, 'Items-labval-')]" --output text 2>/dev/null)
for T in $TABLES; do
  FOUND=$((FOUND+1))
  info "table $T"
  if do_delete; then
    aws dynamodb delete-table --table-name "$T" >/dev/null 2>&1 \
      && ok "delete-table $T" \
      || nope "delete-table $T" "non-zero"
  fi
done

# ----- S3 buckets -----
step "S3 buckets: labval-*"
empty_versioned_bucket() {
  local B="$1"
  aws s3api list-object-versions --bucket "$B" --output json 2>/dev/null \
    | python3 -c '
import json, sys, subprocess
data = json.load(sys.stdin)
items = (data.get("Versions") or []) + (data.get("DeleteMarkers") or [])
for i in range(0, len(items), 1000):
    batch = items[i:i+1000]
    payload = {"Objects":[{"Key":x["Key"],"VersionId":x["VersionId"]} for x in batch],
               "Quiet":True}
    subprocess.run(["aws","s3api","delete-objects","--bucket",sys.argv[1],
                    "--delete",json.dumps(payload)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
' "$B" 2>/dev/null || true
  aws s3 rb "s3://$B" --force >/dev/null 2>&1
}
BUCKETS=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'labval-')].Name" --output text 2>/dev/null)
for B in $BUCKETS; do
  FOUND=$((FOUND+1))
  info "bucket $B"
  if do_delete; then
    empty_versioned_bucket "$B"
    if aws s3api head-bucket --bucket "$B" >/dev/null 2>&1; then
      nope "s3 rb $B" "still present after empty"
    else
      ok "s3 rb $B (versions + delete markers cleared)"
    fi
  fi
done

# ----- CloudWatch log groups -----
step "CloudWatch log groups: /aws/lambda/lab4-labval-*, /aws/apigateway/labval-*"
for PFX in "/aws/lambda/lab4-labval-" "/aws/apigateway/labval-"; do
  GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "$PFX" \
    --query "logGroups[].logGroupName" --output text 2>/dev/null)
  for G in $GROUPS; do
    FOUND=$((FOUND+1))
    info "log-group $G"
    if do_delete; then
      aws logs delete-log-group --log-group-name "$G" >/dev/null 2>&1 \
        && ok "delete-log-group $G" \
        || nope "delete-log-group $G" "non-zero"
    fi
  done
done

echo
if [ "$MODE" = "dry-run" ]; then
  printf "\033[1mDry run — %d resources match 'labval-*'. Re-run with --delete to remove.\033[0m\n" "$FOUND"
  exit 0
else
  printf "\033[1mFOUND %d · DELETED %d · ERRORS %d\033[0m\n" "$FOUND" "$DELETED" "$ERR"
  [ $ERR -gt 0 ] && exit 1 || exit 0
fi
