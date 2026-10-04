# 🎓 Lab 6a — Cognito in the Console

*Hands-On Lab · 45 min · Console · Module 12 — Access*

## Objectives (3 min)

- Create a Cognito user pool and a public SPA app client with the Console wizard
- Name the pool for your user so it's findable in the shared account
- Add a user and set a permanent password
- Sign in from the CLI, get a JWT, and decode it

## Prerequisites (3 min)

- Labs 1–5 complete (or run bootstrap below)
- `jq` available in Cloud9 (already installed)
- AWS Console tab open

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 6a` creates-or-reuses everything through the API Gateway stage so you can attach an authorizer at the end.

## Step 1 — Create the User Pool + App Client (7 min)

1. Console → **Cognito** → **User pools** → **Create user pool**
2. **Define your application** → Application type: **Single-page application (SPA)** — a *public* client, no secret
3. **Name your application:** `web` — this becomes the app client name; later steps look for it
4. **Options for sign-in identifiers:** **Email** only
5. **Self-registration:** leave **off** (we create users as admins)
6. **Required attributes for sign-up:** `email`
7. **Add a return URL:** `http://localhost:3000/callback` (required by the wizard; unused in this lab)
8. **Create user directory** (some console versions label it *Create your application*) — the wizard creates the pool *and* the `web` client, then shows code samples. Scroll down → **Go to overview**

## Step 2 — Rename the Pool & Enable Password Sign-In (6 min)

> The wizard auto-names the pool `User pool - abc123`. The whole class's pools land in the same list, so give yours a name only you will use:

1. Pool **Overview** → **Rename** → `dev-on-aws-<your-user>` (e.g., `dev-on-aws-user1`) → **Save changes**. Step 3 and the bootstrap script look for this exact name.
2. Left nav → **App clients** → `web` → **Edit** (App client information)
3. **Authentication flows:** keep the defaults and also check **Sign in with username and password: ALLOW_USER_PASSWORD_AUTH** — the CLI sign-in below and the Lab 6c web page use it
4. **Save changes**

> SPA clients default to SRP (the password never leaves the browser) and the managed-login PKCE flow. We add `USER_PASSWORD_AUTH` so you can test from a terminal — fine in a lab; in production prefer SRP or managed login with PKCE.

## Step 3 — Save the IDs (4 min)

> Derive both IDs from the API instead of typing them — no copy-paste errors, and no risk of grabbing a classmate's pool.

```bash
POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --output text \
    --query "UserPools[?Name=='dev-on-aws-$USER_ID'].Id | [0]")
CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id $POOL_ID \
    --output text --query "UserPoolClients[?ClientName=='web'].ClientId | [0]")
for v in POOL_ID CLIENT_ID; do echo "export $v=${!v}" >> ~/.dev-on-aws.env; done
echo "POOL_ID=$POOL_ID  CLIENT_ID=$CLIENT_ID"
```

> If `POOL_ID` prints `None`, the rename in Step 2 didn't save — check the pool's name in the Console.

## Step 4 — Add a User (Console) (5 min)

1. User pool → **Users** → **Create user**
2. Invitation message: **Don't send an invitation**
3. Email address: `alice@example.com` — check **Mark email address as verified**
4. Temporary password: **Set a password** → `Tr0picalStorm!`
5. **Create user** → status *Force change password*

> Every student's pool is separate, so every pool can have its own `alice@example.com`.

## Step 5 — Set a Permanent Password (CLI) (4 min)

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id $POOL_ID \
  --username alice@example.com \
  --password 'Tr0picalStorm!' \
  --permanent
```

> The Console can't skip the force-change step without an email round-trip. The admin API can.

## Step 6 — Sign In, Get a JWT (5 min)

```bash
ID_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH --client-id $CLIENT_ID \
  --auth-parameters 'USERNAME=alice@example.com,PASSWORD=Tr0picalStorm!' \
  --query AuthenticationResult.IdToken --output text)
echo "export ID_TOKEN=$ID_TOKEN" >> ~/.dev-on-aws.env
echo ${ID_TOKEN:0:40}…
```

> ⏱️ **ID tokens expire after 60 minutes.** From Lab 6c on, each lab starts with `source ~/environment/dev-on-aws/refresh-token.sh`, which repeats this sign-in and updates `$ID_TOKEN` in your shell and the env file.

## Step 7 — Decode the Payload (5 min)

```bash
python3 ~/environment/dev-on-aws/lab6/decode_jwt.py "$ID_TOKEN"
```

> A JWT is `header.payload.signature`, each part base64url *without padding* — that's why `base64 -d` usually fails on it. Open `lab6/decode_jwt.py` to see the two-line fix. Expected claims:

- `sub` — the user's unique ID (what the app keys data on)
- `email` — `alice@example.com`
- `iss` — the Cognito URL for **your** pool
- `aud` — your `web` client ID
- `exp` — 1 hour from now (Unix seconds)

## Success Criteria (3 min)

- ✅ User pool `dev-on-aws-$USER_ID` visible in the Console
- ✅ Public app client `web`, no secret, `ALLOW_USER_PASSWORD_AUTH` enabled
- ✅ User `alice@example.com` confirmed with a permanent password
- ✅ `initiate-auth` returns an ID token; decoded payload shows `sub`, `email`, `iss`, `aud`, `exp`
- ✅ `$POOL_ID`, `$CLIENT_ID`, `$ID_TOKEN` exported
