"""Create a bucket with a waiter, read real service exception codes, clean up.

Waiters poll an AWS API until a resource reaches the state you asked for —
no hand-rolled sleep loops. Exception codes are how your code tells apart
"bucket missing", "key missing", and "not allowed".

Usage: python3 waiter_demo.py
Requires: USER_ID exported (source ~/.dev-on-aws.env)
"""
import os
import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
bucket = f"student-{os.environ['USER_ID']}-waiterdemo"

# 1. Create, then WAIT until S3 confirms the bucket exists
s3.create_bucket(Bucket=bucket)
s3.get_waiter("bucket_exists").wait(
    Bucket=bucket, WaiterConfig={"Delay": 2, "MaxAttempts": 10}
)
print(f"bucket_exists waiter returned — s3://{bucket} is ready")

# 2. Trigger real service exceptions and read their codes
try:
    s3.head_object(Bucket=bucket, Key="never-uploaded.txt")
except ClientError as e:
    print(f"head_object on missing key   → {e.response['Error']['Code']}")  # 404

try:
    s3.get_object(Bucket=f"student-{os.environ['USER_ID']}-no-such-bucket",
                  Key="x")
except ClientError as e:
    print(f"get_object on missing bucket → {e.response['Error']['Code']}")  # NoSuchBucket

# 3. Delete, then WAIT until the name is fully gone
s3.delete_bucket(Bucket=bucket)
s3.get_waiter("bucket_not_exists").wait(
    Bucket=bucket, WaiterConfig={"Delay": 2, "MaxAttempts": 10}
)
print("bucket_not_exists waiter returned — cleaned up")
