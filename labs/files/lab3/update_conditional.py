"""Lab 3b Step 5 — Conditional update.

Run this script twice. The first run updates ITEM#003's price and bumps
views by 1. The second run raises ConditionalCheckFailedException because
price == 9.99 already — exactly how you prevent lost updates in concurrent
writers."""
import os
from decimal import Decimal

import boto3

table = boto3.resource("dynamodb").Table(f"Items-{os.environ['USER_ID']}")

resp = table.update_item(
    Key={"pk": f"USER#{os.environ['USER_ID']}", "sk": "ITEM#003"},
    UpdateExpression="SET price = :new ADD #v :one",
    ConditionExpression="price <> :new",
    ExpressionAttributeNames={"#v": "views"},
    ExpressionAttributeValues={":new": Decimal("9.99"), ":one": 1},
    ReturnValues="ALL_NEW",
)

print(resp["Attributes"])
