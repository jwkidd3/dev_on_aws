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

code_is() {  # code_is "desc" expected curl-args…  (retries while a fresh deployment propagates)
  local desc="$1" want="$2"; shift 2; local got="" i
  for i in 1 2 3 4 5 6; do
    got=$(curl -s -o "$TMP/http.out" -w '%{http_code}' "$@")
    [ "$got" = "$want" ] && { pass "$desc → $got"; return 0; }
    sleep 5
  done
  fail "$desc" "HTTP $got (want $want): $(head -c 140 "$TMP/http.out")"; return 1
}
# expect_denied "desc" cmd… — passes only on an AccessDenied
expect_denied() {
  local desc="$1"; shift
  local out; out=$("$@" 2>&1) && { fail "$desc" "expected AccessDenied, call succeeded"; return; }
  echo "$out" | grep -q "AccessDenied" && pass "$desc" || fail "$desc" "$(echo "$out" | tr '\n' ' ' | head -c 160)"
}
# retry_ok "desc" cmd… — IAM / S3 changes take a few seconds to apply
retry_ok() {
  local desc="$1"; shift; local i out
  for i in 1 2 3 4 5 6 7 8; do out=$("$@" 2>&1) && { pass "$desc"; return 0; }; sleep 5; done
  fail "$desc" "$(echo "$out" | tr '\n' ' ' | head -c 160)"; return 1
}
LABFILES="$(cd "$(dirname "$0")/.." && pwd)/labs/files"

# Tracked resources (for cleanup)
BUCKET_UPLOADS=""; BUCKET_SITE=""; TABLE=""; LAMBDA_ROLE=""; LAMBDA_FN=""
REST_API=""; POOL_ID=""; SAM_STACK=""; PROBE_BUCKET=""
LAB1C_ROLE=""; LAB1C_PROBE=""; LAB1C_OUT=""
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

  # --- Lab 1c role + buckets ---
  [ -n "$LAB1C_ROLE" ] && aws iam get-role --role-name "$LAB1C_ROLE" >/dev/null 2>&1 && {
    for P in S3CreateOnly AllowBucketDelete; do
      aws iam delete-role-policy --role-name "$LAB1C_ROLE" --policy-name "$P" >/dev/null 2>&1 || true
    done
    aws iam delete-role --role-name "$LAB1C_ROLE" >/dev/null 2>&1 \
      && pass "iam delete-role $LAB1C_ROLE" || fail "delete $LAB1C_ROLE" "non-zero"
  }
  for B in "$LAB1C_PROBE" "$LAB1C_OUT" "student-${PREFIX}-waiterdemo"; do
    [ -n "$B" ] && aws s3api head-bucket --bucket "$B" >/dev/null 2>&1 && aws s3 rb "s3://$B" --force >/dev/null 2>&1
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
    # clobber the operator's real env file. Pin the AWS credential/config
    # paths to the real HOME first — otherwise a laptop run (README option 2)
    # loses ~/.aws and every bootstrap call fails with "Unable to locate
    # credentials". Harmless in Cloud9, where creds come from IMDS.
    export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
    export AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
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
    # Use head-bucket against the deterministic name first — list-buckets is
    # eventually-consistent and can lag a freshly created bucket by minutes.
    BS_EXPECTED_BUCKET="student-${BS_USER_ID}-uploads-$(date +%Y%m%d)"
    if aws s3api head-bucket --bucket "$BS_EXPECTED_BUCKET" >/dev/null 2>&1; then
      BS_BUCKET="$BS_EXPECTED_BUCKET"
      pass "verify: uploads bucket ($BS_BUCKET)"
    else
      BS_BUCKET=$(aws s3api list-buckets \
          --query "Buckets[?starts_with(Name, 'student-${BS_USER_ID}-uploads')] | [0].Name" \
          --output text 2>/dev/null)
      if [ -n "$BS_BUCKET" ] && [ "$BS_BUCKET" != "None" ]; then
        pass "verify: uploads bucket ($BS_BUCKET, via list)"
      else
        BS_BUCKET=""
        fail "verify uploads bucket" "$BS_EXPECTED_BUCKET not found"
        # Diagnostic: dump the 4a log (first iteration that should have called
        # ensure_bucket) so we can see whether it ran, succeeded, or was skipped
        echo "     ┌── bs-4a.log (last 40 lines) ─────────────────"
        tail -n 40 "$TMP/bs-4a.log" 2>/dev/null | sed 's/^/     │ /'
        echo "     └──────────────────────────────────────────────"
      fi
    fi

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

    # Pool name matches bootstrap.sh ensure_cognito's canonical name
    # (same as Lab 6a's console wizard)
    BS_POOL=$(aws cognito-idp list-user-pools --max-results 60 \
        --query "UserPools[?Name=='dev-on-aws-${BS_USER_ID}'].Id | [0]" \
        --output text 2>/dev/null)
    [ -n "$BS_POOL" ] && [ "$BS_POOL" != "None" ] \
      && pass "verify: pool dev-on-aws-${BS_USER_ID} ($BS_POOL)" \
      || { BS_POOL=""; fail "verify cognito pool" "dev-on-aws-${BS_USER_ID} not found"; }

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

    # Bootstrap's Cognito user (alice, same as Lab 6a) gets through the imported API
    BS_TOKEN=$(sed -n 's/^export ID_TOKEN=//p' "$TMP/.dev-on-aws.env" | tail -1)
    BS_URL=$(sed -n 's/^export URL=//p' "$TMP/.dev-on-aws.env" | tail -1)
    code_is "bootstrap ID_TOKEN (alice) → GET /items" 200 -H "Authorization: $BS_TOKEN" "$BS_URL"

    # refresh-token.sh — sourced, re-mints ID_TOKEN into the shell + env file
    NEWTOK=$(bash -c "source '$LABFILES/refresh-token.sh' >/dev/null 2>&1; echo \"\$ID_TOKEN\"")
    [ -n "$NEWTOK" ] && python3 "$LABFILES/lab6/decode_jwt.py" "$NEWTOK" --sub >/dev/null 2>&1 \
      && grep -q "^export ID_TOKEN=$NEWTOK" "$TMP/.dev-on-aws.env" \
      && pass "refresh-token.sh re-minted ID_TOKEN" \
      || fail "refresh-token.sh" "no new token"

    # USER_ID guard — no USER_ID anywhere must refuse (LabRole would collide for everyone)
    mkdir -p "$TMP/noid"
    if HOME="$TMP/noid" USER_ID= bash "$BOOTSTRAP" 1b >/dev/null 2>&1; then
      fail "bootstrap USER_ID guard" "ran without USER_ID"
    else
      pass "bootstrap refuses to run without USER_ID"
    fi

    # Two versions of one key, so cleanup.sh must really empty a versioned bucket
    BS_BKT_NOW=$(sed -n 's/^export BUCKET=//p' "$TMP/.dev-on-aws.env" | tail -1)
    for v in 1 2; do echo "v$v" | aws s3 cp - "s3://$BS_BKT_NOW/v.txt" >/dev/null 2>&1; done
    # cleanup.sh — dry run lists, --delete removes only this user's resources
    N_LIST=$(USER_ID="$BS_USER_ID" bash "$LABFILES/cleanup.sh" 2>/dev/null | grep -c "would delete")
    [ "$N_LIST" -ge 7 ] && pass "cleanup.sh dry run lists $N_LIST resources" \
      || fail "cleanup.sh dry run" "listed $N_LIST (expected ≥7)"
    USER_ID="$BS_USER_ID" bash "$LABFILES/cleanup.sh" --delete >"$TMP/cleanup.log" 2>&1
    gone() { ! "$@" >/dev/null 2>&1; }
    LEFT=""
    gone aws lambda get-function --function-name "$BS_FN" && BS_FN="" || LEFT="$LEFT fn"
    gone aws iam get-role --role-name "$BS_ROLE" && BS_ROLE="" || LEFT="$LEFT role"
    gone aws apigateway get-rest-api --rest-api-id "$BS_API" && BS_API="" || LEFT="$LEFT api"
    gone aws cognito-idp describe-user-pool --user-pool-id "$BS_POOL" && BS_POOL="" || LEFT="$LEFT pool"
    [ "$(aws dynamodb describe-table --table-name "$BS_TABLE" --query Table.TableStatus --output text 2>/dev/null)" != "ACTIVE" ] \
      && BS_TABLE="" || LEFT="$LEFT table"
    gone aws s3api head-bucket --bucket "$BS_BUCKET" && BS_BUCKET="" || LEFT="$LEFT bucket"
    gone aws s3api head-bucket --bucket "$BS_SITE" && BS_SITE="" || LEFT="$LEFT site"
    [ -z "$LEFT" ] && pass "cleanup.sh --delete removed all bootstrap resources" \
      || fail "cleanup.sh --delete" "still present:$LEFT"

    export HOME="$HOME_ORIG"
  fi
fi

# ----- Lab 1b — boto3 install & smoke -----
step "Lab 1b — boto3 install & smoke"
if pip3 install --user --quiet boto3 >/dev/null 2>&1; then
  pass "pip3 install --user boto3"
elif python3 -c "import boto3" 2>/dev/null; then
  # e.g. Homebrew Python on a laptop refuses --user installs (PEP 668); Cloud9 doesn't
  pass "boto3 already importable (pip --user blocked on this host — fine outside Cloud9)"
else
  fail "pip3 install boto3" "non-zero and boto3 not importable"
fi

python3 -c "import boto3; boto3.client('sts').get_caller_identity()" 2>/dev/null \
  && pass "boto3 + STS from Python" \
  || fail "boto3 STS" "import or call failed"

# Real lab scripts run with the validator's synthetic USER_ID (= $PREFIX)
export USER_ID="$PREFIX"

# ----- Lab 1c — narrow role, real AccessDenied, scoped allow -----
step "Lab 1c — Lab1cRole: deny → allow → scope holds"
LAB1C_ROLE="Lab1cRole-${PREFIX}"
# Trust the account root (any principal in this account that may AssumeRole) —
# the lab trusts LabRole specifically; the validator may run as a different caller.
cat > "$TMP/trust-1c.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Principal":{"AWS":"arn:aws:iam::$ACCT:root"},"Action":"sts:AssumeRole"}]}
EOF
sed "s/ACCT/$ACCT/" "$LABFILES/lab1/trust-policy.json" | python3 -m json.tool >/dev/null 2>&1 \
  && pass "lab1/trust-policy.json renders to valid JSON" \
  || fail "lab1/trust-policy.json" "invalid after sed"
sed "s/USER/$USER_ID/" "$LABFILES/lab1/s3-create-only.json" > "$TMP/create-only.json"
try "create-role $LAB1C_ROLE" \
  aws iam create-role --role-name "$LAB1C_ROLE" --assume-role-policy-document "file://$TMP/trust-1c.json"
try "put-role-policy S3CreateOnly (real lab1/s3-create-only.json)" \
  aws iam put-role-policy --role-name "$LAB1C_ROLE" --policy-name S3CreateOnly \
    --policy-document "file://$TMP/create-only.json"

# Run a command as Lab1cRole (retrying AssumeRole through IAM propagation)
as_1c() {
  local creds="" i
  for i in 1 2 3 4 5 6 7 8; do
    creds=$(aws sts assume-role --role-arn "arn:aws:iam::$ACCT:role/$LAB1C_ROLE" \
      --role-session-name labval --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
      --output text 2>/dev/null) && [ -n "$creds" ] && break
    sleep 5
  done
  [ -z "$creds" ] && { echo "assume-role failed" >&2; return 99; }
  env -u AWS_PROFILE AWS_ACCESS_KEY_ID="$(echo "$creds" | cut -f1)" \
    AWS_SECRET_ACCESS_KEY="$(echo "$creds" | cut -f2)" \
    AWS_SESSION_TOKEN="$(echo "$creds" | cut -f3)" "$@"
}
LAB1C_PROBE="student-${PREFIX}-probe"
retry_ok "as Lab1cRole: s3 mb $LAB1C_PROBE (allowed)" as_1c aws s3 mb "s3://$LAB1C_PROBE"
expect_denied "as Lab1cRole: s3 rb → AccessDenied (no delete yet)" as_1c aws s3 rb "s3://$LAB1C_PROBE"
cat > "$TMP/allow-delete.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Action":["s3:DeleteBucket","s3:DeleteObject","s3:ListBucket"],
 "Resource":["arn:aws:s3:::student-$USER_ID-*","arn:aws:s3:::student-$USER_ID-*/*"]}]}
EOF
try "put-role-policy AllowBucketDelete" \
  aws iam put-role-policy --role-name "$LAB1C_ROLE" --policy-name AllowBucketDelete \
    --policy-document "file://$TMP/allow-delete.json"
retry_ok "as Lab1cRole: s3 rb (now allowed)" as_1c aws s3 rb "s3://$LAB1C_PROBE" \
  && LAB1C_PROBE=""
LAB1C_OUT="scratch-${PREFIX}"
try "s3 mb $LAB1C_OUT (outside prefix, as caller)" aws s3 mb "s3://$LAB1C_OUT"
expect_denied "as Lab1cRole: rb outside student-<id>-* → AccessDenied" as_1c aws s3 rb "s3://$LAB1C_OUT"
try "s3 rb $LAB1C_OUT (cleanup as caller)" aws s3 rb "s3://$LAB1C_OUT" && LAB1C_OUT=""

# ----- Lab 2a/2b — S3 -----
step "Lab 2a/2b — S3 CRUD, metadata, presigned URLs, waiters"
BUCKET_UPLOADS="student-${PREFIX}-uploads"
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

# Lab 2a Step 5 — delete creates a marker; removing the marker restores the object
aws s3api delete-object --bucket "$BUCKET_UPLOADS" --key hello.txt >/dev/null 2>&1
MARKER=$(aws s3api list-object-versions --bucket "$BUCKET_UPLOADS" --prefix hello.txt \
  --query 'DeleteMarkers[0].VersionId' --output text 2>/dev/null)
[ -n "$MARKER" ] && [ "$MARKER" != "None" ] \
  && aws s3api delete-object --bucket "$BUCKET_UPLOADS" --key hello.txt --version-id "$MARKER" >/dev/null 2>&1 \
  && aws s3api head-object --bucket "$BUCKET_UPLOADS" --key hello.txt >/dev/null 2>&1 \
  && pass "delete marker created and removed → object restored" \
  || fail "delete-marker undelete" "marker=$MARKER"

export BUCKET="$BUCKET_UPLOADS"
L2="$LABFILES/lab2"
try "lab2/seed.py" python3 "$L2/seed.py"
try "lab2/process.py (paginator)" python3 "$L2/process.py"
GET_URL=$(python3 "$L2/make_get_url.py" 300 2>/dev/null)
[ "$(curl -s "$GET_URL")" = "MESSAGE 0" ] \
  && pass "presigned GET (make_get_url.py) returns MESSAGE 0" \
  || fail "presigned GET" "body mismatch"
PUT_URL=$(python3 "$L2/make_put_url.py" 2>/dev/null)
echo "from curl" > "$TMP/note.txt"
[ "$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: text/plain' \
      --upload-file "$TMP/note.txt" "$PUT_URL")" = "200" ] \
  && pass "presigned PUT (make_put_url.py) via curl" \
  || fail "presigned PUT" "non-200"
WD=$(python3 "$L2/waiter_demo.py" 2>&1)
echo "$WD" | grep -q "NoSuchBucket" && echo "$WD" | grep -q "cleaned up" \
  && pass "lab2/waiter_demo.py (waiters + exception codes)" \
  || fail "waiter_demo.py" "$(echo "$WD" | tail -1 | head -c 160)"

# ----- Lab 3a/3b — DynamoDB -----
step "Lab 3a/3b — DynamoDB table + GSI + real lab3 scripts"
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

# Scripts read/write items.json in the cwd — run them from a scratch copy
mkdir -p "$TMP/lab3" && cp "$LABFILES"/lab3/*.py "$TMP/lab3/"
(cd "$TMP/lab3" && python3 seed.py) >/dev/null 2>&1 && [ -s "$TMP/lab3/items.json" ] \
  && pass "seed.py wrote items.json" || fail "seed.py" "no items.json"
(cd "$TMP/lab3" && python3 bulk_load.py) 2>&1 | grep -q "loaded 30 rows" \
  && pass "bulk_load.py loaded 30 rows from items.json" || fail "bulk_load.py" "did not load 30"
(cd "$TMP/lab3" && python3 get_item_client.py) 2>&1 | grep -q "^resource" \
  && pass "get_item_client.py (client vs resource)" || fail "get_item_client.py" "error"
(cd "$TMP/lab3" && python3 query_filter.py) 2>&1 | grep -q "items under" \
  && pass "query_filter.py (paginated)" || fail "query_filter.py" "error"
try "query_gsi.py" bash -c "cd '$TMP/lab3' && python3 query_gsi.py"
(cd "$TMP/lab3" && python3 update_conditional.py) 2>&1 | grep -q "updated" \
  && (cd "$TMP/lab3" && python3 update_conditional.py) 2>&1 | grep -q "ConditionalCheckFailed" \
  && pass "update_conditional.py: 1st updates, 2nd rejected" || fail "update_conditional.py" "unexpected output"
(cd "$TMP/lab3" && python3 scan_demo.py) 2>&1 | grep -q "items in" \
  && pass "scan_demo.py" || fail "scan_demo.py" "error"

# ----- Lab 4a/4b — Lambda with the REAL lab4 handler -----
step "Lab 4a/4b — Lambda role, real handler, invoke, S3 trigger"
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

# Lab 4b Step 1 exactly: render the real lambda-perms.json with sed
sed -e "s/ACCT/$ACCT/g" -e "s/USER/$USER_ID/g" "$LABFILES/lab4/lambda-perms.json" > "$TMP/perms.json"
try "put-role-policy LambdaAppAccess (rendered lab4/lambda-perms.json)" \
  aws iam put-role-policy --role-name "$LAMBDA_ROLE" \
    --policy-name LambdaAppAccess \
    --policy-document "file://$TMP/perms.json"

( cd "$LABFILES/lab4" && zip -q "$TMP/function.zip" handler.py )

LAMBDA_FN="lab4-${PREFIX}"
created=0
for delay in 5 10 15 20 25; do
  sleep "$delay"
  if aws lambda create-function --function-name "$LAMBDA_FN" \
        --runtime python3.12 --architectures arm64 \
        --role "arn:aws:iam::$ACCT:role/$LAMBDA_ROLE" \
        --handler handler.handler \
        --zip-file "fileb://$TMP/function.zip" \
        --environment "Variables={ITEMS_TABLE=$TABLE,UPLOADS_BUCKET=$BUCKET_UPLOADS}" \
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

# Lab 4b Step 3 — direct invoke writes S3 + DDB and returns a presigned URL
aws lambda invoke --function-name "$LAMBDA_FN" \
  --payload "{\"user\":\"$USER_ID\",\"title\":\"first item\",\"price\":5}" \
  --cli-binary-format raw-in-base64-out "$TMP/out.json" >/dev/null 2>&1
PRESIGNED=$(python3 -c "
import json,sys
r = json.load(open('$TMP/out.json'))
assert r.get('statusCode') == 200, r
b = json.loads(r['body']); assert b['sk'].startswith('ITEM#') and b['pk'] == 'USER#$USER_ID', b
print(b['url'])" 2>/dev/null) \
  && pass "invoke real handler → 200, ITEM# row for USER#$USER_ID" \
  || fail "invoke" "bad response ($(head -c 200 "$TMP/out.json" 2>/dev/null))"
[ -n "$PRESIGNED" ] && [ "$(curl -s "$PRESIGNED")" = "first item" ] \
  && pass "handler's presigned URL serves the object" \
  || fail "presigned URL from handler" "body mismatch"

# Lab 4b Steps 4–5 — S3 trigger using the real notify.json
try "add-permission (s3 invoke)" \
  aws lambda add-permission --function-name "$LAMBDA_FN" --statement-id AllowS3Invoke \
    --action lambda:InvokeFunction --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$BUCKET_UPLOADS"
sed -e "s/ACCT/$ACCT/g" -e "s/USER/$USER_ID/g" "$LABFILES/lab4/notify.json" > "$TMP/notify.json"
try "put-bucket-notification-configuration (rendered notify.json)" \
  aws s3api put-bucket-notification-configuration --bucket "$BUCKET_UPLOADS" \
    --notification-configuration "file://$TMP/notify.json"
# A brand-new notification config can take a few minutes to start delivering
# (observed in this account) — re-upload every minute, give up after ~6 min.
TRIG=""
for i in $(seq 1 36); do
  [ $((i % 6)) -eq 1 ] && echo "hello trigger" | aws s3 cp - "s3://$BUCKET_UPLOADS/incoming/test-$i.txt" >/dev/null 2>&1
  sleep 10
  TRIG=$(aws logs filter-log-events --log-group-name "/aws/lambda/$LAMBDA_FN" \
    --filter-pattern '"S3 ObjectCreated"' --query 'events[0].message' --output text 2>/dev/null)
  [ -n "$TRIG" ] && [ "$TRIG" != "None" ] && break
done
[ -n "$TRIG" ] && [ "$TRIG" != "None" ] \
  && pass "S3 upload to incoming/ triggered the function (after $((i*10))s)" \
  || fail "S3 trigger" "no S3 log line within 6 min"

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

  URL="https://$REST_API.execute-api.$REGION.amazonaws.com/dev/items"
  code_is "curl POST /items (no auth yet)" 200 -X POST "$URL" \
    -H "Content-Type: application/json" -d '{"title":"from cloud9","price":1}'
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

      # Lab 6b Steps 5–6 — Swagger overwrite import using the real lab file
      SWAGGER_SRC="$(cd "$(dirname "$0")/.." && pwd)/labs/files/lab6/swagger.json"
      if [ ! -f "$SWAGGER_SRC" ]; then
        fail "swagger.json present" "$SWAGGER_SRC not found"
      else
        sed -e "s/__ACCT__/$ACCT/g" \
            -e "s/__POOL_ID__/$POOL_ID/g" \
            -e "s|__LAMBDA_ARN__|arn:aws:lambda:$REGION:$ACCT:function:$LAMBDA_FN|g" \
            -e "s/__USER_ID__/$PREFIX/g" \
            "$SWAGGER_SRC" > "$TMP/swagger-filled.json"
        try "put-rest-api --mode overwrite (swagger import)" \
          aws apigateway put-rest-api --rest-api-id "$REST_API" \
              --mode overwrite --body "fileb://$TMP/swagger-filled.json"

        ID_RES=$(aws apigateway get-resources --rest-api-id "$REST_API" \
            --query "items[?path=='/items/{id}'].id | [0]" --output text 2>/dev/null)
        [ -n "$ID_RES" ] && [ "$ID_RES" != "None" ] \
          && pass "import created /items/{id}" \
          || fail "import /items/{id}" "resource not found after import"

        ITEMS_RES=$(aws apigateway get-resources --rest-api-id "$REST_API" \
            --query "items[?path=='/items'].id | [0]" --output text 2>/dev/null)
        aws apigateway get-method --rest-api-id "$REST_API" \
            --resource-id "$ITEMS_RES" --http-method OPTIONS >/dev/null 2>&1 \
          && pass "import created OPTIONS (CORS mock) on /items" \
          || fail "import OPTIONS /items" "method not found"

        POST_AUTH=$(aws apigateway get-method --rest-api-id "$REST_API" \
            --resource-id "$ITEMS_RES" --http-method POST \
            --query authorizationType --output text 2>/dev/null)
        [ "$POST_AUTH" = "COGNITO_USER_POOLS" ] \
          && pass "imported POST is Cognito-protected" \
          || fail "imported POST auth" "authorizationType=$POST_AUTH"

        VALIDATORS=$(aws apigateway get-request-validators --rest-api-id "$REST_API" \
            --query "length(items)" --output text 2>/dev/null)
        [ "${VALIDATORS:-0}" -ge 1 ] \
          && pass "import created request validator" \
          || fail "import request validator" "none found"

        try "add-permission (swagger wildcard)" \
          aws lambda add-permission --function-name "$LAMBDA_FN" \
            --statement-id "swagger-$STAMP" \
            --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
            --source-arn "arn:aws:execute-api:$REGION:$ACCT:$REST_API/*"

        try "redeploy stage=dev after import" \
          aws apigateway create-deployment --rest-api-id "$REST_API" --stage-name dev
        # API Gateway nodes switch to a new deployment gradually, and not uniformly
        # per route — until then some requests still hit the pre-import API.
        # Probe every route type each round; old vs new answers differ:
        #   GET /items (no token)       old 403 (no method)   new 401
        #   POST /items (no token)      old 200 (no auth)     new 401
        #   OPTIONS /items/x            old 403 (no resource) new 200
        #   401 carries CORS header     old no                new yes
        # Require 10 consecutive all-new rounds (max ~6 min).
        URL="https://$REST_API.execute-api.$REGION.amazonaws.com/dev/items"
        ok_run=0
        for i in $(seq 1 120); do
          g=$(curl -s -D "$TMP/g.h" -o /dev/null -w '%{http_code}' "$URL")
          p=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Content-Type: application/json" -d '{"title":"probe","price":0}')
          o=$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$URL/x")
          if [ "$g$p$o" = "401401200" ] && grep -qi '^access-control-allow-origin' "$TMP/g.h"; then
            ok_run=$((ok_run+1)); else ok_run=0; fi
          [ "$ok_run" -ge 10 ] && break; sleep 3
        done
        [ "$ok_run" -ge 10 ] && pass "new deployment serving consistently on every route (after ~$((i*3))s)" \
          || fail "deployment settle" "old and new deployments still interleaved after 6 min"
      fi
    fi
  fi
fi

# ----- Lab 6b/6c — end-to-end through the Cognito-protected API -----
if [ $QUICK -eq 0 ] && [ -n "${AUTH:-}" ] && [ -n "$REST_API" ]; then
  step "Lab 6b/6c — authorizer, CRUD, validation, CORS, per-user isolation"
  H="Authorization: $AUTH"
  code_is "no token → 401" 401 "$URL"
  curl -s -D - -o /dev/null "$URL" | grep -qi '^access-control-allow-origin' \
    && pass "gateway 401 carries CORS header (gateway-responses)" \
    || fail "gateway-response CORS" "no Access-Control-Allow-Origin on 401"
  code_is "malformed token → 401" 401 -H "Authorization: not.a.real.jwt" "$URL"
  NEW_ID=$(curl -s -H "$H" -X POST "$URL" -H "Content-Type: application/json" \
      -d '{"title":"from swagger","price":4.5}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)
  [ -n "$NEW_ID" ] && pass "POST /items with token → id $NEW_ID" || fail "POST /items" "no id"
  code_is "GET /items/{id}" 200 -H "$H" "$URL/$NEW_ID"
  code_is "DELETE /items/{id}" 200 -H "$H" -X DELETE "$URL/$NEW_ID"
  code_is "GET after delete → 404" 404 -H "$H" "$URL/$NEW_ID"
  code_is "POST without price → 400 (request validator)" 400 -H "$H" -X POST "$URL" \
    -H "Content-Type: application/json" -d '{"title":"no price"}'
  curl -s -i -X OPTIONS "$URL" | grep -qi '^access-control-allow-methods' \
    && pass "OPTIONS preflight (mock) returns CORS headers" \
    || fail "OPTIONS preflight" "no Access-Control-Allow-Methods"
  curl -s -i -X OPTIONS "$URL/anything" -H "Origin: http://example.com" \
      -H "Access-Control-Request-Method: DELETE" | grep -qi '^access-control-allow-methods:.*DELETE' \
    && pass "OPTIONS preflight on /items/{id} allows DELETE" \
    || fail "OPTIONS /items/{id}" "no DELETE in Access-Control-Allow-Methods"

  # Per-user isolation: Alice has an item, Bob sees none of them
  curl -s -o /dev/null -H "$H" -X POST "$URL" -H "Content-Type: application/json" \
    -d '{"title":"alice item","price":2}'
  aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username bob@example.com \
    --user-attributes Name=email,Value=bob@example.com Name=email_verified,Value=true \
    --message-action SUPPRESS >/dev/null 2>&1
  aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" --username bob@example.com \
    --password 'Tr0picalStorm!' --permanent >/dev/null 2>&1
  BOB=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CLIENT_ID" \
    --auth-parameters 'USERNAME=bob@example.com,PASSWORD=Tr0picalStorm!' \
    --query AuthenticationResult.IdToken --output text 2>/dev/null)
  A_N=$(curl -s -H "$H" "$URL" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])' 2>/dev/null)
  B_N=$(curl -s -H "Authorization: $BOB" "$URL" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])' 2>/dev/null)
  [ "${A_N:-0}" -ge 1 ] && [ "$B_N" = "0" ] \
    && pass "isolation: validator sees $A_N item(s), bob sees 0" \
    || fail "per-user isolation" "validator=$A_N bob=$B_N"
  SUBS=$(python3 "$LABFILES/lab6/decode_jwt.py" "$AUTH" "$BOB" --sub 2>/dev/null | sort -u | wc -l)
  [ "$SUBS" -eq 2 ] && pass "decode_jwt.py --sub: two distinct subs" || fail "decode_jwt.py" "subs=$SUBS"

  # Lab 6c — site bucket + generated config.js + browser-style Cognito sign-in
  BUCKET_SITE="student-${PREFIX}-site"
  if aws s3 mb "s3://$BUCKET_SITE" >/dev/null 2>&1 \
     && aws s3api put-public-access-block --bucket "$BUCKET_SITE" --public-access-block-configuration \
          "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
     && aws s3 website "s3://$BUCKET_SITE/" --index-document index.html --error-document error.html \
     && sed "s|BUCKET|$BUCKET_SITE|g" "$LABFILES/lab6/site-policy.json" > "$TMP/site-policy.json" \
     && retry_ok "put-bucket-policy (public read)" aws s3api put-bucket-policy \
          --bucket "$BUCKET_SITE" --policy "file://$TMP/site-policy.json"; then
    mkdir -p "$TMP/web" && cp "$LABFILES"/lab6/web/* "$TMP/web/"
    echo "window.APP_CONFIG={region:'us-east-1',clientId:'$CLIENT_ID',apiUrl:'$URL'};" > "$TMP/web/config.js"
    try "s3 sync web/ (+ config.js)" aws s3 sync "$TMP/web" "s3://$BUCKET_SITE/" --delete
    SITE_URL="http://$BUCKET_SITE.s3-website-us-east-1.amazonaws.com"
    code_is "site index.html served" 200 "$SITE_URL/"
    code_is "site config.js served" 200 "$SITE_URL/config.js"
  else
    fail "site bucket" "create/configure failed"
  fi
  # The page signs in by POSTing to Cognito's public InitiateAuth endpoint — same call, from curl
  curl -s -D "$TMP/cog.h" -o "$TMP/cog.json" -X POST "https://cognito-idp.$REGION.amazonaws.com/" \
    -H "Origin: $SITE_URL" -H "Content-Type: application/x-amz-json-1.1" \
    -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
    -d "{\"AuthFlow\":\"USER_PASSWORD_AUTH\",\"ClientId\":\"$CLIENT_ID\",\"AuthParameters\":{\"USERNAME\":\"validator@example.com\",\"PASSWORD\":\"Tr0picalStorm!\"}}"
  grep -q IdToken "$TMP/cog.json" && grep -qi '^access-control-allow-origin' "$TMP/cog.h" \
    && pass "browser-style InitiateAuth (index.html signIn) → IdToken + CORS" \
    || fail "browser sign-in" "$(head -c 160 "$TMP/cog.json")"

  # ----- Lab 7a — X-Ray SDK packaged for arm64 / py3.12, instrumented handler -----
  step "Lab 7a — X-Ray packaging, tracing, annotation filter"
  rm -rf "$TMP/pkg"
  if python3 -m pip install --quiet --target "$TMP/pkg" --no-deps \
       --platform manylinux2014_aarch64 --python-version 3.12 \
       --implementation cp --only-binary=:all: aws-xray-sdk wrapt >/dev/null 2>&1; then
    pass "pip --platform manylinux2014_aarch64 aws-xray-sdk wrapt"
    cp "$LABFILES/lab7/python/handler.py" "$TMP/pkg/handler.py"
    rm -f "$TMP/fn7a.zip"; (cd "$TMP/pkg" && zip -qr "$TMP/fn7a.zip" .)
    try "update-function-code (instrumented handler + SDK)" \
      aws lambda update-function-code --function-name "$LAMBDA_FN" --zip-file "fileb://$TMP/fn7a.zip"
    wait_lambda_updated "$LAMBDA_FN" >/dev/null 2>&1
    try "API stage tracingEnabled=true" \
      aws apigateway update-stage --rest-api-id "$REST_API" --stage-name dev \
        --patch-operations op=replace,path=/tracingEnabled,value=true
    # A stage update re-propagates; for a short while some requests can still hit
    # the previous (pre-import, unauthenticated) deployment. Let it settle.
    sleep 60
    code_is "instrumented handler: POST via API" 200 -H "$H" -X POST "$URL" \
      -H "Content-Type: application/json" -d '{"title":"traced","price":3}'
    code_is "instrumented handler: GET bogus id → 404" 404 -H "$H" "$URL/nope"
    SUB=$(python3 "$LABFILES/lab6/decode_jwt.py" "$AUTH" --sub 2>/dev/null)
    NTR=0
    for i in $(seq 1 30); do
      sleep 10
      NTR=$(aws xray get-trace-summaries --start-time $(( $(date +%s) - 900 )) --end-time "$(date +%s)" \
        --filter-expression "annotation.user = \"$SUB\" AND annotation.method = \"POST\"" \
        --query "TraceSummaries[].Id" --output text 2>/dev/null | wc -w | tr -d ' ')
      # (count IDs, not length() — the CLI paginates and prints one length per page)
      [ "${NTR:-0}" -ge 1 ] 2>/dev/null && break
    done
    [ "${NTR:-0}" -ge 1 ] 2>/dev/null \
      && pass "X-Ray annotation filter finds $NTR POST trace(s) for this user" \
      || fail "X-Ray annotation filter" "no traces within 5 min"
  else
    fail "pip --platform install" "aws-xray-sdk/wrapt for arm64 py3.12"
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

    if [ -n "${AUTH:-}" ]; then
      SAM_URL=$(aws cloudformation describe-stacks --stack-name "$SAM_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue | [0]" --output text 2>/dev/null)
      code_is "SAM HttpApi: no token → 401" 401 "$SAM_URL/items"
      SAM_ID=$(curl -s -H "Authorization: $AUTH" -X POST "$SAM_URL/items" \
          -H "Content-Type: application/json" -d '{"title":"sam item","price":1.23}' \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)
      [ -n "$SAM_ID" ] && pass "SAM HttpApi: POST /items → id $SAM_ID (v2 event parsed)" \
        || fail "SAM POST /items" "no id"
      code_is "SAM HttpApi: GET /items/{id}" 200 -H "Authorization: $AUTH" "$SAM_URL/items/$SAM_ID"
      code_is "SAM HttpApi: DELETE /items/{id}" 200 -H "Authorization: $AUTH" -X DELETE "$SAM_URL/items/$SAM_ID"
      PRE=$(curl -s -D - -o /dev/null -X OPTIONS "$SAM_URL/items" -H "Origin: http://example.com" \
        -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: authorization,content-type")
      echo "$PRE" | grep -qi '^access-control-allow-origin' \
        && pass "SAM HttpApi: CORS preflight answered before the authorizer" \
        || fail "SAM CORS preflight" "$(echo "$PRE" | head -1)"
    fi
  fi
fi

# cleanup() is called via trap on EXIT
