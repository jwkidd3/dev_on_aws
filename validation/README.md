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
| bootstrap | `labs/files/bootstrap.sh` against **all 13 labIds** (`1b 2a 2b 3a 3b 4a 4b 5a 6a 6b 6c 7a 7b`) under one synthetic USER_ID — exercises every `ensure_*` function; verifies bucket, table, role, function, API, Cognito pool, site bucket exist; re-runs `6c` and asserts ≥5 "already present" skips for idempotency |
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

./run.sh                    # full run (~6 min, creates ~20 resources)
./run.sh --skip-sam         # skip Lab 7b (sam build + deploy; needs Docker)
./run.sh --skip-bootstrap   # skip the bootstrap.sh idempotency check
./run.sh --quick            # skip SAM + Cognito + API Gateway authorizer + bootstrap
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
or a middle step fails.

What cleanup removes:

- CloudFormation stack (`sam delete` equivalent via `cfn delete-stack`)
- Cognito user pool (and implicitly the app client + user + authorizer on it)
- API Gateway REST API (and implicitly its resources, methods, stage, deployment)
- Lambda function (and implicitly its versions, aliases, resource policies)
- `/aws/lambda/<function-name>` and `/aws/apigateway/<prefix>` log groups
- Lambda execution role — inline policy `LambdaAppAccess` removed, both
  managed policies (`AWSLambdaBasicExecutionRole` and
  `AWSXRayDaemonWriteAccess`) detached, then the role itself deleted
- DynamoDB table (and its GSI)
- Every S3 bucket created, including the versioned uploads bucket —
  the helper enumerates every object version + delete marker and removes them
  in batches of 1000 before calling `s3 rb`
- The `/tmp` scratch directory used for heredocs

What cleanup intentionally does **not** remove:
- The SAM-managed artifact bucket (`aws-sam-cli-managed-default-*`). It's a
  shared, per-account bucket that real deployments also reuse; leaving it
  avoids breaking subsequent runs and it costs fractions of a cent per month.

If a cleanup step fails (rare; usually because a prior step never got that
far), the script reports it as a failed cleanup — check the AWS console and
delete by hand if needed, or use the orphan sweeper below.

## Cleaning up from earlier runs

If a previous `run.sh` was interrupted or its cleanup trap didn't get to
everything, use the sweeper:

```bash
./cleanup-orphans.sh            # dry run — lists what it would delete
./cleanup-orphans.sh --delete   # actually deletes
```

It finds every resource whose name starts with `labval-` across:
CloudFormation stacks (`sam-labval-*`), Cognito user pools, API Gateway REST
APIs, Lambda functions (`lab4-labval-*`), IAM roles
(`StudentLambdaRole-labval-*`), DynamoDB tables (`Items-labval-*`), S3 buckets,
and CloudWatch log groups (`/aws/lambda/lab4-labval-*`,
`/aws/apigateway/labval-*`). Same versioned-bucket handling as `run.sh`.

## Cost

A full run creates + deletes about a dozen resources, all within AWS Free
Tier in non-production accounts. Expect well under $0.10 per run.

## Requirements on the running environment

- AWS CLI v2 (preinstalled in Cloud9)
- Python 3 + `pip3` (preinstalled in Cloud9)
- `python3.12` on PATH **or** Docker running (SAM needs one to build a
  `Runtime: python3.12` function). Cloud9 on AL2023 ships Python 3.9 by
  default; the script tries `sudo dnf install -y python3.12` and falls back
  to `sam build --use-container` if Docker is available.
- IAM permissions to create the resources above (the tester's IAM user or role
  needs broad create/delete on S3, DynamoDB, Lambda, IAM, API Gateway, Cognito,
  CloudFormation, and X-Ray for a full run)

## Known limitation: Cloud9 AMTC blocks IAM writes

By default, Cloud9 uses **AWS Managed Temporary Credentials (AMTC)**. AMTC
deliberately blocks a set of sensitive API calls — notably every
`iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy`,
`iam:DeleteRole`, and most `sts:*` calls. In that environment the validator
fails on every Lab 4 / Lab 5 step and every IAM cleanup, with:

```
An error occurred (InvalidClientTokenId) when calling the CreateRole operation:
The security token included in the request is invalid.
```

The script is correct — the environment isn't allowed to do what the labs do.
Two ways to run the full validator:

1. **Turn off AMTC in this Cloud9** — `Preferences → AWS Settings → Credentials`
   → disable *AWS managed temporary credentials*. Then run
   `aws configure` with long-lived keys for an IAM user that has the
   permissions listed above. (AMTC re-enables itself if the instance
   restarts; re-disable after every restart.)
2. **Run the validator outside Cloud9** — on a laptop with the AWS CLI and
   credentials for the shared account. All operations are CLI-only, nothing
   requires Cloud9 itself.

Students doing the **labs** (not the validator) are not affected by this —
Lab 4 creates the IAM role through the Lambda console wizard, which goes
through the Cloud9 console session, not the CLI credential chain.
