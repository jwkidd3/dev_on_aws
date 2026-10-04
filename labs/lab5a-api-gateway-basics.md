# 🔌 Lab 5a — API Gateway in the Console

*Hands-On Lab · 45 min · Console · Module 10 — APIs*

## Objectives (3 min)

- Build a REST API through the Console wizard
- Add a resource and a POST method with Lambda proxy integration
- Use the built-in **Test** console to call the method
- Deploy to a `dev` stage and hit it from Cloud9

> Lab 6b adds a Cognito JWT authorizer on top of this same API; request validation and CORS come with the Swagger import there.

## Prerequisites (3 min)

- Lab 4b complete — `lab4-$USER_ID` runs `handler.handler`
- AWS Console tab open

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 5a` creates-or-reuses the bucket, table, role, and Lambda so this lab has a backend to proxy.

## Step 1 — Create the REST API (6 min)

1. Console → **API Gateway** → **Create API**
2. Pick **REST API** → **Build**
3. New API, Name: `dev-on-aws-<your-user>` (e.g., `dev-on-aws-user1`). **Use your own user id** — Lab 5a Step 6 queries for this exact name later.
4. Endpoint type: **Regional**
5. **Create API**

## Step 2 — Add /items Resource (5 min)

1. Left tree → **/** is selected → **Create resource**
2. Resource name: `items` → **Create resource**
3. With `/items` selected → **Create method**
4. Method type: **POST**

## Step 3 — Wire Lambda Proxy (5 min)

1. Integration type: **Lambda function**
2. Toggle **Lambda proxy integration** → ON
3. Lambda function: `lab4-<your-user>` — check the name carefully; the dropdown lists **every** student's function in this shared account
4. **Create method** — accept the "add invoke permission" prompt
5. You should see the method diagram: Client → Method Request → Lambda → Method Response

## Step 4 — Test from the Console (5 min)

1. With POST selected → **Test** tab
2. Request body:

```json
{"title":"from the console","price":3.5}
```

3. **Test**
4. Status 200; the body holds the new item — `"pk": "USER#anonymous"` (no authorizer yet), an `ITEM#…` key, and a presigned `url`
5. Logs panel at the bottom shows the full request/response trace — read it

## Step 5 — Deploy to a Stage (5 min)

1. Top-right → **Deploy API**
2. Stage: `*New stage*` → name: `dev`
3. **Deploy**
4. Note the **Invoke URL** pattern: `https://<API_ID>.execute-api.us-east-1.amazonaws.com/dev`

## Step 6 — Capture the IDs for Downstream Labs (5 min)

```bash
API_ID=$(aws apigateway get-rest-apis --output text \
    --query "items[?name=='dev-on-aws-$USER_ID'].id | [0]")
ITEMS_ID=$(aws apigateway get-resources --rest-api-id $API_ID --output text \
    --query "items[?path=='/items'].id | [0]")
LAMBDA_ARN=$(aws lambda get-function --function-name lab4-$USER_ID \
    --query Configuration.FunctionArn --output text)
for v in API_ID ITEMS_ID LAMBDA_ARN; do echo "export $v=${!v}" >> ~/.dev-on-aws.env; done
source ~/.dev-on-aws.env && echo "API_ID=$API_ID ITEMS_ID=$ITEMS_ID"
```

> `| [0]` guarantees a single ID even if a duplicate API name ever exists. Labs 6b / 7a reference `$API_ID`, `$ITEMS_ID`, `$LAMBDA_ARN` (and `$ACCT` from Lab 1b).

## Step 7 — Call It from Cloud9 (5 min)

```bash
# $API_ID was exported in Step 6 and is now live in this shell
URL="https://$API_ID.execute-api.us-east-1.amazonaws.com/dev/items"
echo "export URL=$URL" >> ~/.dev-on-aws.env
source ~/.dev-on-aws.env

curl -i -X POST $URL \
     -H "Content-Type: application/json" \
     -d '{"title":"from cloud9","price":1}'
```

> Expect HTTP 200 and the new item as JSON. Anyone with this URL can call it right now — Lab 6b locks it down with Cognito.

## Success Criteria (3 min)

- ✅ REST API `dev-on-aws-$USER_ID` created via Console wizard
- ✅ POST /items wired to `lab4-$USER_ID` with proxy integration
- ✅ Console **Test** returns 200 with a full request trace
- ✅ `dev` stage deployed; invoke URL works from Cloud9 `curl`
- ✅ `$API_ID`, `$ITEMS_ID`, `$LAMBDA_ARN`, `$URL` exported
