# 🎓 Lab 6c — Frontend & End-to-End Test

*Hands-On Lab · 45 min · Module 12 — Access*

## Objectives (3 min)

- Host a minimal static frontend on S3
- Prove end-to-end via `curl` from Cloud9 (sign-in → API → DynamoDB)
- Demonstrate per-user isolation with a second Cognito user

## Prerequisites (3 min)

- Labs 6a and 6b complete
- `$POOL_ID`, `$CLIENT_ID`, `$URL`, `$ID_TOKEN` exported

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 6c` creates-or-reuses the full stack through the site bucket so you can sync the web/ directory immediately.

## Step 1 — Create the Site Bucket (6 min)

```bash
SITE=student-$USER_ID-site-$(date +%Y%m%d)
aws s3 mb s3://$SITE

aws s3api put-public-access-block --bucket $SITE \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3 website s3://$SITE/ --index-document index.html --error-document error.html

echo "export SITE=$SITE" >> ~/.dev-on-aws.env
source ~/.dev-on-aws.env
```

## Step 2 — Public-Read Policy (6 min)

> Open `~/environment/dev-on-aws/lab6/site-policy.json` in the editor and read it — a single `Allow s3:GetObject` statement on this bucket. The literal `BUCKET` token is a placeholder; render a copy with your real bucket name and apply:

```bash
sed "s|BUCKET|$SITE|g" \
    ~/environment/dev-on-aws/lab6/site-policy.json > /tmp/site-policy.json

aws s3api put-bucket-policy --bucket $SITE \
    --policy file:///tmp/site-policy.json
```

> **Why no HTTPS-only enforcement?** The S3 website endpoint (`s3-website-us-east-1.amazonaws.com`) only serves HTTP. A `DenyInsecureTransport` clause would 403 every request. To keep HTTPS-only enforcement, front the bucket with CloudFront + OAC — out of scope here; see the Discussion slide.

## Step 3 — Minimal Landing Page (5 min)

> The landing page and 404 page are already on disk under `~/environment/dev-on-aws/lab6/web/`. Open them in the editor if you want to customize. Then sync:

```bash
aws s3 sync ~/environment/dev-on-aws/lab6/web s3://$SITE/ --delete
echo "http://$SITE.s3-website-us-east-1.amazonaws.com"
```

> Open the URL in a browser — confirm the page renders.

## Step 4 — Authorized Call (5 min)

```bash
# ID_TOKEN still valid from Lab 6a (1-hour lifetime)
curl -s -X POST $URL \
  -H "Authorization: $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"widget","price":9.99}' | jq .
```

> Expect a **200** response with the Lambda's JSON (presigned URL + stored row). Then confirm DynamoDB has the new row:

```bash
aws dynamodb scan --table-name Items-$USER_ID --limit 5 \
    --query "Items[].{sk:sk.S, title:title.S, price:price.N}"
```

## Step 5 — Prove the Authorizer Blocks (5 min)

> The authorizer from Lab 6b protects the route. Without a valid token the request never reaches Lambda.

```bash
# No Authorization header at all → API Gateway rejects
curl -s -o /dev/null -w "no token:       %{http_code}\n" \
     -X POST $URL -H "Content-Type: application/json" \
     -d '{"title":"x","price":1}'

# Malformed token → rejected before Lambda runs
curl -s -o /dev/null -w "bad token:      %{http_code}\n" \
     -X POST $URL -H "Content-Type: application/json" \
     -H "Authorization: not.a.real.jwt" \
     -d '{"title":"x","price":1}'

# Valid token → 200
curl -s -o /dev/null -w "valid token:    %{http_code}\n" \
     -X POST $URL -H "Content-Type: application/json" \
     -H "Authorization: $ID_TOKEN" \
     -d '{"title":"x","price":1}'
```

> Expected: `401`, `401` (or `403`), `200`. The 401s never touch your Lambda — API Gateway + the Cognito authorizer did the work.

## Step 6 — Second User & Claim Inspection (6 min)

> Create a second user, sign them in, verify each user's token carries a distinct `sub` claim. Your app uses `sub` to key per-user data — the capstone handler stores it in DynamoDB; Lab 7a's instrumented handler annotates X-Ray traces with it.

```bash
aws cognito-idp admin-create-user --user-pool-id $POOL_ID \
  --username bob@example.com \
  --user-attributes Name=email,Value=bob@example.com Name=email_verified,Value=true \
  --message-action SUPPRESS
aws cognito-idp admin-set-user-password --user-pool-id $POOL_ID \
  --username bob@example.com --password 'Tr0picalStorm!' --permanent

BOB_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH --client-id $CLIENT_ID \
  --auth-parameters USERNAME=bob@example.com,PASSWORD='Tr0picalStorm!' \
  --query AuthenticationResult.IdToken --output text)

# Compare each token's subject claim — they must differ
for T in "$ID_TOKEN" "$BOB_TOKEN"; do
  python3 -c "
import base64, json, sys
p = sys.argv[1].split('.')[1]
p += '=' * (-len(p) % 4)   # restore JWT base64url padding
print(json.loads(base64.urlsafe_b64decode(p))['sub'])
" "$T"
done

# Bob can also call the API — same route, different sub on the server side
curl -s -X POST $URL \
  -H "Authorization: $BOB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"bob widget","price":2.50}' | jq .
```

## Discussion (3 min)

- Where did per-user isolation actually happen — the frontend, API Gateway, or the Lambda?
- What breaks if the JWT expires mid-session? How does the client recover?
- When would you add CloudFront + OAC in front of the site bucket?

## Success Criteria (3 min)

- ✅ Site bucket serves a minimal landing page
- ✅ Authorized POST with `$ID_TOKEN` returns 200 and writes to DynamoDB
- ✅ Missing or malformed Authorization header returns 401/403 — request never reaches Lambda
- ✅ Alice's and Bob's tokens carry distinct `sub` claims
