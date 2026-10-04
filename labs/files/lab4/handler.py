"""Items API handler — Lab 4b onward.

One function serves every way it gets invoked in this course:
  * direct invoke     {"user": "user1", "title": "...", "price": 1.5}
  * S3 trigger        {"Records": [{"s3": ...}]}            (Lab 4b)
  * REST API proxy    event["httpMethod"], Cognito claims   (Labs 5a, 6b, 6c)
  * HTTP API (v2)     event["requestContext"]["http"]       (Lab 7b, SAM)

Data is keyed by the caller's identity: pk = USER#<Cognito sub> behind an
authorizer, so each signed-in user only ever sees their own items.
"""
import json, os, uuid
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

ddb = boto3.resource("dynamodb").Table(os.environ["ITEMS_TABLE"])
s3  = boto3.client("s3")
BKT = os.environ["UPLOADS_BUCKET"]

CORS = {
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
}


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", **CORS},
        "body": json.dumps(body, default=lambda d: float(d) if isinstance(d, Decimal) else str(d)),
    }


def request_info(event):
    """Normalise REST (v1), HTTP API (v2), and direct events -> (method, user, item_id)."""
    rc = event.get("requestContext", {})
    method = event.get("httpMethod") or rc.get("http", {}).get("method") or "DIRECT"
    auth = rc.get("authorizer", {})
    claims = auth.get("claims") or auth.get("jwt", {}).get("claims") or {}
    user = claims.get("sub") or event.get("user") or "anonymous"
    item_id = (event.get("pathParameters") or {}).get("id")
    return method, user, item_id


def handler(event, ctx):
    # S3 trigger (Lab 4b): just log what arrived
    if "Records" in event:
        for r in event["Records"]:
            print(f"S3 {r['eventName']}: s3://{r['s3']['bucket']['name']}/{r['s3']['object']['key']}")
        return {"processed": len(event["Records"])}

    method, user, item_id = request_info(event)
    pk = f"USER#{user}"

    if method == "OPTIONS":
        return respond(200, {})

    if method == "GET" and item_id:
        item = ddb.get_item(Key={"pk": pk, "sk": f"ITEM#{item_id}"}).get("Item")
        return respond(200, item) if item else respond(404, {"error": f"no item {item_id}"})

    if method == "GET":
        items = ddb.query(KeyConditionExpression=Key("pk").eq(pk)
                          & Key("sk").begins_with("ITEM#"))["Items"]
        return respond(200, {"user": user, "count": len(items), "items": items})

    if method == "DELETE" and item_id:
        ddb.delete_item(Key={"pk": pk, "sk": f"ITEM#{item_id}"})
        return respond(200, {"deleted": item_id})

    if method in ("POST", "DIRECT"):
        raw = event.get("body") if "body" in event else json.dumps(event)
        body = json.loads(raw or "{}", parse_float=Decimal)
        new_id = uuid.uuid4().hex[:8]
        key = f"uploads/{user}/{new_id}.txt"
        s3.put_object(Bucket=BKT, Key=key, Body=f"{body.get('title', '')}\n".encode())
        url = s3.generate_presigned_url(
            "get_object", Params={"Bucket": BKT, "Key": key}, ExpiresIn=300)
        item = {
            "pk": pk,
            "sk": f"ITEM#{new_id}",
            "id": new_id,
            "title": body.get("title", "untitled"),
            "price": Decimal(str(body.get("price", 0))),
            "key": key,
        }
        ddb.put_item(Item=item)
        return respond(200, {**item, "url": url})

    return respond(405, {"error": f"method {method} not supported"})
