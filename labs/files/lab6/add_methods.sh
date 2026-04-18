#!/usr/bin/env bash
# Add GET /items and /items/{id} (GET + DELETE) to the REST API from Lab 5a,
# all protected by the Cognito authorizer from Lab 6b Step 1.
#
# Required env vars (set by earlier labs / ~/.dev-on-aws.env):
#   API_ID     — REST API id              (Lab 5a)
#   ITEMS_ID   — /items resource id       (Lab 5a)
#   LAMBDA_ARN — Lambda function ARN      (Lab 5a)
#   AUTH_ID    — Cognito authorizer id    (Lab 6b Step 1)

set -euo pipefail

URI="arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

# GET /items
aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$ITEMS_ID" \
  --http-method GET --authorization-type COGNITO_USER_POOLS --authorizer-id "$AUTH_ID"
aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$ITEMS_ID" \
  --http-method GET --type AWS_PROXY --integration-http-method POST --uri "$URI"

# Child resource /items/{id} with GET and DELETE
ID_RES=$(aws apigateway create-resource --rest-api-id "$API_ID" \
  --parent-id "$ITEMS_ID" --path-part "{id}" --query id -o text)

for M in GET DELETE; do
  aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$ID_RES" \
    --http-method "$M" --authorization-type COGNITO_USER_POOLS --authorizer-id "$AUTH_ID" \
    --request-parameters method.request.path.id=true
  aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$ID_RES" \
    --http-method "$M" --type AWS_PROXY --integration-http-method POST --uri "$URI"
done

aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name dev
echo "Deployed."
