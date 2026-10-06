# ⚡ Lab 4b — Lambda with DynamoDB, S3 & Triggers

*Hands-On Lab · 45 min · Module 9 — Application Logic*

## Objectives (3 min)

- Extend the execution role with DynamoDB + S3 permissions
- Update the function to write DDB and generate presigned URLs
- Add an S3 event trigger on the uploads bucket
- Publish a version and create an alias

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - Inline policy `LambdaAppAccess` on **your** `StudentLambdaRole-user1`
> - S3 trigger on **your** uploads bucket; version + alias `prod` on **your** `lab4-user1` (the alias name can repeat — it lives inside your function)

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
- `request_info()` normalises every way it's invoked — direct, API Gateway REST, HTTP API — into *(method, user, id)*; an **S3 event** just gets logged
- **POST** writes an object to S3, stores an `ITEM#<id>` row in DynamoDB, and returns a presigned URL; **GET** / **DELETE** read and remove items (used from Lab 6b on)
- Items are keyed `USER#<user>` — direct invokes pass `user`; behind the Cognito authorizer it becomes the signed-in user's `sub`
- Returns API-Gateway-style JSON (status, CORS headers, body)

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
    --payload "{\"user\":\"$USER_ID\",\"title\":\"first item\",\"price\":5}" \
    --cli-binary-format raw-in-base64-out out.json && cat out.json
# {"statusCode": 200, ... "body": "{\"pk\": \"USER#user1\", \"sk\": \"ITEM#…\", ... \"url\": \"https://…\"}"}
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

- A log line appears: `S3 ObjectCreated:Put: s3://student-…/incoming/test.txt`
- ⏱️ A **brand-new** notification configuration can take a few minutes to start delivering. If nothing shows after ~30 s, leave `tail` running, upload again from a second terminal (`echo again | aws s3 cp - s3://$BUCKET/incoming/test2.txt`), and give it a couple of minutes. Once active, triggers fire within seconds.
- Press **Ctrl-C** to stop following
- The trigger only fires for `incoming/`; the handler writes to `uploads/` — so it can never trigger itself in a loop

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
- ✅ Direct invoke writes an `ITEM#…` row to DDB and returns a working presigned URL
- ✅ Uploading to `incoming/` auto-triggers the function
- ✅ Version 1 published, alias `prod` points to it
