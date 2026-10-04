"""Lab 3b Step 3 — the same GetItem through the LOW-LEVEL client vs the resource.

boto3 offers two layers over DynamoDB:
  client    1:1 with the HTTP API; every value is typed: {"S": "..."}, {"N": "9.5"}
  resource  higher-level document API; plain Python types, Decimal for numbers
"""
import os

import boto3
from boto3.dynamodb.types import TypeDeserializer

USER = os.environ["USER_ID"]
TABLE = f"Items-{USER}"
KEY = {"pk": f"USER#{USER}", "sk": "ITEM#003"}

# 1. Low-level client — you build typed attribute values yourself
client = boto3.client("dynamodb")
raw = client.get_item(
    TableName=TABLE,
    Key={"pk": {"S": KEY["pk"]}, "sk": {"S": KEY["sk"]}},
)["Item"]
print("client   →", raw)

# Typed → Python by hand (what the resource layer does for you)
td = TypeDeserializer()
print("decoded  →", {k: td.deserialize(v) for k, v in raw.items()})

# 2. Resource (document) API — same call, plain Python in and out
item = boto3.resource("dynamodb").Table(TABLE).get_item(Key=KEY)["Item"]
print("resource →", item)
