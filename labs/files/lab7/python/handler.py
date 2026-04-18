import json, os, boto3
from aws_xray_sdk.core import xray_recorder, patch_all

patch_all()  # auto-wraps boto3, requests, httpx, …

ddb = boto3.resource("dynamodb").Table(os.environ["ITEMS_TABLE"])
s3  = boto3.client("s3")
BKT = os.environ["UPLOADS_BUCKET"]


@xray_recorder.capture("handler")
def handler(event, ctx):
    method = event.get("httpMethod", "DIRECT")
    user = (
        event.get("requestContext", {})
             .get("authorizer", {})
             .get("claims", {})
             .get("sub", event.get("user", "anonymous"))
    )
    xray_recorder.put_annotation("user", user)
    xray_recorder.put_annotation("method", method)
    xray_recorder.put_metadata("event", event)

    key = f"uploads/{user}/{ctx.aws_request_id}.txt"
    s3.put_object(Bucket=BKT, Key=key, Body=b"x-ray traced")
    ddb.put_item(Item={
        "pk":  f"USER#{user}",
        "sk":  f"UPLOAD#{ctx.aws_request_id}",
        "key": key,
    })
    return {"statusCode": 200, "body": json.dumps({"key": key})}
