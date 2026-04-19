# Course Validation Script

A single Cloud9-runnable script that exercises every AWS operation the labs
teach. Use it before a delivery to confirm the account and image are in the
expected state.

## What it does

For each lab that runs AWS commands, the script executes the equivalent
operations through the AWS CLI + `boto3` under a unique `labval-<timestamp>`
prefix so it never collides with student work. Coverage:

| Lab | Operations exercised |
|---|---|
| 1b  | `pip3 install --user boto3`; `sts:GetCallerIdentity` from Python |
| 1c  | `s3:CreateBucket` / `DeleteBucket` round-trip in the student prefix |
| 2a/2b | S3 bucket create, versioning, object PUT with metadata, HEAD, presigned GET, presigned PUT |
| 3a/3b | DynamoDB `CreateTable` with `byCategory` GSI, `batch_writer` put, `Query`, conditional `UpdateItem`, GSI `Query` |
| 4a/4b | IAM role + trust doc, basic execution policy attach, inline policy for DDB + S3, `create-function` (Python 3.12 / arm64), `invoke`, tracing on, X-Ray daemon policy, `publish-version`, `create-alias` |
| 5a  | REST API, `/items` resource, POST method, Lambda proxy integration, `add-permission`, stage deployment |
| 6a  | Cognito user pool + SPA app client, admin-create-user, permanent password, `initiate-auth` returns JWT |
| 6b  | Cognito authorizer on the Lab 5a API |
| 7b  | `sam build`, `sam deploy` using the real `labs/files/lab7/template.yaml` + `handler.py` |

What it does **not** test (requires a browser):
- Cloud9 environment creation wizard
- Cognito create-user-pool wizard (scripted with CLI instead)
- API Gateway Console "Test" tab
- Lambda in-browser code editor

## Running it

From a Cloud9 terminal, after cloning this repo:

```bash
cd ~/environment/dev_on_aws/validation
chmod +x run.sh

./run.sh                 # full run (~5 min, creates ~15 resources)
./run.sh --skip-sam      # skip the SAM build/deploy (fastest if you only care about CLI ops)
./run.sh --quick         # skip SAM + Cognito + API-Gateway authorizer
```

## Output

Each operation prints `✅` or `❌`. A final line reports totals and the script
exits with that failure count.

```
── Lab 2a/2b — S3 CRUD, metadata, presigned URLs ──
  ✅  s3 mb labval-20260417-091235-uploads
  ✅  enable versioning
  ✅  put-object with metadata
  …

RESULT: 37 passed, 0 failed
```

## Cleanup

A `trap cleanup EXIT` deletes every resource the script created, in reverse
order of creation. Cleanup runs even if the script is interrupted (`Ctrl-C`)
or a middle step fails. If a cleanup step fails (rare; usually because a
prior step never got that far), the script reports it as a failed cleanup —
check the AWS console and delete by hand if needed.

## Cost

A full run creates + deletes about a dozen resources, all within AWS Free
Tier in non-production accounts. Expect well under $0.10 per run.

## Requirements on the running environment

- AWS CLI v2 (preinstalled in Cloud9)
- Python 3 + `pip3` (preinstalled in Cloud9)
- For `--skip-sam` off: SAM CLI and Docker (both preinstalled in Cloud9)
- IAM permissions to create the resources above (the tester's IAM user or role
  needs broad create/delete on S3, DynamoDB, Lambda, IAM, API Gateway, Cognito,
  CloudFormation, and X-Ray for a full run)
