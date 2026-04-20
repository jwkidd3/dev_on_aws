"""Lab 2b Step 3 — print a presigned GET URL on stdout so the shell can
capture it into an env var:

    export GET_URL=$(python3 make_get_url.py 300)

Usage:  python3 make_get_url.py [TTL_SECONDS]   (default 300)
"""
import os
import sys
import boto3

ttl = int(sys.argv[1]) if len(sys.argv) > 1 else 300

url = boto3.client("s3").generate_presigned_url(
    "get_object",
    Params={"Bucket": os.environ["BUCKET"], "Key": "outbox/item-00.txt"},
    ExpiresIn=ttl,
)
sys.stdout.write(url)   # no trailing newline — shell $() trims it anyway
