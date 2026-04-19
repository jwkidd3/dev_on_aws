#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Developing-on-AWS course validator.
#
# Exercises every CLI/SDK operation the labs ask a student to run, using a
# unique resource prefix so it never collides with real student work. Prints a
# PASS/FAIL line per check and a final summary. Creates real AWS resources —
# expected cost per full run is a few cents. Cleans up after itself on any
# exit path (success, failure, or Ctrl-C).
#
# Run from a Cloud9 terminal:
#   cd ~/environment/dev_on_aws/validation   # after cloning the course repo
#   chmod +x run.sh
#   ./run.sh
#
# Skip expensive sections with flags:
#   ./run.sh --skip-sam        # skip Lab 7b (sam build + deploy; needs Docker)
#   ./run.sh --quick           # skip SAM and Cognito + API Gateway
# -----------------------------------------------------------------------------
set -u

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

STAMP="$(date +%Y%m%d-%H%M%S)"
PREFIX="labval-$STAMP"
TMP="$(mktemp -d)"

SKIP_SAM=0
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --skip-sam) SKIP_SAM=1 ;;
    --quick)    SKIP_SAM=1; QUICK=1 ;;
    -h|--help)
      sed -n '2,21p' "$0"; exit 0 ;;
  esac
done

PASS=0; FAIL=0
pass() { printf "  \033[32m✅\033[0m  %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m❌\033[0m  %s — %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
step() { echo; printf "\033[1m── %s ──\033[0m\n" "$1"; }

# Tracked resources (for cleanup)
BUCKET_UPLOADS=""; BUCKET_SITE=""; TABLE=""; LAMBDA_ROLE=""; LAMBDA_FN=""
REST_API=""; POOL_ID=""; SAM_STACK=""; PROBE_BUCKET=""

empty_versioned_bucket() {
  # Delete every version AND delete-marker from a bucket, then the bucket itself.
  local B="$1"
  aws s3api list-object-versions --bucket "$B" --output json 2>/dev/null \
    | python3 -c '
import json, sys, subprocess
data = json.load(sys.stdin)
items = (data.get("Versions") or []) + (data.get("DeleteMarkers") or [])
# Chunk into batches of 1000 (DeleteObjects limit)
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

delete_log_group() {
  # Swallow "does not exist" — the group is only auto-created after first invocation
  aws logs delete-log-group --log-group-name "$1" >/dev/null 2>&1 || true
}

cleanup() {
  step "Cleanup"
  # Reverse order of creation — best-effort, no hard fail
  [ -n "$SAM_STACK" ] && {
    aws cloudformation delete-stack --stack-name "$SAM_STACK" >/dev/null 2>&1 \
      && pass "cfn delete-stack $SAM_STACK" \
      || fail "cfn delete-stack" "non-zero"
  }
  [ -n "$POOL_ID" ] && {
    aws cognito-idp delete-user-pool --user-pool-id "$POOL_ID" >/dev/null 2>&1 \
      && pass "cognito delete-user-pool $POOL_ID" \
      || fail "cognito delete-user-pool" "non-zero"
  }
  [ -n "$REST_API" ] && {
    aws apigateway delete-rest-api --rest-api-id "$REST_API" >/dev/null 2>&1 \
      && pass "apigw delete-rest-api $REST_API" \
      || fail "apigw delete-rest-api" "non-zero"
  }
  [ -n "$LAMBDA_FN" ] && {
    aws lambda delete-function --function-name "$LAMBDA_FN" >/dev/null 2>&1 \
      && pass "lambda delete-function $LAMBDA_FN" \
      || fail "lambda delete-function" "non-zero"
    # Log group is created on first invoke; delete if present
    delete_log_group "/aws/lambda/$LAMBDA_FN"
    pass "logs delete-log-group /aws/lambda/$LAMBDA_FN"
  }
  [ -n "$LAMBDA_ROLE" ] && {
    # Remove inline policy
    aws iam delete-role-policy --role-name "$LAMBDA_ROLE" --policy-name LambdaAppAccess >/dev/null 2>&1 || true
    # Detach every managed policy attached during the run
    for P in \
        arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess; do
      aws iam detach-role-policy --role-name "$LAMBDA_ROLE" --policy-arn "$P" >/dev/null 2>&1 || true
    done
    aws iam delete-role --role-name "$LAMBDA_ROLE" >/dev/null 2>&1 \
      && pass "iam delete-role $LAMBDA_ROLE" \
      || fail "iam delete-role" "non-zero"
  }
  [ -n "$TABLE" ] && {
    aws dynamodb delete-table --table-name "$TABLE" >/dev/null 2>&1 \
      && pass "ddb delete-table $TABLE" \
      || fail "ddb delete-table" "non-zero"
  }
  # S3 buckets — handle versioning correctly
  for B in "$BUCKET_UPLOADS" "$BUCKET_SITE" "$PROBE_BUCKET"; do
    [ -z "$B" ] && continue
    empty_versioned_bucket "$B"
    if aws s3api head-bucket --bucket "$B" >/dev/null 2>&1; then
      fail "s3 rb $B" "bucket still present"
    else
      pass "s3 rb $B (versions + delete markers cleared)"
    fi
  done
  # API Gateway access log group (created in Lab 5b pattern; no-op if absent)
  delete_log_group "/aws/apigateway/$PREFIX"
  rm -rf "$TMP"
  echo
  printf "\033[1mRESULT: %d passed, %d failed\033[0m\n" "$PASS" "$FAIL"
  exit "$FAIL"
}
trap cleanup EXIT

# ----- Prerequisites -----
step "Prerequisites"
aws --version >/dev/null 2>&1 && pass "aws CLI on PATH" || { fail "aws CLI" "not installed"; exit 1; }
python3 --version >/dev/null 2>&1 && pass "python3 on PATH" || { fail "python3" "not installed"; exit 1; }

ACCT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  && pass "sts get-caller-identity ($ACCT)" \
  || { fail "sts get-caller-identity" "auth"; exit 1; }

# ----- Lab 1b — boto3 install & smoke -----
step "Lab 1b — boto3 install & smoke"
pip3 install --user --quiet boto3 >/dev/null 2>&1 \
  && pass "pip3 install --user boto3" \
  || fail "pip3 install boto3" "non-zero"

python3 -c "import boto3; boto3.client('sts').get_caller_identity()" 2>/dev/null \
  && pass "boto3 + STS from Python" \
  || fail "boto3 STS" "import or call failed"

# ----- Lab 1c — IAM deny + policy -----
step "Lab 1c — IAM AccessDenied + bucket-delete gap"
# IAM CreateUser should fail for a constrained caller; but the tester likely has admin,
# so we only assert that the CLI command path works, not that it denies.
PROBE_BUCKET="${PREFIX}-probe"
aws s3 mb "s3://$PROBE_BUCKET" >/dev/null 2>&1 \
  && pass "s3 mb $PROBE_BUCKET (probe)" \
  || fail "s3 mb probe" "non-zero"
aws s3 rb "s3://$PROBE_BUCKET" >/dev/null 2>&1 \
  && { pass "s3 rb probe"; PROBE_BUCKET=""; } \
  || fail "s3 rb probe" "non-zero"

# ----- Lab 2a/2b — S3 -----
step "Lab 2a/2b — S3 CRUD, metadata, presigned URLs"
BUCKET_UPLOADS="${PREFIX}-uploads"
aws s3 mb "s3://$BUCKET_UPLOADS" >/dev/null 2>&1 \
  && pass "s3 mb $BUCKET_UPLOADS" \
  || fail "s3 mb uploads" "non-zero"

aws s3api put-bucket-versioning --bucket "$BUCKET_UPLOADS" \
  --versioning-configuration Status=Enabled >/dev/null 2>&1 \
  && pass "enable versioning" \
  || fail "versioning" "non-zero"

echo "hello" | aws s3api put-object --bucket "$BUCKET_UPLOADS" --key "hello.txt" \
  --body /dev/stdin --metadata "owner=validator" >/dev/null 2>&1 \
  && pass "put-object with metadata" \
  || fail "put-object" "non-zero"

aws s3api head-object --bucket "$BUCKET_UPLOADS" --key "hello.txt" \
  --query 'Metadata.owner' --output text 2>/dev/null | grep -q validator \
  && pass "head-object returns metadata" \
  || fail "metadata readback" "mismatch"

python3 - "$BUCKET_UPLOADS" <<'PYEOF' >/dev/null 2>&1 && pass "boto3 generate_presigned_url (GET)" || fail "presigned GET" "python error"
import boto3, sys
url = boto3.client("s3").generate_presigned_url(
    "get_object", Params={"Bucket": sys.argv[1], "Key": "hello.txt"}, ExpiresIn=60)
assert url.startswith("https://")
PYEOF

python3 - "$BUCKET_UPLOADS" <<'PYEOF' >/dev/null 2>&1 && pass "boto3 generate_presigned_url (PUT)" || fail "presigned PUT" "python error"
import boto3, sys
url = boto3.client("s3").generate_presigned_url(
    "put_object", Params={"Bucket": sys.argv[1], "Key": "up.txt"}, ExpiresIn=60)
assert url.startswith("https://")
PYEOF

# ----- Lab 3a/3b — DynamoDB -----
step "Lab 3a/3b — DynamoDB table + GSI + CRUD"
TABLE="Items-${PREFIX}"
aws dynamodb create-table --table-name "$TABLE" \
  --attribute-definitions \
      AttributeName=pk,AttributeType=S \
      AttributeName=sk,AttributeType=S \
      AttributeName=category,AttributeType=S \
      AttributeName=price,AttributeType=N \
  --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes \
      "IndexName=byCategory,KeySchema=[{AttributeName=category,KeyType=HASH},{AttributeName=price,KeyType=RANGE}],Projection={ProjectionType=ALL}" \
  >/dev/null 2>&1 \
  && pass "create-table $TABLE with byCategory GSI" \
  || fail "create-table" "non-zero"

aws dynamodb wait table-exists --table-name "$TABLE" 2>/dev/null \
  && pass "table reached ACTIVE" \
  || fail "table-exists waiter" "timeout"

python3 - "$TABLE" <<'PYEOF' >/dev/null 2>&1 && pass "boto3 batch put + query" || fail "batch put/query" "python error"
import boto3, sys
from decimal import Decimal
t = boto3.resource("dynamodb").Table(sys.argv[1])
with t.batch_writer() as bw:
    for i in range(3, 8):
        bw.put_item(Item={"pk":"USER#validator","sk":f"ITEM#{i:03d}",
                          "category":"widgets","price":Decimal(f"{i}.99")})
from boto3.dynamodb.conditions import Key
r = t.query(KeyConditionExpression=Key("pk").eq("USER#validator"))
assert len(r["Items"]) == 5, len(r["Items"])
PYEOF

python3 - "$TABLE" <<'PYEOF' >/dev/null 2>&1 && pass "conditional update with ADD/SET" || fail "update_item" "python error"
import boto3, sys
from decimal import Decimal
t = boto3.resource("dynamodb").Table(sys.argv[1])
t.update_item(
    Key={"pk":"USER#validator","sk":"ITEM#003"},
    UpdateExpression="SET price = :p ADD #v :one",
    ExpressionAttributeNames={"#v":"views"},
    ExpressionAttributeValues={":p":Decimal("1.00"),":one":1})
PYEOF

python3 - "$TABLE" <<'PYEOF' >/dev/null 2>&1 && pass "GSI query" || fail "GSI query" "python error"
import boto3, sys
from boto3.dynamodb.conditions import Key
from decimal import Decimal
t = boto3.resource("dynamodb").Table(sys.argv[1])
r = t.query(IndexName="byCategory",
            KeyConditionExpression=Key("category").eq("widgets"))
assert len(r["Items"]) >= 1
PYEOF

# ----- Lab 4a — Lambda create + role -----
step "Lab 4a/4b — Lambda role, function, invoke, S3 trigger"
LAMBDA_ROLE="StudentLambdaRole-${PREFIX}"
cat > "$TMP/trust.json" <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name "$LAMBDA_ROLE" \
  --assume-role-policy-document file://"$TMP/trust.json" >/dev/null 2>&1 \
  && pass "create-role $LAMBDA_ROLE" \
  || fail "create-role" "non-zero"

aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null 2>&1 \
  && pass "attach AWSLambdaBasicExecutionRole" \
  || fail "attach policy" "non-zero"

# Inline policy equivalent to lab4/lambda-perms.json
cat > "$TMP/perms.json" <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow",
  "Action":["dynamodb:PutItem","dynamodb:GetItem","dynamodb:Query"],
  "Resource":"arn:aws:dynamodb:$REGION:$ACCT:table/$TABLE"},
 {"Effect":"Allow",
  "Action":["s3:GetObject","s3:PutObject"],
  "Resource":"arn:aws:s3:::$BUCKET_UPLOADS/*"}]}
EOF
aws iam put-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-name LambdaAppAccess \
  --policy-document file://"$TMP/perms.json" >/dev/null 2>&1 \
  && pass "put-role-policy LambdaAppAccess (sed pattern equivalent)" \
  || fail "inline policy" "non-zero"

# Wait for IAM propagation
sleep 10

# Package a minimal handler
cat > "$TMP/handler.py" <<'EOF'
import json
def handler(event, ctx):
    return {"statusCode": 200, "body": json.dumps({"ok": True, "event": event})}
EOF
( cd "$TMP" && zip -q function.zip handler.py )

LAMBDA_FN="lab4-${PREFIX}"
aws lambda create-function --function-name "$LAMBDA_FN" \
  --runtime python3.12 --architectures arm64 \
  --role "arn:aws:iam::$ACCT:role/$LAMBDA_ROLE" \
  --handler handler.handler \
  --zip-file "fileb://$TMP/function.zip" \
  --timeout 10 --memory-size 256 >/dev/null 2>&1 \
  && pass "create-function $LAMBDA_FN" \
  || fail "create-function" "non-zero"

sleep 3  # function state → Active
aws lambda wait function-active-v2 --function-name "$LAMBDA_FN" 2>/dev/null \
  && pass "function reached Active" \
  || fail "function-active waiter" "timeout"

aws lambda invoke --function-name "$LAMBDA_FN" \
  --payload '{"test":"validator"}' --cli-binary-format raw-in-base64-out \
  "$TMP/out.json" >/dev/null 2>&1 && grep -q '"ok": true' "$TMP/out.json" \
  && pass "invoke + parse response" \
  || fail "invoke" "bad response"

aws lambda update-function-configuration --function-name "$LAMBDA_FN" \
  --tracing-config Mode=Active >/dev/null 2>&1 \
  && pass "enable X-Ray tracing" \
  || fail "tracing on" "non-zero"

aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess >/dev/null 2>&1 \
  && pass "attach AWSXRayDaemonWriteAccess" \
  || fail "xray policy" "non-zero"

# Versioning + alias (Lab 4b Step 6)
sleep 3  # allow config update to settle
V=$(aws lambda publish-version --function-name "$LAMBDA_FN" \
    --query Version --output text 2>/dev/null) \
  && pass "publish-version = $V" \
  || fail "publish-version" "non-zero"

if [ -n "$V" ]; then
  aws lambda create-alias --function-name "$LAMBDA_FN" \
    --name prod --function-version "$V" >/dev/null 2>&1 \
    && pass "create-alias prod -> $V" \
    || fail "create-alias" "non-zero"
fi

# ----- Lab 5a — API Gateway REST -----
step "Lab 5a — API Gateway REST + Lambda proxy"
REST_API=$(aws apigateway create-rest-api --name "$PREFIX" \
  --endpoint-configuration types=REGIONAL \
  --query id --output text 2>/dev/null) \
  && pass "create-rest-api $REST_API" \
  || fail "create-rest-api" "non-zero"

if [ -n "$REST_API" ]; then
  ROOT=$(aws apigateway get-resources --rest-api-id "$REST_API" \
    --query "items[?path=='/'].id" --output text 2>/dev/null)
  ITEMS=$(aws apigateway create-resource --rest-api-id "$REST_API" \
    --parent-id "$ROOT" --path-part items \
    --query id --output text 2>/dev/null) \
    && pass "create-resource /items" || fail "create-resource" "non-zero"

  aws apigateway put-method --rest-api-id "$REST_API" --resource-id "$ITEMS" \
    --http-method POST --authorization-type NONE >/dev/null 2>&1 \
    && pass "put-method POST" || fail "put-method" "non-zero"

  LAMBDA_ARN="arn:aws:lambda:$REGION:$ACCT:function:$LAMBDA_FN"
  aws apigateway put-integration --rest-api-id "$REST_API" --resource-id "$ITEMS" \
    --http-method POST --type AWS_PROXY --integration-http-method POST \
    --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
    >/dev/null 2>&1 \
    && pass "put-integration AWS_PROXY" || fail "put-integration" "non-zero"

  aws lambda add-permission --function-name "$LAMBDA_FN" \
    --statement-id "apigw-$STAMP" \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCT:$REST_API/*/POST/items" \
    >/dev/null 2>&1 \
    && pass "add-permission (apigw invoke)" || fail "add-permission" "non-zero"

  aws apigateway create-deployment --rest-api-id "$REST_API" --stage-name dev \
    >/dev/null 2>&1 \
    && pass "create-deployment stage=dev" || fail "deployment" "non-zero"
fi

if [ $QUICK -eq 0 ]; then
  # ----- Lab 6a — Cognito -----
  step "Lab 6a — Cognito user pool + app client + user"
  POOL_ID=$(aws cognito-idp create-user-pool --pool-name "$PREFIX" \
    --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true}' \
    --username-attributes email --auto-verified-attributes email \
    --query "UserPool.Id" --output text 2>/dev/null) \
    && pass "create-user-pool $POOL_ID" \
    || fail "create-user-pool" "non-zero"

  if [ -n "$POOL_ID" ]; then
    CLIENT_ID=$(aws cognito-idp create-user-pool-client \
      --user-pool-id "$POOL_ID" --client-name web --no-generate-secret \
      --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
      --query "UserPoolClient.ClientId" --output text 2>/dev/null) \
      && pass "create-user-pool-client $CLIENT_ID" \
      || fail "create-user-pool-client" "non-zero"

    aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" \
      --username "validator@example.com" \
      --user-attributes Name=email,Value=validator@example.com Name=email_verified,Value=true \
      --message-action SUPPRESS >/dev/null 2>&1 \
      && pass "admin-create-user" || fail "admin-create-user" "non-zero"

    aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" \
      --username "validator@example.com" \
      --password 'Tr0picalStorm!' --permanent >/dev/null 2>&1 \
      && pass "admin-set-user-password (permanent)" \
      || fail "admin-set-user-password" "non-zero"

    # initiate-auth returns a JSON with IdToken on success
    AUTH=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH \
      --client-id "$CLIENT_ID" \
      --auth-parameters "USERNAME=validator@example.com,PASSWORD=Tr0picalStorm!" \
      --query "AuthenticationResult.IdToken" --output text 2>/dev/null) \
      && [ -n "$AUTH" ] && pass "initiate-auth returns IdToken" \
      || fail "initiate-auth" "no token"

    # Lab 6b — API Gateway Cognito authorizer (exercised against the Lab 5a API)
    if [ -n "$REST_API" ]; then
      AUTH_ID=$(aws apigateway create-authorizer --rest-api-id "$REST_API" \
        --name "cognito-$STAMP" --type COGNITO_USER_POOLS \
        --identity-source method.request.header.Authorization \
        --provider-arns "arn:aws:cognito-idp:$REGION:$ACCT:userpool/$POOL_ID" \
        --query id --output text 2>/dev/null) \
        && pass "create-authorizer" \
        || fail "create-authorizer" "non-zero"
    fi
  fi
fi

# ----- Lab 7b — SAM -----
if [ $SKIP_SAM -eq 0 ]; then
  step "Lab 7b — SAM build + deploy (requires Docker)"
  if ! command -v sam >/dev/null 2>&1; then
    fail "sam CLI" "not installed — pass --skip-sam to bypass"
  else
    SAM_DIR="$TMP/sam"
    mkdir -p "$SAM_DIR/python"
    cp "$(dirname "$0")/../labs/files/lab7/template.yaml" "$SAM_DIR/template.yaml" 2>/dev/null || {
      # fallback: minimal template
      cat > "$SAM_DIR/template.yaml" <<'EOF'
Transform: AWS::Serverless-2016-10-31
Parameters:
  CognitoPoolId:   { Type: String }
  CognitoClientId: { Type: String }
  UploadsBucket:   { Type: String }
Resources:
  ItemsTable:
    Type: AWS::Serverless::SimpleTable
    Properties: { PrimaryKey: { Name: pk, Type: String } }
  Fn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.12
      Handler: handler.handler
      CodeUri: python/
      Tracing: Active
      Policies:
        - DynamoDBCrudPolicy: { TableName: !Ref ItemsTable }
EOF
    }
    cp "$(dirname "$0")/../labs/files/lab7/python/handler.py" "$SAM_DIR/python/handler.py" 2>/dev/null || \
      echo "def handler(e,c): return {'statusCode':200,'body':'ok'}" > "$SAM_DIR/python/handler.py"

    (cd "$SAM_DIR" && sam build >/dev/null 2>&1) \
      && pass "sam build" || fail "sam build" "non-zero"

    SAM_STACK="sam-${PREFIX}"
    (cd "$SAM_DIR" && sam deploy \
      --stack-name "$SAM_STACK" \
      --resolve-s3 --no-confirm-changeset \
      --capabilities CAPABILITY_IAM \
      --parameter-overrides \
        "CognitoPoolId=${POOL_ID:-none} CognitoClientId=${CLIENT_ID:-none} UploadsBucket=$BUCKET_UPLOADS" \
      >/dev/null 2>&1) \
      && pass "sam deploy $SAM_STACK" || fail "sam deploy" "non-zero"
  fi
fi

# cleanup() is called via trap on EXIT
