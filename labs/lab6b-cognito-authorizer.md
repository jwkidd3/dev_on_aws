# 🎓 Lab 6b — API Gateway Authorizer & Swagger Import

*Hands-On Lab · 45 min · Module 12 — Access*

## Objectives (2 min)

- Attach a Cognito user pool authorizer to the API from Lab 5
- Verify that no-token and valid-token calls behave correctly
- Replace the hand-built resources with a Swagger import
- Redeploy and smoke-test every method

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - Authorizer `cognito-user1` on **your** API `dev-on-aws-user1`; the Swagger import keeps the title `dev-on-aws-user1` (filled in from `__USER_ID__`)

## Prerequisites (3 min)

- Labs 5a, 6a complete
- Exported: `$USER_ID`, `$ACCT`, `$API_ID`, `$ITEMS_ID`, `$LAMBDA_ARN`, `$URL`, `$POOL_ID`, `$ID_TOKEN`

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 6b` creates-or-reuses the API, Lambda, user pool + client + `alice`, and captures a fresh `$ID_TOKEN`.

> Getting `401` with a token that used to work? It has expired (60-minute lifetime): `source ~/environment/dev-on-aws/refresh-token.sh`

## Step 1 — Create the Authorizer (6 min)

```bash
AUTH_ID=$(aws apigateway create-authorizer \
  --rest-api-id $API_ID \
  --name cognito-$USER_ID \
  --type COGNITO_USER_POOLS \
  --identity-source method.request.header.Authorization \
  --provider-arns arn:aws:cognito-idp:us-east-1:$ACCT:userpool/$POOL_ID \
  --query id --output text)

echo "export AUTH_ID=$AUTH_ID" >> ~/.dev-on-aws.env
source ~/.dev-on-aws.env
echo "AUTH_ID=$AUTH_ID"
```

> You're wiring the authorizer by hand first so you can see each moving part. Steps 4–5 then replace all of this hand-built wiring with a single Swagger import — the API as code.

## Step 2 — Attach to POST (5 min)

```bash
aws apigateway update-method \
  --rest-api-id $API_ID --resource-id $ITEMS_ID \
  --http-method POST \
  --patch-operations \
    op=replace,path=/authorizationType,value=COGNITO_USER_POOLS \
    op=replace,path=/authorizerId,value=$AUTH_ID 

aws apigateway create-deployment \
  --rest-api-id $API_ID --stage-name dev
```

## Step 3 — Verify Auth (5 min)

```bash
# No token → 401
curl -i -X POST $URL -H "Content-Type: application/json" \
     -d '{"title":"x","price":1}'

# Valid token → 200 — note "pk": "USER#<alice's sub>", not USER#anonymous
curl -i -X POST $URL -H "Authorization: $ID_TOKEN" \
     -H "Content-Type: application/json" -d '{"title":"authed","price":9.99}'

# Malformed token → 401
curl -i -X POST $URL -H "Authorization: not.a.token" \
     -d '{"title":"x","price":1}'
```

> No-token call returned **200**? The previous deployment is still being served on some nodes — wait 30–60 s and repeat. Deployments propagate gradually.

> With the authorizer in place, API Gateway passes the verified claims to Lambda, and the handler keys the item on Alice's `sub`. The client can no longer choose whose data it writes.

## Step 4 — Read the Swagger Definition (6 min)

> Open `~/environment/dev-on-aws/lab6/swagger.json` in the **editor** and find these five pieces before you import anything:

- `securityDefinitions.CognitoAuth` — the authorizer you built by hand in Step 1, declared as code (`x-amazon-apigateway-authorizer`)
- `x-amazon-apigateway-request-validators` + `definitions.NewItem` — a **request model**: POST bodies must carry `title` (string) and `price` (number) or API Gateway rejects them with 400 before Lambda ever runs
- `paths./items.options` — a **mock integration** answering CORS preflight; its `requestTemplates` block is a VTL **mapping template**, the same mechanism non-proxy integrations use to reshape payloads
- `x-amazon-apigateway-integration` on every method — the Lambda proxy wiring from Lab 5a, repeated as code
- `x-amazon-apigateway-gateway-responses` — adds CORS headers to API Gateway's *own* 401/403/400 errors, so a browser can read them (Lab 6c's web page relies on this)

## Step 5 — Import & Redeploy (8 min)

```bash
cd ~/environment/dev-on-aws/lab6
sed -e "s/__ACCT__/$ACCT/g" \
    -e "s/__POOL_ID__/$POOL_ID/g" \
    -e "s|__LAMBDA_ARN__|$LAMBDA_ARN|g" \
    -e "s/__USER_ID__/$USER_ID/g" \
    swagger.json > /tmp/swagger-filled.json

# Overwrite the hand-built API with the definition-as-code
aws apigateway put-rest-api --rest-api-id $API_ID \
    --mode overwrite --body fileb:///tmp/swagger-filled.json

# New methods need invoke permission on the Lambda
aws lambda add-permission --function-name lab4-$USER_ID \
    --statement-id swagger-$USER_ID \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-east-1:$ACCT:$API_ID/*"

aws apigateway create-deployment --rest-api-id $API_ID --stage-name dev
```

> `--mode overwrite` replaces every resource, method, and authorizer on the API with what the file declares — your Step 1–2 hand wiring is now reproducible from version control.

> ⏱️ A new deployment reaches API Gateway's nodes gradually — for a minute or two, some requests can still hit the *old* API (no authorizer, no GET). Wait until it's consistent before Step 6:

```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}/" $URL                    # GET, no token
  curl -s -o /dev/null -w "%{http_code} " -X POST $URL -d '{}'    # POST, no token
  sleep 3
done; echo
# want ten "401/401" in a row. A 403 or 200 is the old API still answering — run it again.
```

## Step 6 — Smoke Test Everything (8 min)

```bash
H="-H Authorization:$ID_TOKEN"
ID=$(curl -s $H -X POST $URL -H "Content-Type: application/json" \
     -d '{"title":"from swagger","price":4.50}' | jq -r .id)   # POST → new id
echo "created $ID"
curl -s $H $URL | jq '.count, [.items[].title]'               # GET list (only Alice's items)
curl -s $H $URL/$ID | jq .                                    # GET one
curl -s $H -X DELETE $URL/$ID | jq .                          # DELETE
curl -s -o /dev/null -w "after delete: %{http_code}\n" $H $URL/$ID   # → 404

# Request model: body missing "price" → 400 before Lambda runs
curl -s -o /dev/null -w "invalid body:  %{http_code}\n" $H \
  -X POST $URL -H "Content-Type: application/json" -d '{"title":"no price"}'

# CORS preflight: mock integration answers, no auth needed
curl -s -i -X OPTIONS $URL | grep -i access-control
```

## Success Criteria (2 min)

- ✅ Authorizer created and attached to POST by hand (Steps 1–2)
- ✅ No-token → 401, valid-token → 200
- ✅ Swagger import rebuilt the API: POST + GET `/items`, GET + DELETE `/items/{id}`, all Cognito-protected
- ✅ Item created, listed, fetched, deleted — then `404`
- ✅ POST without `price` → 400 from the request validator (Lambda never invoked)
- ✅ `OPTIONS /items` returns `Access-Control-Allow-*` headers from the mock integration
