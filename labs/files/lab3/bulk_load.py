"""Lab 3b Step 2 — load items.json into Items-$USER_ID with the batch writer.

json.load(parse_float=Decimal) matters: DynamoDB's document API rejects
Python floats, so numbers must arrive as Decimal.
"""
import json
import os
from decimal import Decimal

import boto3

TABLE_NAME = f"Items-{os.environ['USER_ID']}"

with open("items.json") as f:
    rows = json.load(f, parse_float=Decimal)

table = boto3.resource("dynamodb").Table(TABLE_NAME)
with table.batch_writer() as bw:      # chunks to 25/call, retries UnprocessedItems
    for r in rows:
        bw.put_item(Item=r)
print(f"loaded {len(rows)} rows from items.json into {TABLE_NAME}")
