"""Lab 2b Step 1 — seed inbox/ with 5 objects, each stamped with the
student's USER_ID so owner metadata doesn't collide in the shared account."""
import os
import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
USER_ID = os.environ["USER_ID"]

for i in range(5):
    s3.put_object(
        Bucket=BUCKET,
        Key=f"inbox/item-{i:02d}.txt",
        Body=f"message {i}".encode(),
        ContentType="text/plain",
        Metadata={"owner": USER_ID},
    )

print(f"seeded 5 objects under s3://{BUCKET}/inbox/")
