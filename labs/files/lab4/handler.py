import json, os, boto3

ddb = boto3.resource("dynamodb").Table(os.environ["ITEMS_TABLE"])
s3  = boto3.client("s3")
BKT = os.environ["UPLOADS_BUCKET"]

def handler(event, ctx):
    user = event.get("user", "anonymous")
    key  = f"uploads/{user}/{ctx.aws_request_id}.txt"
    s3.put_object(Bucket=BKT, Key=key, Body=b"hello from lambda")
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": BKT, "Key": key},
        ExpiresIn=300,
    )
    ddb.put_item(Item={
        "pk":  f"USER#{user}",
        "sk":  f"UPLOAD#{ctx.aws_request_id}",
        "url": url,
    })
    return {"statusCode": 200, "body": json.dumps({"url": url})}
