# 🔍 Lab 7b — Full App with SAM

*Hands-On Lab · 55 min · Module 13 — Deployment*

## Objectives (4 min)

- Review a SAM template that covers the whole app
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
- `$POOL_ID`, `$CLIENT_ID`, `$BUCKET` exported; refresh the token so the smoke tests work:

```bash
source ~/environment/dev-on-aws/refresh-token.sh
```

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 7b` creates-or-reuses the user pool, client, and uploads bucket the SAM template references.

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
- **ItemsFn.Policies** — SAM-managed policy templates grant scoped DDB + S3 + X-Ray
- **Events** — `ANY /items` and `ANY /items/{id}` route every verb to this Lambda. HTTP APIs send a different event shape (payload v2) than Lab 5a's REST API; the handler's `request_info()` reads both

## Step 2 — Build & First Deploy (7 min)

> Our Lambda's `Runtime: python3.12`. `--use-container` builds inside AWS's official Python 3.12 Docker image, so it matches Lambda exactly. That's the reliable path, and the 100 GB disk from Lab 1a's setup script leaves room for the image.

```bash
cd ~/environment/dev-on-aws/lab7

sam build --use-container

sam deploy --guided --stack-name dev-on-aws-$USER_ID --region us-east-1 \
    --parameter-overrides CognitoPoolId=$POOL_ID CognitoClientId=$CLIENT_ID UploadsBucket=$BUCKET
# The prompts are pre-filled from --parameter-overrides — press Enter to accept each
# Confirm changes before deploy: y   ·   Allow SAM CLI IAM role creation: y
# Save arguments to configuration file: y
```

> **Docker not working?** `setup-cloud9.sh` also installed Python 3.12 + pip, so plain `sam build` (without `--use-container`) works too. If `docker ps` says *permission denied*, you skipped the reboot after the setup script; run `sudo reboot`.

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

1. Edit `python/handler.py` — e.g., add a new log line or annotation
2. `sam build --use-container && sam deploy` (no `--guided`; reuses `samconfig.toml`)
3. Change takes ~30 s to apply
4. Invoke again, confirm new behavior in CloudWatch logs

## Step 5 — Verify Resources & See the Trace (7 min)

> The stack's resources are regular AWS resources visible in each service's console. Fire traffic and then confirm end-to-end via X-Ray:

1. **Lambda console** — the function SAM created shows up alongside `lab4-$USER_ID`; note the stack-generated suffix in its name
2. **DynamoDB console** — the SAM-managed table appears with an auto-generated name
3. Fire 10 test requests against `$API_URL/items`
4. CloudWatch → **X-Ray traces** → **Trace Map** — confirm: client → API GW → ItemsFn → DynamoDB
5. **Traces** → filter `annotation.method = "POST"` — the `method` annotation now comes from the HTTP API's v2 event, same as it did from REST

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
- ✅ Code-change redeploy completed in < 1 min with observable difference
- ✅ The SAM-managed Lambda and DynamoDB table appear in their service consoles
- ✅ X-Ray service map shows the full request path
- ✅ `sam delete` removed every resource the stack created
