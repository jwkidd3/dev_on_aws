"""Lab 3b Step 6 — Scan, timed.

Scan reads the ENTIRE table then filters client-side. This is why you
design access patterns for Query first and only fall back to Scan for
ad-hoc one-offs or admin tools."""
import os
import time

import boto3
from boto3.dynamodb.conditions import Attr

table = boto3.resource("dynamodb").Table(f"Items-{os.environ['USER_ID']}")

t0 = time.time()
resp = table.scan(FilterExpression=Attr("category").eq("widgets"))
print(f"{len(resp['Items'])} items in {time.time()-t0:.2f}s")
