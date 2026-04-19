#!/usr/bin/env bash
# Idempotent "catch me up" setup for any lab in this course.
# Usage:   bash bootstrap.sh <labId>
# labId ∈ { 1b 2a 2b 3a 3b 4a 4b 5a 6a 6b 6c 7a 7b }
#
# Creates-or-reuses every AWS resource the target lab depends on and
# exports the env vars downstream labs reference into ~/.dev-on-aws.env.
# Safe to re-run; existing resources are detected and skipped.

set -euo pipefail

LAB="${1:-}"
[ -z "$LAB" ] && { echo "usage: bash bootstrap.sh <labId>" >&2; exit 2; }

REGION=us-east-1
ENV=~/.dev-on-aws.env
FILES=$(cd "$(dirname "$0")" && pwd)   # where lab1/ lab3/ lab4/ etc live

say()  { printf "  \033[34m→\033[0m  %s\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
skip() { printf "  \033[90m·\033[0m  %s (already present)\n" "$*"; }
die()  { printf "  \033[31m✗\033[0m  %s\n" "$*" >&2; exit 1; }

touch "$ENV"
putenv() {   # putenv KEY=VALUE — upsert into $ENV
  local k="${1%%=*}" v="${1#*=}"
  if grep -qE "^export ${k}=" "$ENV" 2>/dev/null; then
    # BSD/GNU sed compatible in-place
    sed -i.bak -E "s|^export ${k}=.*|export ${k}=${v}|" "$ENV" && rm -f "${ENV}.bak"
  else
    echo "export ${k}=${v}" >> "$ENV"
  fi
}

#── env ────────────────────────────────────────────────────────────────
ensure_env() {
  say "ensure_env"
  if [ -z "${USER_ID:-}" ]; then
    local ARN
    ARN=$(aws sts get-caller-identity --query Arn --output text)
    USER_ID=$(echo "$ARN" | sed -nE 's|.*:(user|assumed-role)/([^/]+).*|\2|p')
    [ -z "$USER_ID" ] && die "could not derive USER_ID from $ARN"
  fi
  ACCT=$(aws sts get-caller-identity --query Account --output text)
  putenv "USER_ID=$USER_ID"
  putenv "ACCT=$ACCT"
  export USER_ID ACCT
  ok "USER_ID=$USER_ID ACCT=$ACCT"
}

#── S3 uploads bucket (Lab 2a) ────────────────────────────────────────
ensure_bucket() {
  say "ensure_bucket"
  local B=""
  # 1. env-provided takes priority
  if [ -n "${BUCKET:-}" ] && aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    B="$BUCKET"; skip "s3://$B (from env)"
  else
    # 2. discover any student-$USER_ID-uploads* the student created earlier
    B=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'student-${USER_ID}-uploads')] | [0].Name" \
        --output text 2>/dev/null || true)
    if [ -z "$B" ] || [ "$B" = "None" ]; then
      # 3. create a fresh one
      B="student-${USER_ID}-uploads-$(date +%Y%m%d)"
      aws s3 mb "s3://$B" >/dev/null
      aws s3api put-bucket-versioning --bucket "$B" \
        --versioning-configuration Status=Enabled
      ok "s3://$B (created)"
    else
      skip "s3://$B (discovered)"
    fi
  fi
  putenv "BUCKET=$B"
  export BUCKET="$B"
}

#── DynamoDB Items-$USER_ID (Lab 3a) ──────────────────────────────────
ensure_table() {
  say "ensure_table"
  local T="Items-$USER_ID"
  if aws dynamodb describe-table --table-name "$T" >/dev/null 2>&1; then
    skip "$T"
  else
    aws dynamodb create-table --table-name "$T" \
      --attribute-definitions \
          AttributeName=id,AttributeType=S \
          AttributeName=category,AttributeType=S \
      --key-schema AttributeName=id,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --global-secondary-indexes \
        "IndexName=byCategory,KeySchema=[{AttributeName=category,KeyType=HASH}],Projection={ProjectionType=ALL}" \
      >/dev/null
    aws dynamodb wait table-exists --table-name "$T"
    ok "$T (with byCategory GSI)"
  fi
}

#── Lambda execution role + function (Lab 4a/4b) ──────────────────────
ensure_lambda() {
  say "ensure_lambda"
  local R="StudentLambdaRole-$USER_ID"
  local F="lab4-$USER_ID"

  if ! aws iam get-role --role-name "$R" >/dev/null 2>&1; then
    local TMP; TMP=$(mktemp -d)
    cat > "$TMP/trust.json" <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
    aws iam create-role --role-name "$R" \
        --assume-role-policy-document "file://$TMP/trust.json" >/dev/null
    aws iam attach-role-policy --role-name "$R" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    cat > "$TMP/perms.json" <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow",
  "Action":["dynamodb:PutItem","dynamodb:GetItem","dynamodb:Query",
            "dynamodb:UpdateItem","dynamodb:DeleteItem"],
  "Resource":"arn:aws:dynamodb:$REGION:$ACCT:table/Items-$USER_ID"},
 {"Effect":"Allow",
  "Action":["s3:GetObject","s3:PutObject"],
  "Resource":"arn:aws:s3:::$BUCKET/*"}]}
EOF
    aws iam put-role-policy --role-name "$R" \
        --policy-name LambdaAppAccess \
        --policy-document "file://$TMP/perms.json"
    rm -rf "$TMP"
    ok "role $R"
  else
    skip "role $R"
  fi

  if ! aws lambda get-function --function-name "$F" >/dev/null 2>&1; then
    local SRC="$FILES/lab4/handler.py"
    [ -f "$SRC" ] || die "missing $SRC — did you clone the course repo?"
    local Z; Z=$(mktemp -d)/function.zip
    (cd "$(dirname "$SRC")" && zip -q "$Z" handler.py)

    # IAM propagation — retry with backoff
    local created=0
    for delay in 5 10 15 20 25; do
      sleep "$delay"
      if aws lambda create-function --function-name "$F" \
            --runtime python3.12 --architectures arm64 \
            --role "arn:aws:iam::$ACCT:role/$R" --handler handler.handler \
            --zip-file "fileb://$Z" --timeout 10 --memory-size 256 \
            --environment "Variables={ITEMS_TABLE=Items-$USER_ID,UPLOADS_BUCKET=$BUCKET}" \
            >/dev/null 2>&1; then
        created=1; break
      fi
    done
    [ "$created" = 1 ] || die "lambda create-function failed after retries"
    aws lambda wait function-active-v2 --function-name "$F" 2>/dev/null \
      || aws lambda wait function-active --function-name "$F"
    ok "function $F"
  else
    skip "function $F"
  fi

  LAMBDA_ARN=$(aws lambda get-function --function-name "$F" \
      --query Configuration.FunctionArn --output text)
  putenv "LAMBDA_ARN=$LAMBDA_ARN"
  export LAMBDA_ARN
}

#── API Gateway REST + /items + deploy (Lab 5a) ───────────────────────
ensure_api() {
  say "ensure_api"
  local NAME="dev-on-aws-$USER_ID"
  local AID IID
  AID=$(aws apigateway get-rest-apis \
        --query "items[?name=='$NAME'].id | [0]" --output text)

  if [ -z "$AID" ] || [ "$AID" = "None" ]; then
    AID=$(aws apigateway create-rest-api --name "$NAME" \
           --endpoint-configuration types=REGIONAL \
           --query id --output text)
    local ROOT
    ROOT=$(aws apigateway get-resources --rest-api-id "$AID" \
           --query "items[0].id" --output text)
    IID=$(aws apigateway create-resource --rest-api-id "$AID" \
          --parent-id "$ROOT" --path-part items --query id --output text)
    aws apigateway put-method --rest-api-id "$AID" --resource-id "$IID" \
        --http-method POST --authorization-type NONE >/dev/null
    aws apigateway put-integration --rest-api-id "$AID" --resource-id "$IID" \
        --http-method POST --type AWS_PROXY --integration-http-method POST \
        --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
        >/dev/null
    aws lambda add-permission --function-name "lab4-$USER_ID" \
        --statement-id "apigw-$USER_ID-$(date +%s)" \
        --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$REGION:$ACCT:$AID/*/*/items" \
        >/dev/null 2>&1 || true
    aws apigateway create-deployment --rest-api-id "$AID" --stage-name dev >/dev/null
    ok "api $NAME ($AID)"
  else
    IID=$(aws apigateway get-resources --rest-api-id "$AID" \
          --query "items[?path=='/items'].id | [0]" --output text)
    skip "api $NAME ($AID)"
  fi

  local URL="https://$AID.execute-api.$REGION.amazonaws.com/dev/items"
  putenv "API_ID=$AID"
  putenv "ITEMS_ID=$IID"
  putenv "URL=$URL"
  export API_ID="$AID" ITEMS_ID="$IID" URL
}

#── Cognito pool + client + user + fresh ID token (Lab 6a/6b) ─────────
ensure_cognito() {
  say "ensure_cognito"
  local PNAME="dev-on-aws-pool-$USER_ID"
  local PID
  PID=$(aws cognito-idp list-user-pools --max-results 60 \
        --query "UserPools[?Name=='$PNAME'].Id | [0]" --output text)
  if [ -z "$PID" ] || [ "$PID" = "None" ]; then
    PID=$(aws cognito-idp create-user-pool --pool-name "$PNAME" \
          --auto-verified-attributes email \
          --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=false,RequireLowercase=false,RequireNumbers=false,RequireSymbols=false}' \
          --query UserPool.Id --output text)
    ok "pool $PID"
  else skip "pool $PID"; fi

  local CNAME="dev-on-aws-client-$USER_ID"
  local CID
  CID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$PID" \
        --query "UserPoolClients[?ClientName=='$CNAME'].ClientId | [0]" \
        --output text)
  if [ -z "$CID" ] || [ "$CID" = "None" ]; then
    CID=$(aws cognito-idp create-user-pool-client --user-pool-id "$PID" \
          --client-name "$CNAME" \
          --explicit-auth-flows ALLOW_ADMIN_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
          --query UserPoolClient.ClientId --output text)
    ok "client $CID"
  else skip "client $CID"; fi

  aws cognito-idp admin-create-user --user-pool-id "$PID" \
      --username "student-$USER_ID" \
      --user-attributes Name=email,Value="student-$USER_ID@example.com" Name=email_verified,Value=true \
      --message-action SUPPRESS >/dev/null 2>&1 || true
  aws cognito-idp admin-set-user-password --user-pool-id "$PID" \
      --username "student-$USER_ID" --password "Passw0rd!LabRun" \
      --permanent >/dev/null 2>&1 || true

  local TOKEN
  TOKEN=$(aws cognito-idp admin-initiate-auth --user-pool-id "$PID" \
          --client-id "$CID" --auth-flow ADMIN_USER_PASSWORD_AUTH \
          --auth-parameters "USERNAME=student-$USER_ID,PASSWORD=Passw0rd!LabRun" \
          --query AuthenticationResult.IdToken --output text)
  putenv "POOL_ID=$PID"
  putenv "CLIENT_ID=$CID"
  putenv "ID_TOKEN=$TOKEN"
  export POOL_ID="$PID" CLIENT_ID="$CID" ID_TOKEN="$TOKEN"
  ok "ID_TOKEN captured"
}

#── Static-site bucket (Lab 6c) ───────────────────────────────────────
ensure_site() {
  say "ensure_site"
  local S=""
  if [ -n "${SITE:-}" ] && aws s3api head-bucket --bucket "$SITE" 2>/dev/null; then
    S="$SITE"; skip "s3://$S (from env)"
  else
    S=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'student-${USER_ID}-site')] | [0].Name" \
        --output text 2>/dev/null || true)
    if [ -z "$S" ] || [ "$S" = "None" ]; then
      S="student-${USER_ID}-site-$(date +%Y%m%d)"
      aws s3 mb "s3://$S" >/dev/null
      aws s3api put-public-access-block --bucket "$S" \
        --public-access-block-configuration \
        "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
      aws s3 website "s3://$S/" --index-document index.html --error-document error.html
      ok "s3://$S (+ website config)"
    else
      skip "s3://$S (discovered)"
    fi
  fi
  putenv "SITE=$S"
  export SITE="$S"
}

#── Dispatch ──────────────────────────────────────────────────────────
case "$LAB" in
  1b)             ensure_env ;;
  2a|2b)          ensure_env ;;
  3a|3b)          ensure_env ;;
  4a)             ensure_env; ensure_bucket; ensure_table ;;
  4b|5a)          ensure_env; ensure_bucket; ensure_table; ensure_lambda ;;
  6a)             ensure_env; ensure_bucket; ensure_table; ensure_lambda; ensure_api ;;
  6b|7a|7b)       ensure_env; ensure_bucket; ensure_table; ensure_lambda; ensure_api; ensure_cognito ;;
  6c)             ensure_env; ensure_bucket; ensure_table; ensure_lambda; ensure_api; ensure_cognito; ensure_site ;;
  *) echo "Unknown lab: $LAB  (expected 1b|2a|2b|3a|3b|4a|4b|5a|6a|6b|6c|7a|7b)" >&2; exit 2 ;;
esac

echo
echo "Bootstrap for Lab $LAB complete. Open a new terminal OR run:"
echo "    source ~/.dev-on-aws.env"
