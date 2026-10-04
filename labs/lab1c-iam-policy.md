# 🧪 Lab 1c — Test Permissions & Author IAM Policy

*Hands-On Lab · 45 min · Module 4 — Permissions*

## Objectives (2 min)

- Read a real `AccessDenied` and identify the principal, action, and resource
- Build a deliberately narrow role and assume it from the CLI
- Write a least-privilege policy scoped to your own bucket prefix and attach it to that **role**
- Prove the policy allows what it should — and nothing more

> **Why a new role?** The class shares one AWS account and you are an administrator, so IAM won't stop you from touching other students' resources. Never test a denial on anything that isn't yours. Instead you'll create a role that only *you* use, give it almost nothing, and watch IAM enforce exactly what you write.

## Prerequisites (2 min)

- Lab 1b complete — `$USER_ID` and `$ACCT` set in `~/.dev-on-aws.env`
- `aws sts get-caller-identity` returns the `assumed-role/LabRole/…` ARN

> **Starting fresh?** `export USER_ID=user1` (your own number), then `bash ~/environment/dev-on-aws/bootstrap.sh 1c` exports `$USER_ID` / `$ACCT`.

## Step 1 — Read a Real Denial (5 min)

```bash
aws iam create-user --user-name test-blocked-$USER_ID
```

- Expected: `AccessDenied` — `LabRole` is allowed to manage *roles and policies* but not IAM *users*
- Read the full message: it names the **principal** (`assumed-role/LabRole/i-…`), the **action** (`iam:CreateUser`), and the **resource**
- In the Console you're `userN`, an admin. Your code runs as `LabRole`, which isn't. **Permissions belong to the identity making the call**, not to the person typing.

## Step 2 — Create a Narrow Role You Can Assume (8 min)

> Open `~/environment/dev-on-aws/lab1/trust-policy.json` and `lab1/s3-create-only.json` in the editor and read them. The trust policy lets **only `LabRole`** assume the new role. The permissions policy allows creating and listing `student-<you>-*` buckets — and **no deletes**.

```bash
cd ~/environment/dev-on-aws/lab1
sed "s/ACCT/$ACCT/" trust-policy.json > /tmp/trust.json
sed "s/USER/$USER_ID/" s3-create-only.json > /tmp/create-only.json
aws iam create-role --role-name Lab1cRole-$USER_ID \
    --assume-role-policy-document file:///tmp/trust.json --query Role.Arn
aws iam put-role-policy --role-name Lab1cRole-$USER_ID \
    --policy-name S3CreateOnly --policy-document file:///tmp/create-only.json
```

> Now add a CLI **profile** that assumes the role, using the instance's own credentials as the source:

```bash
aws configure set profile.lab1c.role_arn arn:aws:iam::$ACCT:role/Lab1cRole-$USER_ID
aws configure set profile.lab1c.credential_source Ec2InstanceMetadata
aws configure set profile.lab1c.region us-east-1
aws sts get-caller-identity --profile lab1c
```

- Expected ARN: `assumed-role/Lab1cRole-user1/botocore-session-…` — you're now a different principal
- If you get `AccessDenied` on `AssumeRole`, wait 10 s (IAM is eventually consistent) and retry

## Step 3 — Hit the Gap (5 min)

```bash
PROBE=student-$USER_ID-probe-$(date +%s)
aws s3 mb s3://$PROBE --profile lab1c      # allowed by S3CreateOnly
aws s3 rb s3://$PROBE --profile lab1c      # AccessDenied — no s3:DeleteBucket
```

- Read the error: principal `Lab1cRole-…`, action `s3:DeleteBucket`
- This is IAM's default: **anything not explicitly allowed is denied**

## Step 4 — Author the Policy (7 min)

> In the Cloud9 editor create `~/environment/dev-on-aws/lab1/student-allow-bucket-delete.json`. Replace `user1` with **your** user in both ARNs:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:DeleteBucket",
      "s3:DeleteObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::student-user1-*",
      "arn:aws:s3:::student-user1-*/*"
    ]
  }]
}
```

> Attach it to the **role** as a second inline policy:

```bash
cd ~/environment/dev-on-aws/lab1
aws iam put-role-policy --role-name Lab1cRole-$USER_ID \
    --policy-name AllowBucketDelete \
    --policy-document file://student-allow-bucket-delete.json
aws iam list-role-policies --role-name Lab1cRole-$USER_ID
```

> Console view: IAM → **Roles** → `Lab1cRole-userN` → **Permissions** tab shows both inline policies.

## Step 5 — Verify Allow *and* Deny (7 min)

```bash
sleep 10                                   # let IAM propagate
aws s3 rb s3://$PROBE --profile lab1c      # now succeeds
```

> Prove the scope holds. Create a bucket that's yours but **outside** the `student-<you>-` prefix (using `LabRole`, the default profile), then try to delete it as the narrow role:

```bash
OUT=scratch-$USER_ID-$(date +%s)
aws s3 mb s3://$OUT                        # LabRole creates it
aws s3 rb s3://$OUT --profile lab1c        # AccessDenied — name doesn't match student-<you>-*
aws s3 rb s3://$OUT                        # clean up as LabRole
```

> Same account, same person, your own bucket — denied, because the policy's `Resource` pattern doesn't match. That's least privilege doing its job.

## Step 6 — Clean Up the Role (3 min)

```bash
aws iam delete-role-policy --role-name Lab1cRole-$USER_ID --policy-name AllowBucketDelete
aws iam delete-role-policy --role-name Lab1cRole-$USER_ID --policy-name S3CreateOnly
aws iam delete-role --role-name Lab1cRole-$USER_ID
```

## Discussion (3 min)

- Why scope the `Resource` to your prefix instead of `"*"`?
- In production, which identity should your application code run as: a person's admin user, a broad shared role, or a narrow role like `Lab1cRole`?
- If the CLI succeeds but your SDK code fails on the same Cloud9 instance — what's the most likely cause? (Hint: which profile/credentials is each one using?)

## Success Criteria (3 min)

- ✅ `iam:CreateUser` as `LabRole` fails, and you can name the principal, action, and resource from the error
- ✅ `aws sts get-caller-identity --profile lab1c` shows `assumed-role/Lab1cRole-userN/…`
- ✅ Bucket delete as `Lab1cRole` fails before `AllowBucketDelete`, succeeds after
- ✅ Deleting a bucket outside `student-<you>-*` as `Lab1cRole` is still denied
- ✅ `Lab1cRole-userN` removed
