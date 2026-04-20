"""Lab 2b Step 4 — print a presigned PUT URL on stdout so the shell can
capture it into an env var:

    export PUT_URL=$(python3 make_put_url.py)

The URL is scoped to uploads/$USER_ID/note.txt with ContentType text/plain.
The caller must send the exact same Content-Type header or S3 returns
SignatureDoesNotMatch (the header is part of the signed payload).
"""
import os
import sys
import boto3

url = boto3.client("s3").generate_presigned_url(
    "put_object",
    Params={
        "Bucket":      os.environ["BUCKET"],
        "Key":         f"uploads/{os.environ['USER_ID']}/note.txt",
        "ContentType": "text/plain",
    },
    ExpiresIn=600,
)
sys.stdout.write(url)
