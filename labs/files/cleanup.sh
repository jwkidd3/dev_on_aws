#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# End-of-course cleanup — removes ONLY resources that carry YOUR $USER_ID.
#
# The whole class shares one AWS account and everyone is an admin, so nothing
# stops a careless delete from hitting a classmate's work. This script matches
# exact per-student names only:
#   stack dev-on-aws-$U · API dev-on-aws-$U · user pool dev-on-aws-$U
#   function lab4-$U (+ its log group) · roles StudentLambdaRole-$U, Lab1cRole-$U
#   table Items-$U · buckets student-$U-*  (all versions emptied first)
# Your Cloud9 environment is left alone.
#
# Usage:
#   bash cleanup.sh            # dry run — list what would be deleted
#   bash cleanup.sh --delete   # actually delete
# -----------------------------------------------------------------------------
set -u
[ -f ~/.dev-on-aws.env ] && source ~/.dev-on-aws.env
export AWS_DEFAULT_REGION=us-east-1
U="${USER_ID:-}"
if [ -z "$U" ] || [ "$U" = "LabRole" ]; then
  echo "USER_ID is '${U:-empty}' — set it first:  export USER_ID=user1" >&2; exit 2
fi
DEL=0; [ "${1:-}" = "--delete" ] && DEL=1

act() {   # act "description" cmd args…   — prints, and runs only with --delete
  if [ "$DEL" = 1 ]; then
    if "${@:2}" >/dev/null 2>&1; then printf "  \033[32m✓\033[0m %s\n" "$1"
    else printf "  \033[31m✗\033[0m %s (failed or already gone)\n" "$1"; fi
  else printf "  • would delete: %s\n" "$1"; fi
}
q() { "$@" 2>/dev/null || true; }   # quiet lookup; empty output on error

echo "Cleanup for USER_ID=$U — $( [ "$DEL" = 1 ] && echo DELETING || echo 'DRY RUN (add --delete)')"

# SAM stack (Lab 7b)
if aws cloudformation describe-stacks --stack-name "dev-on-aws-$U" >/dev/null 2>&1; then
  act "stack dev-on-aws-$U" aws cloudformation delete-stack --stack-name "dev-on-aws-$U"
  [ "$DEL" = 1 ] && aws cloudformation wait stack-delete-complete --stack-name "dev-on-aws-$U"
fi

# API Gateway REST API (Labs 5a/6b)
for id in $(q aws apigateway get-rest-apis --query "items[?name=='dev-on-aws-$U'].id" --output text); do
  act "REST API dev-on-aws-$U ($id)" aws apigateway delete-rest-api --rest-api-id "$id"
done

# Cognito user pool (Lab 6a)
for id in $(q aws cognito-idp list-user-pools --max-results 60 \
              --query "UserPools[?Name=='dev-on-aws-$U'].Id" --output text); do
  act "user pool dev-on-aws-$U ($id)" aws cognito-idp delete-user-pool --user-pool-id "$id"
done

# Lambda function + logs (Labs 4a/4b/7a)
if aws lambda get-function --function-name "lab4-$U" >/dev/null 2>&1; then
  act "function lab4-$U" aws lambda delete-function --function-name "lab4-$U"
fi
if [ -n "$(q aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/lab4-$U" \
             --query "logGroups[?logGroupName=='/aws/lambda/lab4-$U'].logGroupName" --output text)" ]; then
  act "log group /aws/lambda/lab4-$U" aws logs delete-log-group --log-group-name "/aws/lambda/lab4-$U"
fi

# IAM roles (Labs 1c, 4a/4b) — inline policies and attachments must go first
for R in "StudentLambdaRole-$U" "Lab1cRole-$U"; do
  aws iam get-role --role-name "$R" >/dev/null 2>&1 || continue
  if [ "$DEL" = 1 ]; then
    for p in $(q aws iam list-role-policies --role-name "$R" --query PolicyNames --output text); do
      aws iam delete-role-policy --role-name "$R" --policy-name "$p"
    done
    for a in $(q aws iam list-attached-role-policies --role-name "$R" \
                 --query AttachedPolicies[].PolicyArn --output text); do
      aws iam detach-role-policy --role-name "$R" --policy-arn "$a"
      # The Lab 4a console wizard creates a customer-managed policy just for this role
      case "$a" in *:policy/service-role/AWSLambdaBasicExecutionRole-*)
        aws iam delete-policy --policy-arn "$a" 2>/dev/null ;; esac
    done
  fi
  act "role $R" aws iam delete-role --role-name "$R"
done

# DynamoDB table (Lab 3a)
if aws dynamodb describe-table --table-name "Items-$U" >/dev/null 2>&1; then
  act "table Items-$U" aws dynamodb delete-table --table-name "Items-$U"
fi

# S3 buckets (Labs 1c, 2a, 6c) — versioned buckets need every version removed
for B in $(q aws s3api list-buckets \
             --query "Buckets[?starts_with(Name,'student-$U-')].Name" --output text); do
  if [ "$DEL" = 1 ]; then
    # Every version + delete marker, 1000 per delete-objects call (CLI + stdlib only)
    python3 - "$B" <<'PY'
import json, subprocess, sys
b = sys.argv[1]
raw = subprocess.run(["aws", "s3api", "list-object-versions", "--bucket", b, "--output", "json"],
                     capture_output=True, text=True).stdout or "{}"
d = json.loads(raw)
objs = [{"Key": v["Key"], "VersionId": v["VersionId"]}
        for v in (d.get("Versions") or []) + (d.get("DeleteMarkers") or [])]
for i in range(0, len(objs), 1000):
    subprocess.run(["aws", "s3api", "delete-objects", "--bucket", b, "--delete",
                    json.dumps({"Objects": objs[i:i + 1000], "Quiet": True})],
                   check=True, capture_output=True)
PY
  fi
  act "bucket s3://$B (all versions)" aws s3 rb "s3://$B" --force
done

echo
[ "$DEL" = 1 ] && echo "Done." || echo "Nothing deleted. Re-run with --delete to remove the items above."
