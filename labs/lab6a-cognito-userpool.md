# 🎓 Lab 6a — Cognito in the Console

*Hands-On Lab · 45 min · Console · Module 12 — Access*

## Objectives (3 min)

- Create a Cognito user pool using the Console wizard
- Create an SPA app client (no secret, PKCE flow)
- Add a user and set a permanent password
- Use the CLI to sign in and get a JWT; decode it

## Prerequisites (3 min)

- Labs 1–5 complete (or run bootstrap below)
- `jq` available in Cloud9 (already installed)
- AWS Console tab open

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 6a` creates-or-reuses everything through the API Gateway stage so you can attach an authorizer at the end.

## Step 1 — Create the User Pool (6 min)

1. Console → **Cognito** → **Create user pool**
2. **Configure sign-in experience:** sign-in options = **Email**
3. **Configure security requirements:** password policy defaults; MFA = **No MFA** (class-only)
4. **Configure sign-up experience:** self-registration off; required attributes = `email`
5. **Configure message delivery:** **Send email with Cognito**
6. **Integrate your app:** user pool name `dev-on-aws-<your-user>` (e.g., `dev-on-aws-user1`). Step 3 queries for this exact name.

## Step 2 — Create the App Client (5 min)

1. Still in the wizard: **App client name** = `web`
2. Client type: **Public client** (no secret — SPA / mobile)
3. Authentication flows: check **ALLOW_USER_PASSWORD_AUTH** and **ALLOW_REFRESH_TOKEN_AUTH**
4. Click through → **Create user pool**
5. On the pool's page, copy the **User pool ID** and the app client's **Client ID**

## Step 3 — Save the IDs (5 min)

> Derive both IDs from the API instead of typing them — no copy-paste errors, no stale placeholders.

```bash
POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 \
    --query "UserPools[?Name=='dev-on-aws-$USER_ID'].Id | [0]" \
    --output text)
CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
    --user-pool-id $POOL_ID \
    --query "UserPoolClients[?ClientName=='web'].ClientId | [0]" \
    --output text)

echo "export POOL_ID=$POOL_ID"     >> ~/.dev-on-aws.env
echo "export CLIENT_ID=$CLIENT_ID" >> ~/.dev-on-aws.env
source ~/.dev-on-aws.env
echo "POOL_ID=$POOL_ID  CLIENT_ID=$CLIENT_ID"
```

> If the pool was created with a different name in the console wizard, swap the `Name==` filter accordingly.

## Step 4 — Add a User (Console) (5 min)

1. User pool → **Users** tab → **Create user**
2. Invitation: **Don't send an invitation**
3. Email: `alice@example.com` — check **Mark email as verified**
4. Temporary password: `Tr0picalStorm!`
5. **Create user** → user appears with status *Force change password*

## Step 5 — Set a Permanent Password (CLI) (5 min)

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id $POOL_ID \
  --username alice@example.com \
  --password 'Tr0picalStorm!' \
  --permanent
```

> The console can't set a permanent password without an email round-trip. The CLI can — useful in a shared account.

## Step 6 — Sign In, Get a JWT (5 min)

```bash
TOKENS=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=alice@example.com,PASSWORD='Tr0picalStorm!')

ID_TOKEN=$(echo $TOKENS | jq -r .AuthenticationResult.IdToken)
echo "export ID_TOKEN=$ID_TOKEN" >> ~/.dev-on-aws.env
```

## Step 7 — Decode the Payload (5 min)

```bash
echo $ID_TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

> Expected claims:

- `sub` — the user's unique ID (what your app keys data on)
- `email` — `alice@example.com`
- `iss` — the Cognito URL for your pool
- `aud` — your app client ID
- `exp` — 1 hour from now

## Success Criteria (3 min)

- ✅ User pool `dev-on-aws-$USER_ID` visible in the Console
- ✅ Public app client `web` created; no secret
- ✅ User `alice@example.com` confirmed, permanent password set
- ✅ `initiate-auth` returns an `IdToken`
- ✅ Decoded payload shows `sub`, `email`, `iss`, `aud`, `exp`
- ✅ `$POOL_ID`, `$CLIENT_ID`, `$ID_TOKEN` exported
