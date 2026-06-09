# 🔍 Lab 7a — Instrument Lambda with X-Ray

*Hands-On Lab · 45 min · Module 14 — Observability*

## Objectives (3 min)

- Add the X-Ray SDK to the Lambda package
- Turn on active tracing on the Lambda and API Gateway stage
- Add annotations (`user`, `method`) and metadata
- Grant the X-Ray daemon write permission

## Prerequisites (3 min)

- Labs 4a–4b, 5a, 6a–6c complete
- Function `lab4-$USER_ID` deployed, API live
- Exported: `$USER_ID`, `$API_ID`, `$URL`, `$ID_TOKEN`

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 7a` creates-or-reuses the full stack through Cognito so you can instrument and fire traffic immediately.

## Step 1 — Add the SDK (8 min)

```bash
# Your Lab 4b handler lives here
cd ~/environment/dev-on-aws/lab4
ls handler.py   # confirm file exists from Lab 4b

pip install aws-xray-sdk -t .       # vendor into the package
echo "aws-xray-sdk" > requirements.txt
```

## Step 2 — Swap in the Instrumented Handler (7 min)

> The X-Ray-instrumented handler is already on disk at `~/environment/dev-on-aws/lab7/python/handler.py`. Overwrite the Lab 4 version with it:

```bash
cp ~/environment/dev-on-aws/lab7/python/handler.py \
   ~/environment/dev-on-aws/lab4/handler.py
```

> Open either file in the editor to read. Highlights:

- `patch_all()` — auto-wraps every `boto3` call as an X-Ray subsegment
- `@xray_recorder.capture("handler")` — adds a named span for the handler itself
- **Annotations** (`user`, `method`) — indexed, filterable from the X-Ray console
- **Metadata** (`event`) — not indexed; shown inline when you open a trace

## Step 3 — Turn on Tracing (7 min)

```bash
aws lambda update-function-configuration \
    --function-name lab4-$USER_ID \
    --tracing-config Mode=Active
aws lambda wait function-updated --function-name lab4-$USER_ID

aws iam attach-role-policy \
    --role-name StudentLambdaRole-$USER_ID \
    --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess

aws apigateway update-stage \
    --rest-api-id $API_ID --stage-name dev \
    --patch-operations op=replace,path=/tracingEnabled,value=true
```

> Always `wait function-updated` between Lambda updates or the next call hits `ResourceConflictException`.

## Step 4 — Redeploy & Fire (7 min)

```bash
cd ~/environment/dev-on-aws/lab4
# Zip the handler + every vendored dependency pip just installed.
# Exclude packaging metadata and any local artefacts (test output, policy JSON).
zip -qr function.zip . \
    -x '*.dist-info/*' '__pycache__/*' \
       'out.json' 'notify.json' 'lambda-perms.json' 'requirements.txt'

aws lambda update-function-code \
    --function-name lab4-$USER_ID \
    --zip-file fileb://function.zip
aws lambda wait function-updated --function-name lab4-$USER_ID

for i in $(seq 1 20); do
  curl -s -H "Authorization: $ID_TOKEN" -X POST $URL \
       -H "Content-Type: application/json" \
       -d "{\"title\":\"t$i\",\"price\":$i.00}" > /dev/null
done
```

## Step 5 — First Look at X-Ray (7 min)

1. CloudWatch console → **X-Ray traces** → **Service map**
2. Should appear: client → API Gateway → Lambda → DynamoDB / S3
3. Click Lambda node → see response-time histogram
4. Click a trace → see segments and subsegments

> Lab 7b redeploys this same handler via SAM and confirms the trace map end-to-end.

## Success Criteria (3 min)

- ✅ `aws-xray-sdk` packaged into the deploy artifact
- ✅ Lambda `TracingConfig.Mode = Active`
- ✅ `AWSXRayDaemonWriteAccess` attached to the role
- ✅ API GW stage `tracingEnabled = true`
- ✅ X-Ray console shows at least one end-to-end trace
