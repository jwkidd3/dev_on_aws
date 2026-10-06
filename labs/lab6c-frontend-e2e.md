# 🎓 Lab 6c — Frontend & End-to-End Test

*Hands-On Lab · 45 min · Module 12 — Access*

## Objectives (2 min)

- Host the web frontend on S3 and point it at **your** Cognito client and API
- Sign in from the browser and drive the full app: Cognito → API Gateway → Lambda → DynamoDB
- Prove the authorizer blocks bad calls and that each user only sees their own data

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - Site bucket `student-user1-site-<yyyymmdd>`
> - User `bob@example.com` inside **your** pool

## Prerequisites (3 min)

- Labs 6a and 6b complete; `$POOL_ID`, `$CLIENT_ID`, `$URL` exported
- Refresh your token first — it's likely over an hour old:

```bash
source ~/environment/dev-on-aws/refresh-token.sh
```

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 6c` creates-or-reuses the full stack through the site bucket (and `alice@example.com`). Then skip to Step 2.

## Step 1 — Create the Site Bucket (5 min)

```bash
SITE=student-$USER_ID-site-$(date +%Y%m%d)
aws s3 mb s3://$SITE
aws s3api put-public-access-block --bucket $SITE --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
aws s3 website s3://$SITE/ --index-document index.html --error-document error.html
echo "export SITE=$SITE" >> ~/.dev-on-aws.env
```

> Bucket names are global across *all* AWS accounts, and `$USER_ID` keeps yours distinct from your classmates'.

## Step 2 — Public-Read Policy (4 min)

> Open `~/environment/dev-on-aws/lab6/site-policy.json` in the editor — one `Allow s3:GetObject` statement. `BUCKET` is a placeholder; render and apply:

```bash
sed "s|BUCKET|$SITE|g" ~/environment/dev-on-aws/lab6/site-policy.json > /tmp/site-policy.json
aws s3api put-bucket-policy --bucket $SITE --policy file:///tmp/site-policy.json
```

> **Why no HTTPS-only rule?** The S3 website endpoint only serves HTTP, so a `DenyInsecureTransport` clause would 403 every request. For HTTPS, front the bucket with CloudFront + OAC (see Discussion).

## Step 3 — Configure & Deploy the Frontend (6 min)

> Open `lab6/web/index.html` in the editor. Find the two network calls it makes:
> - `signIn()` — POSTs to Cognito's public `InitiateAuth` API with your **client ID** (no AWS credentials in the browser)
> - `api()` — calls your API with the ID token in the `Authorization` header
>
> Both read their settings from `config.js`, which you generate now from your own env vars:

```bash
cd ~/environment/dev-on-aws/lab6
echo "window.APP_CONFIG={region:'us-east-1',clientId:'$CLIENT_ID',apiUrl:'$URL'};" > web/config.js
cat web/config.js
aws s3 sync web s3://$SITE/ --delete
echo "http://$SITE.s3-website-us-east-1.amazonaws.com"
```

## Step 4 — Use the App in the Browser (8 min)

1. Open the URL from Step 3 in a new browser tab
2. Open DevTools → **Network** tab, then sign in as `alice@example.com` / `Tr0picalStorm!`
3. The table lists Alice's items (anything left from Lab 6b). Add two items with the form
4. In **Network**, click the `items` requests: an `OPTIONS` **preflight** first (answered by the mock integration), then the real `GET`/`POST` carrying `Authorization: eyJ…`
5. Delete one item with its **Delete** button — watch the `DELETE /items/<id>` call
6. Sign out and try a wrong password — Cognito's error appears in *Last response*

> The page is static files on S3. Identity comes from Cognito; authorization happens in API Gateway; data access happens in Lambda. The browser never holds AWS credentials.

## Step 5 — Confirm from the Back End (4 min)

```bash
curl -s -H "Authorization: $ID_TOKEN" $URL | jq '.count, [.items[].title]'
SUB=$(python3 ~/environment/dev-on-aws/lab6/decode_jwt.py "$ID_TOKEN" --sub)
aws dynamodb query --table-name Items-$USER_ID --key-condition-expression "pk = :p" \
    --expression-attribute-values "{\":p\":{\"S\":\"USER#$SUB\"}}" \
    --query "Items[].{sk:sk.S, title:title.S, price:price.N}"
```

> Both show the items you just added in the browser — the API and the table agree.

## Step 6 — Prove the Authorizer Blocks (4 min)

```bash
curl -s -o /dev/null -w "no token:    %{http_code}\n" $URL
curl -s -o /dev/null -w "bad token:   %{http_code}\n" -H "Authorization: not.a.real.jwt" $URL
curl -s -o /dev/null -w "valid token: %{http_code}\n" -H "Authorization: $ID_TOKEN" $URL
```

> Expected: `401`, `401` (or `403`), `200`. The rejections never reach Lambda — API Gateway and the Cognito authorizer did the work.

## Step 7 — Second User, Separate Data (5 min)

```bash
aws cognito-idp admin-create-user --user-pool-id $POOL_ID --username bob@example.com \
  --user-attributes Name=email,Value=bob@example.com Name=email_verified,Value=true \
  --message-action SUPPRESS
aws cognito-idp admin-set-user-password --user-pool-id $POOL_ID \
  --username bob@example.com --password 'Tr0picalStorm!' --permanent
BOB_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id $CLIENT_ID \
  --auth-parameters 'USERNAME=bob@example.com,PASSWORD=Tr0picalStorm!' \
  --query AuthenticationResult.IdToken --output text)
```

```bash
python3 ~/environment/dev-on-aws/lab6/decode_jwt.py "$ID_TOKEN" "$BOB_TOKEN" --sub   # two different subs
curl -s -H "Authorization: $ID_TOKEN"  $URL | jq .count    # Alice's items
curl -s -H "Authorization: $BOB_TOKEN" $URL | jq .count    # 0 — Bob sees none of them
```

> Now sign in as Bob in the browser: an empty list. Add an item as Bob, then sign back in as Alice — she can't see it. The handler keys every read and write on the token's `sub`, which the client can't forge.

## Discussion (2 min)

- Where did per-user isolation actually happen — the frontend, API Gateway, or the Lambda?
- What breaks when the ID token expires mid-session? How would the page use the refresh token?
- When would you add CloudFront + OAC in front of the site bucket?

## Success Criteria (2 min)

- ✅ Site bucket serves the app; `config.js` points at your client and API
- ✅ Signed in as Alice in the browser; add, list, and delete work end-to-end
- ✅ Missing or malformed `Authorization` → 401/403, valid → 200
- ✅ Alice and Bob have distinct `sub` claims and see only their own items
