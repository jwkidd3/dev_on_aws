# 🗂️ Lab 2a — S3 in the Console

*Hands-On Lab · 45 min · Console · Module 6 — Storage*

## Objectives (3 min)

- Create an S3 bucket through the AWS Console UI
- Upload an object and set metadata/content-type from the UI
- View object details and the ETag
- Enable versioning and observe object versions
- Delete an object in a versioned bucket, find the delete marker, and undo the delete

> Lab 2b does the same things from code. Lab 2a is console muscle-memory.

## Prerequisites (3 min)

- Lab 1a complete (Cloud9 + LabRole + repo cloned)
- AWS Console tab open at S3
- Your user: `user1` (replace throughout)

> **Starting fresh / fell behind?** Run `bash ~/environment/dev-on-aws/bootstrap.sh 2a` — it exports `$USER_ID`/`$ACCT` to `~/.dev-on-aws.env` so you're ready to go.

## Step 1 — Create the Bucket (Console) (6 min)

1. S3 console → **Create bucket**
2. Name: `student-user1-uploads-<today>` (e.g. `…-20260417`)
3. Region: **US East (N. Virginia) us-east-1**
4. Object Ownership: **ACLs disabled** (default)
5. Block Public Access: **leave all four boxes checked**
6. Versioning: **Enable**
7. Default encryption: SSE-S3 (default)
8. Click **Create bucket**

## Step 2 — Upload an Object (6 min)

1. Open the bucket → **Upload**
2. **Add files** → pick a local file (e.g. a text or image file from your Cloud9 tree)
3. Expand **Properties** → note **Content-Type**; change if needed
4. Expand **Metadata** → Add user metadata: key `owner`, value `user1`
5. Click **Upload**

## Step 3 — Inspect the Object (6 min)

1. Click the uploaded object's name
2. Note the **ETag**, **Size**, **Storage class**, **Last modified**
3. Scroll to **Metadata** — confirm `x-amz-meta-owner: user1`
4. Click **Object URL** — expect `AccessDenied` XML (Block Public Access is on)
5. Back on the object page → **Open** — browser opens a pre-signed URL, file downloads

## Step 4 — Observe Versioning (6 min)

1. Re-upload a *changed* copy of the same file (same key)
2. On the object page → **Versions** tab → you should see 2 versions with different ETags
3. Pick the older version → **Download** → confirm you get the original content

## Step 5 — Delete & Undelete with Versioning (6 min)

> ⚠️ The whole class shares this account and you're an admin — the Console will let you delete *anyone's* objects. Work only in **your** `student-<you>-…` bucket.

1. In your bucket, select the object → **Delete** → type `delete` → **Delete objects**
2. The object vanishes from the list. Toggle **Show versions** ON
3. The key is still there: both versions, plus a new **Delete marker** on top — versioning turned your delete into a soft delete
4. Select only the **Delete marker** row → **Delete** → `permanently delete`
5. Toggle **Show versions** OFF — the object is back, at its latest version

## Step 6 — Empty Your Bucket (6 min)

1. Bucket list → select your bucket → **Empty**
2. Type `permanently delete` → **Empty**
3. Leave the empty bucket in place — Lab 2b will reuse it
4. Save the name for later:

```bash
# In the Cloud9 terminal — look up the bucket you just created (no retyping)
BUCKET=$(aws s3api list-buckets --output text \
  --query "Buckets[?starts_with(Name,'student-$USER_ID-uploads')].Name | [0]")
echo "export BUCKET=$BUCKET" >> ~/.dev-on-aws.env
source ~/.dev-on-aws.env
echo $BUCKET    # should match the bucket you just created in the Console
```

## Success Criteria (3 min)

- ✅ Versioned bucket created in your prefix, BPA on
- ✅ Object uploaded with user metadata visible in the Properties tab
- ✅ Two versions of the same key exist; older version still downloadable
- ✅ Deleted object recovered by removing its delete marker
- ✅ `$BUCKET` exported for later labs
