# 🗂️ Lab 2b — Presigned URLs & Processing Pipeline

*Hands-On Lab · 45 min · Module 6 — Storage*

## Objectives (2 min)

- Do from **code** what Lab 2a did in the Console — PUT, GET, metadata
- Build a round-trip pipeline: download → transform → upload back
- Generate a presigned GET URL; verify expiry behavior
- Generate a presigned PUT URL; upload via `curl` only
- Paginate through a prefix
- Block on **waiters** and read service **exception codes**

## Prerequisites (3 min)

- Lab 2a complete — empty bucket `student-$USER_ID-uploads-<today>` exists
- `$BUCKET` set in `~/.dev-on-aws.env`
- Working in Cloud9 terminal — no profile needed

> **Starting fresh?** `bash ~/environment/dev-on-aws/bootstrap.sh 2b` sets `$BUCKET` to an existing or new uploads bucket.

## Step 1 — Seed the Pipeline (6 min)

> Every Python snippet in this lab is already on disk under `~/environment/dev-on-aws/lab2/` (cloned in Lab 1a). **Do not paste Python into the terminal** — open each file in the Cloud9 editor, read it, then run it.

> Open `lab2/seed.py` in the editor. It PUTs 5 objects under `inbox/`, each stamped with your `$USER_ID` as owner metadata. Then run:

```bash
cd ~/environment/dev-on-aws/lab2
python3 seed.py
# seeded 5 objects under s3://student-…-uploads-…/inbox/
```

## Step 2 — Process with a Paginator (7 min)

> Open `lab2/process.py`. It paginates `inbox/` (no manual `ContinuationToken`), upper-cases each body, preserves metadata, and writes to `outbox/`.

```bash
python3 process.py
# processed 5 objects into s3://student-…-uploads-…/outbox/
```

## Step 3 — Presigned GET (6 min)

> Open `lab2/make_get_url.py`. It prints one presigned GET URL on stdout; an optional TTL argument (default 300 s) lets us demo expiry. We capture the URL into an env var so `curl` can use it directly.

```bash
# Capture a 300-second URL into $GET_URL
export GET_URL=$(python3 make_get_url.py 300)
curl -s "$GET_URL"; echo
# MESSAGE 0

# Capture a 5-second URL, wait past the window, retry
export GET_URL_SHORT=$(python3 make_get_url.py 5)
sleep 7
curl -s "$GET_URL_SHORT"; echo
# <Error><Code>AccessDenied</Code>…
```

- First fetch: body is `MESSAGE 0` — the URL itself carried the signed auth
- Second fetch: `AccessDenied` — expiry is enforced server-side
- Treat presigned URLs like bearer tokens while valid — anyone with the link can read
- `$(…)` trims trailing whitespace, so the URL lands in the env var clean

## Step 4 — Presigned PUT (6 min)

> Open `lab2/make_put_url.py`. It prints a presigned PUT URL on stdout, scoped to `uploads/$USER_ID/note.txt` with `Content-Type: text/plain`. Capture it the same way.

```bash
export PUT_URL=$(python3 make_put_url.py)
echo "$PUT_URL"   # sanity check — should be a long https:// URL

# Create the payload and PUT it — no AWS creds on the caller
echo "from curl" > /tmp/note.txt
curl -s -X PUT -H "Content-Type: text/plain" \
     --upload-file /tmp/note.txt \
     "$PUT_URL"
```

> S3 returns an empty body on success. If the `Content-Type` header differs from what you signed for, S3 returns `SignatureDoesNotMatch` — the header is part of the signed payload.

## Step 5 — Verify (5 min)

```bash
aws s3 ls s3://$BUCKET/ --recursive
aws s3api get-object --bucket $BUCKET \
    --key uploads/$USER_ID/note.txt /tmp/round-trip.txt
cat /tmp/round-trip.txt
# from curl
```

## Step 6 — Waiters & Exception Codes (7 min)

> Open `lab2/waiter_demo.py`. It creates a scratch bucket and uses `get_waiter("bucket_exists")` to block until S3 confirms it — no sleep loops. Then it triggers two real failures and prints their **service exception codes**, and finally deletes the bucket with a `bucket_not_exists` waiter.

```bash
python3 waiter_demo.py
# bucket_exists waiter returned — s3://student-…-waiterdemo is ready
# head_object on missing key   → 404
# get_object on missing bucket → NoSuchBucket
# bucket_not_exists waiter returned — cleaned up
```

- Every waiter is just a polling loop the SDK ships for you — `WaiterConfig` tunes delay and attempts
- `e.response["Error"]["Code"]` is the field your retry/branch logic should switch on — not the message text

## Success Criteria (3 min)

- ✅ 5 objects in `inbox/`, 5 matching objects in `outbox/`
- ✅ Presigned GET works inside the window, fails after expiry
- ✅ Presigned PUT accepts an upload from `curl` with no AWS creds
- ✅ Paginator iterated all objects without manual token management
- ✅ Waiters confirmed bucket create/delete; exception codes `404` and `NoSuchBucket` observed
