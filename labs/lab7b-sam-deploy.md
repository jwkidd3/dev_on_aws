# 🔍 Lab 7b — Deploy with SAM, Trace & Clean Up

*Hands-On Lab · 55 min · CLI · Module 13 — Deployment*

## Objectives (4 min)

- Review a SAM template for the app's API + function + table tier
- `sam build` + `sam deploy --guided` into a fresh stack
- Make a code change and redeploy in place
- Verify the deployed resources through their service consoles

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - CloudFormation stack `dev-on-aws-user1` — CloudFormation derives the function, table, and API names from it, so they're unique automatically
> - The SAM artifact bucket `aws-sam-cli-managed-default-…` is created **once per account and shared** by the whole class — never delete it

## Prerequisites (4 min)

- Lab 7a complete
- SAM CLI installed (`sam --version`)
- `$POOL_ID`, `$CLIENT_ID`, `$BUCKET` exported

> **Starting fresh?** Run `bash ~/environment/dev-on-aws/bootstrap.sh 7b` (creates-or-reuses everything through Lab 6b, several minutes), then `source ~/.dev-on-aws.env` for the IDs and a fresh `$ID_TOKEN`, and skip the refresh below.

- Refresh the token so the smoke tests work:

```bash
source ~/environment/dev-on-aws/refresh-token.sh
```

## Step 1 — Review the SAM Project (8 min)

> The SAM project is already on disk. Explore it in the Cloud9 file tree:

```bash
cd ~/environment/dev-on-aws/lab7
ls -R
# template.yaml
# python/handler.py        (the X-Ray handler you copied into lab4/ in Lab 7a)
# python/requirements.txt (aws-xray-sdk — sam build installs it for the right platform)
```

> Open `template.yaml` in the editor. Notice:

- **Parameters** — pool/client IDs and bucket passed in at deploy time; no hard-coding
- **Globals** — `Tracing: Active` enables X-Ray on every function in the stack
- **ItemsTable** — a DynamoDB table with the same `pk`/`sk` shape as `Items-userN`; no `TableName`, so CloudFormation names it from the stack — unique per student
- **Api** — `HttpApi` (the cheaper, simpler API type) with a Cognito **JWT authorizer** wired from parameters and CORS handled by API Gateway
- **ItemsFn.Policies** — SAM policy templates grant scoped DDB + S3; the AWS managed `AWSXRayDaemonWriteAccess` policy lets it send traces
- **Events** — `ANY /items` and `ANY /items/{id}` route every verb to this Lambda. HTTP APIs send a different event shape (payload v2) than Lab 5a's REST API; the handler's `request_info()` reads both

## Step 2 — Build & First Deploy (7 min)

> Our Lambda is `Runtime: python3.12` on `arm64` (Graviton). `setup-cloud9.sh` installed Python 3.12 + pip, so `sam build` builds natively: it downloads the **arm64 (manylinux aarch64)** wheels for `aws-xray-sdk` and its dependencies, even though your Cloud9 instance is x86_64.

```bash
cd ~/environment/dev-on-aws/lab7

sam build

sam deploy --guided --stack-name dev-on-aws-$USER_ID --region us-east-1 \
    --parameter-overrides CognitoPoolId=$POOL_ID CognitoClientId=$CLIENT_ID UploadsBucket=$BUCKET
# The prompts are pre-filled from --parameter-overrides — press Enter to accept each
# Confirm changes before deploy: y   ·   Allow SAM CLI IAM role creation: y
# Save arguments to configuration file: y
# SAM then shows the changeset: "Deploy this changeset? [y/N]" → y
# First deploy takes ~2–3 min
```

> **Don't add `--use-container` here.** Your m5.large is x86_64 and the function is arm64, so the arm64 build image can't execute: you get `exec format error` → `Builder crashed` / `JSONDecodeError`. **`Build Failed` saying `python3.12` not found?** The setup script's Python step didn't finish: run `sudo dnf install -y python3.12 python3.12-pip` and build again.

> Creates an S3 bucket for artifacts (prefixed `aws-sam-cli-managed-default-`) on first use — acceptable in shared accounts.

## Step 3 — Smoke the New Stack (7 min)

> Derive the API URL from the stack's Outputs instead of hand-copying it from the terminal scrollback:

```bash
export API_URL=$(aws cloudformation describe-stacks \
    --stack-name dev-on-aws-$USER_ID \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue | [0]" \
    --output text)
echo "$API_URL"

curl -s -H "Authorization: $ID_TOKEN" -X POST $API_URL/items \
     -H "Content-Type: application/json" \
     -d '{"title":"sam item","price":1.23}' | jq .
curl -s -H "Authorization: $ID_TOKEN" $API_URL/items | jq .count   # 1 — a brand-new table
curl -s -o /dev/null -w "no token: %{http_code}\n" $API_URL/items  # 401 from the JWT authorizer
```

## Step 4 — Iterate (7 min)

1. Edit `python/handler.py` — e.g., add `print("v2 handler")` as the first line of `handler()`
2. `sam build && sam deploy` (no `--guided`; reuses `samconfig.toml`). Answer **y** at the changeset prompt; build + deploy takes 1–3 min
3. Call the API again and watch the logs for your new line:

```bash
curl -s -H "Authorization: $ID_TOKEN" $API_URL/items | jq .count
sam logs --stack-name dev-on-aws-$USER_ID -n ItemsFn --tail    # Ctrl-C to stop
```

## Step 5 — Verify Resources & See the Trace (7 min)

> The stack's resources are regular AWS resources visible in each service's console. Fire traffic and then confirm end-to-end via X-Ray:

1. **Lambda console** — the function SAM created (`dev-on-aws-user1-ItemsFn-…`; replace `user1` with your user ID) shows up alongside your `lab4-user1`; note the stack-generated suffix
2. **DynamoDB console** — the SAM-managed table appears with an auto-generated name
3. Fire 10 test requests:

```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code} " -H "Authorization: $ID_TOKEN" $API_URL/items
done; echo
```

4. CloudWatch → **X-Ray traces** → **Trace Map** — find your `dev-on-aws-<you>-ItemsFn-…` node: client → ItemsFn → DynamoDB / S3. There's **no API Gateway node**: HTTP APIs don't emit X-Ray segments, unlike the REST API you traced in 7a
5. **Traces** → filter `annotation.user = "<sub>" AND annotation.method = "GET"` (the `sub` from Lab 7a Step 5) — the `method` annotation now comes from the HTTP API's v2 event, same as it did from REST

## Step 6 — Tear Down (7 min)

```bash
sam delete --stack-name dev-on-aws-$USER_ID --region us-east-1
# Confirm y when prompted — SAM removes every resource in the stack.
# Re-check the Lambda / DynamoDB consoles — the SAM-managed resources are gone.
```

> Your Cognito pool, S3 buckets, and the Lab 4–6 resources (which aren't in this stack) stay put. At the end of class, `bash ~/environment/dev-on-aws/cleanup.sh` lists everything carrying your user ID; add `--delete` to remove it (Module 15).

## Success Criteria (4 min)

- ✅ `sam deploy --guided` finished and printed the `ApiUrl` output
- ✅ POST to the SAM-managed API URL returned 200 with your JWT
- ✅ Code-change redeploy completed and the new log line appears in `sam logs`
- ✅ The SAM-managed Lambda and DynamoDB table appear in their service consoles
- ✅ X-Ray trace map shows client → ItemsFn → DynamoDB (and you can say why there's no API Gateway node)
- ✅ `sam delete` removed every resource the stack created
