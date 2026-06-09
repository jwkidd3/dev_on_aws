# ⚡ Lab 4a — Lambda in the Console

*Hands-On Lab · 45 min · Console · Module 9 — Application Logic*

## Objectives (3 min)

- Create a Lambda function through the AWS Console wizard
- Edit the handler in the in-browser code editor
- Configure memory, timeout, and an environment variable
- Run a test event; read the CloudWatch log output

> Lab 4b does this same work from Cloud9 and the CLI.

## Prerequisites (3 min)

- Lab 1a complete; Labs 2a + 3a done (or run bootstrap — see below)
- AWS Console tab open

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 4a` creates-or-reuses the uploads bucket and `Items-$USER_ID` table so the handler has something to read/write.

## Step 1 — Create the Function & Role (6 min)

> **Wherever this slide shows `user1`, substitute your own user id** (`user2`, `user3`, …). The Console doesn't expand shell vars, and every lab downstream looks up `lab4-$USER_ID` and `StudentLambdaRole-$USER_ID` literally.

1. Console → **Lambda** → **Create function**
2. Choose **Author from scratch**
3. Function name: `lab4-<your-user>` (e.g., `lab4-user1`)
4. Runtime: **Python 3.12**
5. Architecture: **arm64**
- Role name: `StudentLambdaRole-<your-user>`
- Policy templates: leave empty (Lambda adds the basic execution policy for CloudWatch Logs automatically)

6. 
7. **Create function** — Lambda creates both the function and the role. Lab 4b adds DynamoDB / S3 permissions to this same role.

## Step 2 — Edit the Handler (6 min)

> The console opens at the **Code** tab with a default `lambda_function.py`. Replace its contents:

```python
import json, os

def lambda_handler(event, context):
    greeting = os.environ.get("GREETING", "Hello")
    name     = event.get("name", "World")
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message":   f"{greeting}, {name}!",
            "requestId": context.aws_request_id
        })
    }
```

> Click **Deploy** (the orange button). This uploads the edited code.

## Step 3 — Configure Memory, Timeout, Env Vars (6 min)

1. Switch to the **Configuration** tab
2. **General configuration** → Edit → Memory **256 MB**, Timeout **10 sec** → **Save**
3. **Environment variables** → Edit → Add `GREETING = Hi` → **Save**

## Step 4 — Test Event (6 min)

1. Switch to the **Test** tab
2. Event name: `hello-<your-user>`
3. Payload JSON: `{"name":"<your-user>"}` — e.g., `{"name":"user1"}`
4. Click **Test**
5. Expected response status 200; body contains `"Hi, <your-user>!"`

## Step 5 — Read the Logs (6 min)

1. **Monitor** tab → **View CloudWatch logs**
2. You should see a log group `/aws/lambda/lab4-<your-user>` with one stream
3. Open the stream; note `INIT_START`, `START`, `END`, `REPORT` lines
4. The `REPORT` line has duration, memory used, and billed ms

## Step 6 — Invoke from Cloud9 Terminal (6 min)

```bash
aws lambda invoke \
    --function-name lab4-$USER_ID \
    --payload '{"name":"Cloud9"}' \
    --cli-binary-format raw-in-base64-out \
    out.json

cat out.json
# {"statusCode":200,"body":"{\"message\":\"Hi, Cloud9!\",...}"}
```

> Refresh the logs in the console — a second stream appears.

## Success Criteria (3 min)

- ✅ Function `lab4-$USER_ID` created through the Console wizard
- ✅ Handler edited inline and deployed
- ✅ Env var `GREETING=Hi` takes effect in the response
- ✅ Test event returns 200; CloudWatch log stream visible
- ✅ CLI invoke from Cloud9 hits the same function
