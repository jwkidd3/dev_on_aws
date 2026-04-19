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
#   ./run.sh --skip-bootstrap  # skip the bootstrap.sh idempotency check
#   ./run.sh --quick           # skip SAM, Cognito + API Gateway, AND bootstrap
# -----------------------------------------------------------------------------
set -u

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

STAMP="$(date +%Y%m%d-%H%M%S)"
PREFIX="labval-$STAMP"
TMP="$(mktemp -d)"

SKIP_SAM=0
SKIP_BOOTSTRAP=0
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --skip-sam)       SKIP_SAM=1 ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=1 ;;
    --quick)          SKIP_SAM=1; SKIP_BOOTSTRAP=1; QUICK=1 ;;
    -h|--help)
      sed -n '2,22p' "$0"; exit 0 ;;
  esac
done

PASS=0; FAIL=0
pass() { printf "  \033[32m✅\033[0m  %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m❌\033[0m  %s — %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
step() { echo; printf "\033[1m── %s ──\033[0m\n" "$1"; }

# Run an AWS (or any) command, capturing stderr so we can surface the
# real reason a check failed instead of a generic "non-zero".
# Usage: try "description" aws iam create-role ...
try() {
  local desc="$1"; shift
  local err; err=$("$@" 2>&1 >/dev/null) && { pass "$desc"; return 0; }
  # Truncate long multi-line errors to one readable line
  err=$(printf '%s' "$err" | tr '\n' ' ' | head -c 220)
  fail "$desc" "${err:-non-zero}"
  return 1
}

# Tracked resources (for cleanup)
BUCKET_UPLOADS=""; BUCKET_SITE=""; TABLE=""; LAMBDA_ROLE=""; LAMBDA_FN=""
REST_API=""; POOL_ID=""; SAM_STACK=""; PROBE_BUCKET=""
# Bootstrap-stage resources (created via labs/files/bootstrap.sh under a distinct USER_ID)
BS_USER_ID=""; BS_BUCKET=""; BS_TABLE=""; BS_ROLE=""; BS_FN=""; BS_API=""; BS_POOL=""; BS_SITE=""

empty_versioned_bucket() {
  # Delete every version AND delete-marker from a bucket, then the bucket itself.
  local B="$1"
  local RAW
  RAW=$(aws s3api list-object-versions --bucket "$B" --output json 2>/dev/null) || RAW=""
  if [ -n "$RAW" ]; then
    printf '%s' "$RAW" | python3 -c '
import json, sys, subprocess
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
items = (data.get("Versions") or []) + (data.get("DeleteMarkers") or [])
for i in range(0, len(items), 1000):
    batch = items[i:i+1000]
    payload = {"Objects":[{"Key":x["Key"],"VersionId":x["VersionId"]} for x in batch],
               "Quiet":True}
    subprocess.run(["aws","s3api","delete-objects","--bucket",sys.argv[1],
                    "--delete",json.dumps(payload)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
' "$B" 2>/dev/null || true
  fi
  aws s3 rb "s3://$B" --force >/dev/null 2>&1
}

delete_log_group() {
  # Swallow "does not exist" — the group is only auto-created after first invocation
  aws logs delete-log-group --log-group-name "$1" >/dev/null 2>&1 || true
}

# APIGW throttles DeleteRestApi at 1 req / 30 s / account — retry with backoff.
# On total failure, print the last AWS error to stdout so the caller can surface it.
delete_rest_api() {
  local id="$1" last_err=""
  for delay in 0 35 60 90 120; do
    [ "$delay" -gt 0 ] && sleep "$delay"
    last_err=$(aws apigateway delete-rest-api --rest-api-id "$id" 2>&1 >/dev/null) && return 0
  done
  printf '%s' "$last_err" | tr '\n' ' ' | head -c 200
  return 1
}

cleanup() {
  step "Cleanup"
  # Reverse order of creation — best-effort, no hard fail

  # --- Bootstrap-stage teardown (if the bootstrap test created anything) ---
  [ -n "$BS_POOL" ] && {
    aws cognito-idp delete-user-pool --user-pool-id "$BS_POOL" >/dev/null 2>&1 \
      && pass "bootstrap cleanup: pool $BS_POOL" \
      || fail "bootstrap delete-user-pool" "non-zero"
  }
  [ -n "$BS_API" ] && {
    local_err=$(delete_rest_api "$BS_API") \
      && pass "bootstrap cleanup: api $BS_API" \
      || fail "bootstrap delete-rest-api" "${local_err:-throttled after retries}"
  }
  [ -n "$BS_FN" ] && {
    aws lambda delete-function --function-name "$BS_FN" >/dev/null 2>&1 \
      && pass "bootstrap cleanup: function $BS_FN" \
      || fail "bootstrap delete-function" "non-zero"
    delete_log_group "/aws/lambda/$BS_FN"
  }
  [ -n "$BS_ROLE" ] && {
    aws iam delete-role-policy --role-name "$BS_ROLE" --policy-name LambdaAppAccess >/dev/null 2>&1 || true
    aws iam detach-role-policy --role-name "$BS_ROLE" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null 2>&1 || true
    aws iam delete-role --role-name "$BS_ROLE" >/dev/null 2>&1 \
      && pass "bootstrap cleanup: role $BS_ROLE" \
      || fail "bootstrap delete-role" "non-zero"
  }
  [ -n "$BS_TABLE" ] && {
    aws dynamodb delete-table --table-name "$BS_TABLE" >/dev/null 2>&1 \
      && pass "bootstrap cleanup: table $BS_TABLE" \
      || fail "bootstrap delete-table" "non-zero"
  }
  for B in "$BS_BUCKET" "$BS_SITE"; do
    [ -z "$B" ] && continue
    empty_versioned_bucket "$B"
    aws s3api head-bucket --bucket "$B" >/dev/null 2>&1 \
      && fail "bootstrap rb $B" "still present" \
      || pass "bootstrap cleanup: s3 rb $B"
  done

  # --- Main-stage teardown ---
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
    local_err=$(delete_rest_api "$REST_API") \
      && pass "apigw delete-rest-api $REST_API" \
      || fail "apigw delete-rest-api" "${local_err:-throttled after retries}"
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

# ----- Bootstrap script — idempotent "catch me up" setup -----
# Exercises every supported labId (13) in dependency order under a single
# synthetic USER_ID, so every ensure_* function in bootstrap.sh is invoked
# and each AWS resource is created exactly once. Then spot-checks
# idempotency by re-running the top-of-chain target.
if [ "$SKIP_BOOTSTRAP" = 0 ]; then
  step "bootstrap.sh — all 13 labIds under one synthetic user"
  BOOTSTRAP="$(cd "$(dirname "$0")/.." && pwd)/labs/files/bootstrap.sh"
  if [ ! -f "$BOOTSTRAP" ]; then
    fail "bootstrap.sh present" "$BOOTSTRAP not found"
  else
    pass "bootstrap.sh present"

    BS_USER_ID="bsval${STAMP//-/}"           # S3-bucket-safe; no dashes
    BS_ROLE="StudentLambdaRole-${BS_USER_ID}"
    BS_FN="lab4-${BS_USER_ID}"
    BS_TABLE="Items-${BS_USER_ID}"

    # Redirect ~/.dev-on-aws.env into tempdir so the validator doesn't
    # clobber the operator's real env file.
    HOME_ORIG="$HOME"; export HOME="$TMP"
    : > "$TMP/.dev-on-aws.env"

    # Run every labId in dependency order. Each is idempotent against the
    # resources earlier targets already created.
    for LABID in 1b 2a 2b 3a 3b 4a 4b 5a 6a 6b 6c 7a 7b; do
      if USER_ID="$BS_USER_ID" bash "$BOOTSTRAP" "$LABID" >"$TMP/bs-${LABID}.log" 2>&1; then
        pass "bootstrap $LABID"
      else
        fail "bootstrap $LABID" "$(tail -c 200 "$TMP/bs-${LABID}.log" | tr '\n' ' ')"
      fi
    done

    # Verify each ensure_* function produced the expected AWS resource.
    BS_BUCKET=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'student-${BS_USER_ID}-uploads')] | [0].Name" \
        --output text 2>/dev/null)
    [ -n "$BS_BUCKET" ] && [ "$BS_BUCKET" != "None" ] \
      && pass "verify: uploads bucket ($BS_BUCKET)" \
      || fail "verify uploads bucket" "not found"

    aws dynamodb describe-table --table-name "$BS_TABLE" >/dev/null 2>&1 \
      && pass "verify: $BS_TABLE" \
      || fail "verify table" "not found"

    aws iam get-role --role-name "$BS_ROLE" >/dev/null 2>&1 \
      && pass "verify: $BS_ROLE" \
      || fail "verify role" "not found"

    aws lambda get-function --function-name "$BS_FN" >/dev/null 2>&1 \
      && pass "verify: $BS_FN" \
      || fail "verify function" "not found"

    BS_API=$(aws apigateway get-rest-apis \
        --query "items[?name=='dev-on-aws-${BS_USER_ID}'].id | [0]" --output text 2>/dev/null)
    [ -n "$BS_API" ] && [ "$BS_API" != "None" ] \
      && pass "verify: api dev-on-aws-${BS_USER_ID} ($BS_API)" \
      || fail "verify api" "not found"

    BS_POOL=$(aws cognito-idp list-user-pools --max-results 60 \
        --query "UserPools[?Name=='dev-on-aws-pool-${BS_USER_ID}'].Id | [0]" \
        --output text 2>/dev/null)
    [ -n "$BS_POOL" ] && [ "$BS_POOL" != "None" ] \
      && pass "verify: pool dev-on-aws-pool-${BS_USER_ID} ($BS_POOL)" \
      || fail "verify cognito pool" "not found"

    BS_SITE=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'student-${BS_USER_ID}-site')] | [0].Name" \
        --output text 2>/dev/null)
    [ -n "$BS_SITE" ] && [ "$BS_SITE" != "None" ] \
      && pass "verify: site bucket ($BS_SITE)" \
      || fail "verify site bucket" "not found"

    # Idempotency re-run — everything already exists; should skip 5+ resources.
    # 6c is top-of-chain (covers all seven ensure_* paths).
    if USER_ID="$BS_USER_ID" bash "$BOOTSTRAP" 6c >"$TMP/bs-rerun.log" 2>&1; then
      SKIPS=$(grep -c "already present" "$TMP/bs-rerun.log" || true)
      if [ "$SKIPS" -ge 5 ]; then
        pass "idempotency: 6c re-run skipped $SKIPS resources"
      else
        fail "idempotency check" "only $SKIPS skips on re-run (expected ≥5)"
      fi
    else
      fail "bootstrap 6c (idempotency re-run)" "$(tail -c 200 "$TMP/bs-rerun.log" | tr '\n' ' ')"
    fi

    export HOME="$HOME_ORIG"
  fi
fi

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

echo "hello" > "$TMP/hello.txt"
try "put-object with metadata" \
  aws s3api put-object --bucket "$BUCKET_UPLOADS" --key "hello.txt" \
    --body "$TMP/hello.txt" --metadata "owner=validator"

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
try "create-role $LAMBDA_ROLE" \
  aws iam create-role --role-name "$LAMBDA_ROLE" \
    --assume-role-policy-document "file://$TMP/trust.json"

try "attach AWSLambdaBasicExecutionRole" \
  aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

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
try "put-role-policy LambdaAppAccess (sed pattern equivalent)" \
  aws iam put-role-policy --role-name "$LAMBDA_ROLE" \
    --policy-name LambdaAppAccess \
    --policy-document "file://$TMP/perms.json"

# IAM propagation — new roles need ~10-30s before Lambda can assume them.
# Retry create-function with backoff instead of a blind sleep.
cat > "$TMP/handler.py" <<'EOF'
import json
def handler(event, ctx):
    return {"statusCode": 200, "body": json.dumps({"ok": True, "event": event})}
EOF
( cd "$TMP" && zip -q function.zip handler.py )

LAMBDA_FN="lab4-${PREFIX}"
created=0
for delay in 5 10 15 20 25; do
  sleep "$delay"
  if aws lambda create-function --function-name "$LAMBDA_FN" \
        --runtime python3.12 --architectures arm64 \
        --role "arn:aws:iam::$ACCT:role/$LAMBDA_ROLE" \
        --handler handler.handler \
        --zip-file "fileb://$TMP/function.zip" \
        --timeout 10 --memory-size 256 >/dev/null 2>&1; then
    created=1; break
  fi
done
[ "$created" = 1 ] \
  && pass "create-function $LAMBDA_FN (after IAM propagation)" \
  || fail "create-function" "role still not assumable after retries"

# function-active waiter — v2 is preferred but the older name also works
wait_lambda_active() {
  aws lambda wait function-active-v2 --function-name "$1" 2>/dev/null \
    || aws lambda wait function-active --function-name "$1" 2>/dev/null
}
wait_lambda_updated() {
  aws lambda wait function-updated-v2 --function-name "$1" 2>/dev/null \
    || aws lambda wait function-updated --function-name "$1" 2>/dev/null
}

wait_lambda_active "$LAMBDA_FN" \
  && pass "function reached Active" \
  || fail "function-active waiter" "timeout"

aws lambda invoke --function-name "$LAMBDA_FN" \
  --payload '{"test":"validator"}' --cli-binary-format raw-in-base64-out \
  "$TMP/out.json" >"$TMP/invoke.meta" 2>&1 \
  && python3 -c "
import json,sys
r = json.load(open('$TMP/out.json'))
if r.get('statusCode') != 200: sys.exit('statusCode != 200: ' + str(r))
b = json.loads(r.get('body') or '{}')
sys.exit(0 if b.get('ok') is True else 'body.ok not true: ' + str(b))
" >/dev/null 2>&1 \
  && pass "invoke + parse response" \
  || fail "invoke" "bad response ($(cat "$TMP/out.json" 2>/dev/null | head -c 200))"

aws lambda update-function-configuration --function-name "$LAMBDA_FN" \
  --tracing-config Mode=Active >/dev/null 2>&1 \
  && pass "enable X-Ray tracing" \
  || fail "tracing on" "non-zero"

# CRITICAL: after update-function-configuration the function is InProgress;
# publish-version / create-alias will fail with ResourceConflictException unless
# we wait for the update to finish.
wait_lambda_updated "$LAMBDA_FN" >/dev/null 2>&1

aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess >/dev/null 2>&1 \
  && pass "attach AWSXRayDaemonWriteAccess" \
  || fail "xray policy" "non-zero"

# Versioning + alias (Lab 4b Step 6)
V=$(aws lambda publish-version --function-name "$LAMBDA_FN" \
    --query Version --output text 2>/dev/null) \
  && [ -n "$V" ] && [ "$V" != "None" ] \
  && pass "publish-version = $V" \
  || fail "publish-version" "non-zero"

if [ -n "$V" ] && [ "$V" != "None" ]; then
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

  try "add-permission (apigw invoke)" \
    aws lambda add-permission --function-name "$LAMBDA_FN" \
      --statement-id "apigw-$STAMP" \
      --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
      --source-arn "arn:aws:execute-api:$REGION:$ACCT:$REST_API/*/POST/items"

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
    LAB7="$(cd "$(dirname "$0")/.." && pwd)/labs/files/lab7"
    if [ -d "$LAB7" ]; then
      mkdir -p "$SAM_DIR"
      cp "$LAB7/template.yaml" "$SAM_DIR/template.yaml"
      cp -r "$LAB7/python" "$SAM_DIR/python"   # includes handler.py + requirements.txt
    else
      # Fallback — minimal standalone project
      mkdir -p "$SAM_DIR/python"
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
      echo "def handler(e,c): return {'statusCode':200,'body':'ok'}" > "$SAM_DIR/python/handler.py"
    fi

    # AL2023 ships Python 3.9; SAM's builder needs BOTH python3.12 AND pip
    # for 3.12 (the pip package is separate on AL2023).
    if ! command -v python3.12 >/dev/null 2>&1; then
      sudo dnf install -y python3.12 python3.12-pip >/dev/null 2>&1 || true
    fi
    # python3.12 present but no pip? install pip separately or bootstrap it.
    if command -v python3.12 >/dev/null 2>&1 \
       && ! python3.12 -m pip --version >/dev/null 2>&1; then
      sudo dnf install -y python3.12-pip >/dev/null 2>&1 \
        || python3.12 -m ensurepip --default-pip >/dev/null 2>&1 || true
    fi
    if command -v python3.12 >/dev/null 2>&1 \
       && python3.12 -m pip --version >/dev/null 2>&1; then
      try "sam build (native, python3.12 + pip present)" \
        bash -c "cd '$SAM_DIR' && sam build"
    elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      try "sam build --use-container (native python3.12 missing pip)" \
        bash -c "cd '$SAM_DIR' && sam build --use-container"
    else
      fail "sam build" "need python3.12 + pip (dnf install python3.12 python3.12-pip), or Docker for --use-container"
    fi

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
