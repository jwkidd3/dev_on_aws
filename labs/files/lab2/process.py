"""Lab 2b Step 2 — paginate inbox/, upper-case each body, write to outbox/.
Demonstrates boto3 paginators (no manual ContinuationToken) and
metadata preservation across an object copy."""
import os
import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]

paginator = s3.get_paginator("list_objects_v2")
count = 0
for page in paginator.paginate(Bucket=BUCKET, Prefix="inbox/"):
    for obj in page.get("Contents", []):
        resp = s3.get_object(Bucket=BUCKET, Key=obj["Key"])
        body = resp["Body"].read().decode().upper()
        out_key = obj["Key"].replace("inbox/", "outbox/")
        s3.put_object(
            Bucket=BUCKET,
            Key=out_key,
            Body=body.encode(),
            ContentType="text/plain",
            Metadata={**resp["Metadata"], "stage": "processed"},
        )
        count += 1

print(f"processed {count} objects into s3://{BUCKET}/outbox/")
