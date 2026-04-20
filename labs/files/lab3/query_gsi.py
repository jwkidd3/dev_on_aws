"""Lab 3b Step 4 — Query the byCategory GSI.

Demonstrates:
  - GSI queries don't require the base table's primary key
  - Index KeySchema can mix a HASH (category) and RANGE (price)
  - Projection=ALL means every attribute is available in the result
"""
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource("dynamodb").Table(f"Items-{os.environ['USER_ID']}")

resp = table.query(
    IndexName="byCategory",
    KeyConditionExpression=Key("category").eq("widgets")
                           & Key("price").lt(Decimal("15")),
)

for x in resp["Items"]:
    print(x["sk"], x["title"], x["price"])
