# ⚡ Lab 4b — Lambda with DynamoDB, S3 & Triggers

*Hands-On Lab · 45 min · Module 9 — Application Logic*

## Objectives (3 min)

- Extend the execution role with DynamoDB + S3 permissions
- Update the function to write DDB and generate presigned URLs
- Add an S3 event trigger on the uploads bucket
- Publish a version and create an alias

## Prerequisites (3 min)

- Lab 4a complete — function `lab4-$USER_ID` deployed
- Bucket `student-$USER_ID-uploads-…` from Lab 2a still exists
- Table `Items-$USER_ID` from Lab 3
- Exported: `$USER_ID`, `$ACCT`, `$BUCKET`

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 4b` creates-or-reuses the bucket, table, role, and function so triggers have something to wire up.

## Step 1 — Grant DDB + S3 (6 min)

> The policy template at `~/environment/dev-on-aws/lab4/lambda-perms.json` uses `ACCT` and `USER` placeholders. Render a copy with your real values, then attach:

```bash
cd ~/environment/dev-on-aws/lab4

sed -e "s/ACCT/$ACCT/g" -e "s/USER/$USER_ID/g" \
    lambda-perms.json > /tmp/lambda-perms.json

aws iam put-role-policy \
    --role-name StudentLambdaRole-$USER_ID \
    --policy-name LambdaAppAccess \
    --policy-document file:///tmp/lambda-perms.json
```

## Step 2 — Review the Updated Handler (6 min)

> Open `~/environment/dev-on-aws/lab4/handler.py` in the editor. Key things to notice:

- Clients created at module scope — outside the handler, so they're reused across warm invocations
- Reads config from env vars (`ITEMS_TABLE`, `UPLOADS_BUCKET`) — no hard-coded names
- Writes the object to S3 and records a DynamoDB row with the presigned URL
- Returns API-Gateway-style JSON (status + body)

## Step 3 — Redeploy with New Env Vars (6 min)

> Lab 4a created the function with the default `lambda_function.lambda_handler` entrypoint. Our zip holds `handler.py` with `def handler(…)` — so the handler setting must change to `handler.handler` or every invoke returns `Runtime.ImportModuleError`. Also: each `update-*` puts the function in *InProgress*; wait for it to settle before firing the next or AWS raises `ResourceConflictException`.

```bash
cd ~/environment/dev-on-aws/lab4
zip -r function.zip handler.py

aws lambda update-function-code \
    --function-name lab4-$USER_ID \
    --zip-file fileb://function.zip
aws lambda wait function-updated --function-name lab4-$USER_ID

aws lambda update-function-configuration \
    --function-name lab4-$USER_ID \
    --handler handler.handler \
    --environment "Variables={ITEMS_TABLE=Items-$USER_ID,UPLOADS_BUCKET=$BUCKET}"
aws lambda wait function-updated --function-name lab4-$USER_ID

aws lambda invoke --function-name lab4-$USER_ID \
    --payload "{\"user\":\"$USER_ID\"}" \
    --cli-binary-format raw-in-base64-out out.json && cat out.json
```

## Step 4 — Add the S3 Trigger (6 min)

```bash
aws lambda add-permission \
    --function-name lab4-$USER_ID \
    --statement-id AllowS3Invoke \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::$BUCKET
```

> The notification config at `~/environment/dev-on-aws/lab4/notify.json` also uses `ACCT` and `USER` placeholders. Render and apply:

```bash
sed -e "s/ACCT/$ACCT/g" -e "s/USER/$USER_ID/g" \
    ~/environment/dev-on-aws/lab4/notify.json > /tmp/notify.json

aws s3api put-bucket-notification-configuration \
    --bucket $BUCKET \
    --notification-configuration file:///tmp/notify.json
```

## Step 5 — Fire & Observe (6 min)

```bash
echo "hello trigger" | aws s3 cp - s3://$BUCKET/incoming/test.txt
aws logs tail /aws/lambda/lab4-$USER_ID --follow
```

- Look for a new log stream within ~5 seconds
- The event payload in the logs includes the S3 object key

## Step 6 — Version & Alias (6 min)

```bash
# Capture the version number publish-version returns
VER=$(aws lambda publish-version \
        --function-name lab4-$USER_ID \
        --description "lab4b-s3-trigger" \
        --query Version --output text)
echo "published version $VER"

aws lambda create-alias \
    --function-name lab4-$USER_ID \
    --name prod \
    --function-version $VER
```

> Version numbering is sequential per function; the first `publish-version` returns `1`, the second `2`, and so on. Capturing it from the command output avoids guessing.

## Success Criteria (3 min)

- ✅ Inline policy `LambdaAppAccess` attached to the role
- ✅ Direct invoke writes to DDB and returns a working presigned URL
- ✅ Uploading to `incoming/` auto-triggers the function
- ✅ Version 1 published, alias `prod` points to it
