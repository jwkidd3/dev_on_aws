# 🔌 Lab 5a — API Gateway in the Console

*Hands-On Lab · 45 min · Console · Module 10 — APIs*

## Objectives (3 min)

- Build a REST API through the Console wizard
- Add a resource and a POST method with Lambda proxy integration
- Use the built-in **Test** console to call the method
- Deploy to a `dev` stage and hit it from Cloud9

> Lab 6b adds a Cognito JWT authorizer on top of this same API; request validation and CORS come with the Swagger import there.

## Prerequisites (3 min)

- Lab 4a or 4b complete — `lab4-$USER_ID` exists
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
3. Lambda function: `lab4-<your-user>` (the one you created in Lab 4a)
4. **Create method** — accept the "add invoke permission" prompt
5. You should see the method diagram: Client → Method Request → Lambda → Method Response

## Step 4 — Test from the Console (5 min)

1. With POST selected → **Test** tab
```json
{"name":"API Gateway"}
```

2. Request body:
3. **Test**
4. Scroll right — Status 200, body contains your greeting
5. Logs panel at the bottom shows the full request/response trace — read it

## Step 5 — Deploy to a Stage (5 min)

1. Top-right → **Deploy API**
2. Stage: `*New stage*` → name: `dev`
3. **Deploy**
4. Note the **Invoke URL** pattern: `https://<API_ID>.execute-api.us-east-1.amazonaws.com/dev`

## Step 6 — Capture the IDs for Downstream Labs (5 min)

```bash
API_ID=$(aws apigateway get-rest-apis \
    --query "items[?name=='dev-on-aws-$USER_ID'].id" -o text)
ITEMS_ID=$(aws apigateway get-resources --rest-api-id $API_ID \
    --query "items[?path=='/items'].id" -o text)
ACCT=$(aws sts get-caller-identity --query Account -o text)
LAMBDA_ARN=$(aws lambda get-function --function-name lab4-$USER_ID \
    --query Configuration.FunctionArn -o text)

cat >> ~/.dev-on-aws.env <<EOF
export API_ID=$API_ID
export ITEMS_ID=$ITEMS_ID
export ACCT=$ACCT
export LAMBDA_ARN=$LAMBDA_ARN
EOF
source ~/.dev-on-aws.env
```

> Labs 6b / 7a / 7b all reference `$API_ID`, `$ITEMS_ID`, `$ACCT`, `$LAMBDA_ARN`.

## Step 7 — Call It from Cloud9 (5 min)

```bash
# $API_ID was exported in Step 6 and is now live in this shell
URL="https://$API_ID.execute-api.us-east-1.amazonaws.com/dev/items"
echo "export URL=$URL" >> ~/.dev-on-aws.env
source ~/.dev-on-aws.env

curl -i -X POST $URL \
     -H "Content-Type: application/json" \
     -d '{"name":"Cloud9"}'
```

> Expect HTTP 200 and your Lambda's JSON body.

## Success Criteria (3 min)

- ✅ REST API `dev-on-aws-$USER_ID` created via Console wizard
- ✅ POST /items wired to `lab4-$USER_ID` with proxy integration
- ✅ Console **Test** returns 200 with a full request trace
- ✅ `dev` stage deployed; invoke URL works from Cloud9 `curl`
- ✅ `$API_ID`, `$ITEMS_ID`, `$ACCT`, `$LAMBDA_ARN` exported
