"""Lab 3b Step 3 — Query with a FilterExpression, paginated.

  KeyConditionExpression  narrows the rows the database touches
  FilterExpression        runs AFTER the read — still charged for
  Limit + ExclusiveStartKey  manual pagination when a page is full
"""
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr, Key

table = boto3.resource("dynamodb").Table(f"Items-{os.environ['USER_ID']}")

kwargs = {
    "KeyConditionExpression": Key("pk").eq(f"USER#{os.environ['USER_ID']}")
                              & Key("sk").begins_with("ITEM#"),
    "FilterExpression": Attr("price").lt(Decimal("20")),
    "Limit": 10,
}

total = 0
while True:
    r = table.query(**kwargs)
    total += len(r["Items"])
    if "LastEvaluatedKey" not in r:
        break
    kwargs["ExclusiveStartKey"] = r["LastEvaluatedKey"]

print("items under $20:", total)
