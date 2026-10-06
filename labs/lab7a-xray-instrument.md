# 🔍 Lab 7a — Instrument Lambda with X-Ray

*Hands-On Lab · 45 min · Module 14 — Observability*

## Objectives (3 min)

- Package the X-Ray SDK for Lambda's runtime (Python 3.12, arm64)
- Turn on active tracing for the Lambda and the API Gateway stage
- Add annotations (`user`, `method`) and metadata
- Use the service map and **annotation filters** to find specific requests

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - Nothing new — you modify **your** `lab4-user1`, `StudentLambdaRole-user1`, and the `dev` stage of **your** API. X-Ray shows every student's services; filter on `annotation.user` to see only yours

## Prerequisites (3 min)

- Labs 4–6 complete — `lab4-$USER_ID` behind the Cognito-protected API
- Exported: `$USER_ID`, `$API_ID`, `$URL`, `$CLIENT_ID`
- Refresh your token — the one from this morning has expired:

```bash
source ~/environment/dev-on-aws/refresh-token.sh
```

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 7a` creates-or-reuses the full stack through Cognito and the Swagger import, with a fresh `$ID_TOKEN`.

## Step 1 — Package the SDK for Lambda (8 min)

> Cloud9 runs Python 3.9 on x86; your function runs **Python 3.12 on arm64**. A plain `pip install -t .` would grab x86/3.9 builds of `wrapt` (which has compiled code) and also vendor its own `botocore`, shadowing the runtime's. So ask pip for the *target* platform and skip `botocore` (Lambda already has it):

```bash
cd ~/environment/dev-on-aws/lab4
rm -rf package && pip3 install --target package --no-deps \
    --platform manylinux2014_aarch64 --python-version 3.12 \
    --implementation cp --only-binary=:all: aws-xray-sdk wrapt
ls package     # aws_xray_sdk/  wrapt/  (+ .dist-info folders)
```

## Step 2 — Swap in the Instrumented Handler (6 min)

> The X-Ray-instrumented handler is on disk at `~/environment/dev-on-aws/lab7/python/handler.py` — identical logic to Lab 4b's, plus the lines marked `# X-Ray:`. Copy it over the Lab 4 version:

```bash
cp ~/environment/dev-on-aws/lab7/python/handler.py ~/environment/dev-on-aws/lab4/handler.py
```

> Open it in the editor and find:

- `patch_all()` — auto-wraps every `boto3` call as an X-Ray subsegment
- `@xray_recorder.capture("handler")` — a named span around the handler
- **Annotations** (`user`, `method`) — indexed, so you can **filter** traces by them
- **Metadata** (`event`) — not indexed; shown when you open a trace

## Step 3 — Turn on Tracing (7 min)

```bash
aws lambda update-function-configuration --function-name lab4-$USER_ID \
    --tracing-config Mode=Active
aws lambda wait function-updated --function-name lab4-$USER_ID
aws iam attach-role-policy --role-name StudentLambdaRole-$USER_ID \
    --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
aws apigateway update-stage --rest-api-id $API_ID --stage-name dev \
    --patch-operations op=replace,path=/tracingEnabled,value=true
```

> Always `wait function-updated` between Lambda updates, or the next call hits `ResourceConflictException`.

## Step 4 — Redeploy & Fire Traffic (7 min)

```bash
cd ~/environment/dev-on-aws/lab4
rm -f function.zip && (cd package && zip -qr ../function.zip .) && zip -q function.zip handler.py
aws lambda update-function-code --function-name lab4-$USER_ID --zip-file fileb://function.zip
aws lambda wait function-updated --function-name lab4-$USER_ID
```

```bash
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -H "Authorization: $ID_TOKEN" -X POST $URL \
       -H "Content-Type: application/json" -d "{\"title\":\"t$i\",\"price\":$i}"
done; echo
curl -s -o /dev/null -w "GET list: %{http_code}\n"   -H "Authorization: $ID_TOKEN" $URL
curl -s -o /dev/null -w "GET bogus: %{http_code}\n"  -H "Authorization: $ID_TOKEN" $URL/nope
```

> Expect a row of `200`s, then `200` and `404`. A row of `401`s means the token expired — re-run `refresh-token.sh`. A `502` means the function crashed: `aws logs tail /aws/lambda/lab4-$USER_ID --since 5m`.

## Step 5 — Service Map, Traces & Annotation Filters (8 min)

1. CloudWatch console → **X-Ray traces** → **Trace Map**. Expect: client → API Gateway `dev-on-aws-<you>/dev` → `lab4-<you>` → DynamoDB / S3. Other students' services may appear too — it's one account. Focus on the nodes with **your** user in the name.
2. Click the Lambda node → response-time histogram
3. **Traces** → in the query box, filter by your annotations:
   - `annotation.method = "GET"` → just your two GETs
   - `http.status = 404` → the bogus request; open it and find the `handler` subsegment and the DynamoDB `GetItem` that returned nothing
4. Open any POST trace → **Metadata** tab on the `handler` subsegment shows the full event

> The same filter from the CLI — handy in scripts and runbooks:

```bash
SUB=$(python3 ~/environment/dev-on-aws/lab6/decode_jwt.py "$ID_TOKEN" --sub)
aws xray get-trace-summaries --start-time $(( $(date +%s) - 900 )) --end-time $(date +%s) \
    --filter-expression "annotation.user = \"$SUB\" AND annotation.method = \"POST\"" \
    --query "TraceSummaries[].Id" --output text      # one trace ID per matching POST
```

> `annotation.user` is Alice's Cognito `sub`. Filtering on it isolates *your* requests even with 25 students tracing in the same account. That's why it's an annotation (indexed), not metadata.

## Success Criteria (3 min)

- ✅ `aws-xray-sdk` + `wrapt` packaged for arm64 / Python 3.12 and deployed
- ✅ Lambda `TracingConfig.Mode = Active`, `AWSXRayDaemonWriteAccess` attached, API stage `tracingEnabled = true`
- ✅ Trace map shows API Gateway → Lambda → DynamoDB / S3
- ✅ Annotation filters (`annotation.method`, `annotation.user`) return just the matching traces
- ✅ The 404 request found and inspected in its trace
