import os
import boto3
from seed import ROWS

USER = os.environ.get("USER_ID", "user1")
TABLE_NAME = f"Items-{USER}"

table = boto3.resource("dynamodb").Table(TABLE_NAME)
with table.batch_writer() as bw:
    for r in ROWS:
        bw.put_item(Item=r)
print(f"loaded {len(ROWS)} rows into {TABLE_NAME}")
