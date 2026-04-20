# Developing on AWS

A 3-day, introductory-level, **lab-heavy** workshop for developers who want to build a real serverless web application on AWS using the SDKs, CLI, and the Console. **15 hands-on labs**, each ≤ 45 minutes, build the application piece by piece inside AWS Cloud9.

## Audience

Software developers, solution architects, and IT professionals with:

- AWS Technical Essentials-level knowledge or equivalent
- Working programming experience in **Python**

## Format

- 15 Reveal.js teaching decks — paced for 15–20 min delivery (M1/M15 shorter)
- **15 Reveal.js lab decks** — each ≤ 45 min of keyboard time
- **~71% lab / ~29% lecture** by schedule clock
- **Every lab runs inside AWS Cloud9** — no local install on student laptops
- For each major service, the **first sub-lab is Console-driven**; follow-ups use the SDK/CLI
- Shared class AWS account — each student gets an IAM user (`user1`, `user2`, …)
- Region for all labs: `us-east-1`
- **7 hours per day** (09:00 – 16:00), 1-hour lunch, two 15-min breaks

## Lab Environment

- **Console URL:** `https://kiddcorp.signin.aws.amazon.com/console`
- **Usernames:** `user1`, `user2`, `user3`, … — handed out at class start
- **Cloud9 environment:** students **create their own** in Lab 1a — new EC2, **m5.large**, **SSH** connection, Amazon Linux 2023, 30-min idle timeout
- **Pre-seeded per student:** the IAM user `userN` plus prefix-enforcing policies attached to that user, and a shared **`LabRole`** that has the broader permissions the labs exercise (IAM, STS, Lambda, SAM/CloudFormation, etc.). *Everything else* — Cloud9, DynamoDB tables, Lambda roles, S3 buckets, Cognito pools, API Gateway, SAM stacks — students create in the labs.
- **Prefix convention:** every resource a student creates starts with their user ID (`student-user1-…`, `Items-user1`, `lab4-user1`, `StudentLambdaRole-user1`). The IAM policies enforce this.
- **Credentials:** Cloud9's default **AWS Managed Temporary Credentials (AMTC)** block a handful of IAM/STS/Lambda calls the labs need. In **Lab 1a** students attach **`LabRole`** to the Cloud9 EC2 instance and **turn AMTC off** so the SDK/CLI pick up the role via IMDS — no `aws configure`, no access keys on laptops.
- **Editor vs. terminal:** class convention set in Lab 1a — source/config files are authored in the Cloud9 **editor**; commands ≤ ~5 lines go into the **terminal**. Never paste multi-line source into a shell prompt.

## Module → Lab Map

Which labs each teaching module sets up. Modules without labs are pure concept / recap. Labs always follow their paired module on the schedule (same day).

| # | Module | Lab(s) it sets up | Day |
| -- | ------ | ----------------- | --- |
| 1  | Course Overview                         | — (kickoff)        | 1 |
| 2  | Building a Web Application on AWS       | — (architecture)   | 1 |
| 3  | Getting Started with Development on AWS | **1a, 1b**         | 1 |
| 4  | Getting Started with Permissions        | **1c**             | 1 |
| 5  | Getting Started with Storage            | — (paired w/ M6)   | 1 |
| 6  | Processing Your Storage Operations      | **2a, 2b**         | 1 |
| 7  | Getting Started with Databases          | — (paired w/ M8)   | 2 |
| 8  | Processing Your Database Operations     | **3a, 3b**         | 2 |
| 9  | Processing Your Application Logic       | **4a, 4b**         | 2 |
| 10 | Managing the APIs                       | **5a**             | 2 |
| 11 | Building a Modern Application           | — (integration)    | 3 |
| 12 | Granting Access to Application Users    | **6a, 6b, 6c**     | 3 |
| 13 | Deploying Your Application              | **7b**             | 3 |
| 14 | Observing Your Application              | **7a**             | 3 |
| 15 | Course Wrap-up                          | —                  | 3 |

Labs 7a and 7b are done back-to-back on Day 3: **7a** (X-Ray instrumentation, paired with M14) deposits the instrumented handler that **7b** (SAM deploy, paired with M13) then deploys via CloudFormation.

## Console vs. SDK Labs

| Service     | Console lab | SDK / CLI lab(s)                                 |
| ----------- | ----------- | ------------------------------------------------ |
| IAM         | Lab 1a, 1c  | Lab 1b (SDK smoke)                               |
| S3          | **Lab 2a**  | Lab 2b (SDK + presigned)                         |
| DynamoDB    | **Lab 3a**  | Lab 3b (Query, GSI, conditional update)          |
| Lambda      | **Lab 4a**  | Lab 4b (SDK + S3 triggers)                       |
| API Gateway | **Lab 5a**  | Lab 6b (Swagger import brings CORS + validation) |
| Cognito     | **Lab 6a**  | Lab 6b (authorizer), Lab 6c (frontend)           |
| SAM / X-Ray | —           | Lab 7a (SDK instrument), Lab 7b (SAM + trace map) |

## Three-Day Schedule

Class runs **09:00 – 16:00** each day (7 h). Lunch 60 min, two 15-min breaks.

### Day 1 — Foundations

| Time          | Block                                            | Duration |
| ------------- | ------------------------------------------------ | -------- |
| 09:00 – 09:15 | [M1 — Course Overview](presentations/01-course-overview.html)                         | 15 min |
| 09:15 – 09:35 | [M2 — Building a Web Application on AWS](presentations/02-building-web-application.html) | 20 min |
| 09:35 – 09:55 | [M3 — Getting Started with Development on AWS](presentations/03-getting-started-development.html) | 20 min |
| 09:55 – 10:10 | *Break*                                          | 15 min |
| 10:10 – 10:30 | [M4 — Getting Started with Permissions](presentations/04-getting-started-permissions.html) | 20 min |
| 10:30 – 11:00 | **[Lab 1a — Sign In & Create Your Cloud9 Environment](labs/lab1a-signin-orientation.html)** | 30 min |
| 11:00 – 11:30 | **[Lab 1b — First SDK Call in Cloud9](labs/lab1b-cli-sdk-profile.html)** | 30 min |
| 11:30 – 12:15 | **[Lab 1c — IAM Policy Authoring](labs/lab1c-iam-policy.html)** | 45 min |
| 12:15 – 13:15 | *Lunch*                                          | 60 min |
| 13:15 – 13:27 | [M5 — Getting Started with Storage](presentations/05-getting-started-storage.html) | ~12 min |
| 13:27 – 13:40 | [M6 — Processing Your Storage Operations](presentations/06-processing-storage-operations.html) | ~13 min |
| 13:40 – 13:55 | *Break*                                          | 15 min |
| 13:55 – 14:40 | **[Lab 2a — S3 in the Console](labs/lab2a-s3-crud.html)** | 45 min |
| 14:40 – 15:25 | **[Lab 2b — S3 via SDK & Presigned URLs](labs/lab2b-s3-presigned.html)** | 45 min |
| 15:25 – 16:00 | *Day-1 wrap / Q&A*                                | 35 min |

**Day 1 totals:** lecture 100 min · lab 195 min · **lab share 66%**

### Day 2 — Data & Logic

| Time          | Block                                            | Duration |
| ------------- | ------------------------------------------------ | -------- |
| 09:00 – 09:20 | [M7 — Getting Started with Databases](presentations/07-getting-started-databases.html) | 20 min |
| 09:20 – 09:40 | [M8 — Processing Your Database Operations](presentations/08-processing-database-operations.html) | 20 min |
| 09:40 – 09:55 | *Break*                                          | 15 min |
| 09:55 – 10:40 | **[Lab 3a — DynamoDB in the Console](labs/lab3a-dynamodb-basics.html)** | 45 min |
| 10:40 – 11:25 | **[Lab 3b — DynamoDB via SDK](labs/lab3b-dynamodb-query.html)** | 45 min |
| 11:25 – 11:45 | [M9 — Processing Your Application Logic](presentations/09-processing-application-logic.html) | 20 min |
| 11:45 – 12:45 | *Lunch*                                          | 60 min |
| 12:45 – 13:30 | **[Lab 4a — Lambda in the Console](labs/lab4a-lambda-deploy.html)** | 45 min |
| 13:30 – 14:15 | **[Lab 4b — Lambda SDK + Triggers](labs/lab4b-lambda-integrations.html)** | 45 min |
| 14:15 – 14:30 | *Break*                                          | 15 min |
| 14:30 – 14:50 | [M10 — Managing the APIs](presentations/10-managing-apis.html) | 20 min |
| 14:50 – 15:35 | **[Lab 5a — API Gateway in the Console](labs/lab5a-api-gateway-basics.html)** | 45 min |
| 15:35 – 16:00 | *Day-2 wrap / Q&A*                                | 25 min |

**Day 2 totals:** lecture 80 min · lab 225 min · **lab share 74%**

### Day 3 — Modern Application

| Time          | Block                                            | Duration |
| ------------- | ------------------------------------------------ | -------- |
| 09:00 – 09:20 | [M11 — Building a Modern Application](presentations/11-building-modern-application.html) | 20 min |
| 09:20 – 09:40 | [M12 — Granting Access to Your Application Users](presentations/12-granting-access-users.html) | 20 min |
| 09:40 – 09:55 | *Break*                                          | 15 min |
| 09:55 – 10:40 | **[Lab 6a — Cognito in the Console](labs/lab6a-cognito-userpool.html)** | 45 min |
| 10:40 – 11:25 | **[Lab 6b — Authorizer & Swagger Import](labs/lab6b-cognito-authorizer.html)** | 45 min |
| 11:25 – 12:10 | **[Lab 6c — Frontend End-to-End](labs/lab6c-frontend-e2e.html)** | 45 min |
| 12:10 – 13:10 | *Lunch*                                          | 60 min |
| 13:10 – 13:30 | [M13 — Deploying Your Application](presentations/13-deploying-application.html) | 20 min |
| 13:30 – 13:50 | [M14 — Observing Your Application](presentations/14-observing-application.html) | 20 min |
| 13:50 – 14:05 | *Break*                                          | 15 min |
| 14:05 – 14:50 | **[Lab 7a — Instrument Lambda with X-Ray](labs/lab7a-xray-instrument.html)** | 45 min |
| 14:50 – 15:45 | **[Lab 7b — SAM, Trace Map & Cleanup](labs/lab7b-sam-deploy.html)** | 55 min |
| 15:45 – 16:00 | [M15 — Course Wrap-up](presentations/15-course-wrap-up.html) | 15 min |

**Day 3 totals:** lecture 95 min · lab 235 min · **lab share 71%**

### Course totals

| Metric                     | Time           |
| -------------------------- | -------------- |
| Lecture (15 modules)       | 4h 35m         |
| **Hands-on lab (15 labs)** | **10h 55m**    |
| Total working time         | 15h 30m        |
| **Lab share**              | **~70%** ✓     |

## Lab Dependency Chain

Labs build on each other conceptually, but each has a **bootstrap fallback** so no
lab truly requires successful completion of the previous one. A student who falls
behind runs `bash ~/environment/dev-on-aws/bootstrap.sh <labId>` and the script
creates-or-reuses every resource that lab needs, then exports the expected env
vars to `~/.dev-on-aws.env`:

```
1a  (REQUIRED — Cloud9 + LabRole + repo clone)
 ↓
1b → 1c            bootstrap.sh 1b → env vars
 ↓
2a → 2b            bootstrap.sh 2a|2b → env vars
 ↓
3a → 3b            bootstrap.sh 3a|3b → env vars
 ↓
4a → 4b            bootstrap.sh 4a|4b → bucket + table (+ role, fn for 4b)
 ↓
5a                 bootstrap.sh 5a    → + Lambda role/function
 ↓
6a → 6b → 6c       bootstrap.sh 6a|6b|6c → + API + Cognito (+ site for 6c)
 ↓
7a → 7b            bootstrap.sh 7a|7b → full stack through Cognito
```

The only hard dependency is **Lab 1a** (Cloud9 environment + LabRole attached +
AMTC off + course repo cloned). Everything after that is reachable from the
bootstrap script. The script is idempotent — re-running it detects existing
resources and skips them.

## Repository Layout

```
dev_on_aws/
├── README.md                ← this file
├── Developing on AWS.docx   ← source outline
├── presentations/           ← 15 teaching decks
│   ├── 01-course-overview.html
│   └── … 14 more …
├── labs/                    ← 15 hands-on lab decks
│   ├── lab1a-signin-orientation.html
│   └── … 14 more …
└── labs/files/              ← source files students clone via GitHub in Lab 1a
    ├── bootstrap.sh          ← "catch me up" setup for any lab
    ├── lab1/  (smoke_test.py)
    ├── lab2/  (seed.py, process.py, make_get_url.py, make_put_url.py)
    ├── lab3/  (seed.py, bulk_load.py, query_filter.py, query_gsi.py, update_conditional.py, scan_demo.py)
    ├── lab4/  (handler.py, lambda-perms.json, notify.json)
    ├── lab6/  (add_methods.sh, site-policy.json, web/*.html)
    └── lab7/  (template.yaml, python/handler.py, python/requirements.txt)
```

## Course-Files Distribution

Course materials live in the public GitHub repo
[**jwkidd3/dev_on_aws**](https://github.com/jwkidd3/dev_on_aws). Lab 1a
Step 4 has students clone it and copy the supporting files into their
workspace:

```
cd ~/environment
git clone https://github.com/jwkidd3/dev_on_aws
cp -r dev_on_aws/labs/files ./dev-on-aws
```

From then on, every lab opens files that are already on disk under
`~/environment/dev-on-aws/`. No copy-paste of large blocks into a terminal.

## Prerequisites Students Should Bring

- A laptop with a modern browser (Chrome, Firefox, Safari, or Edge)
- Reliable internet connection
- That's it — Cloud9 provides the IDE, AWS CLI, Python + `boto3`, `git`, `curl`, `jq`, Docker, and SAM CLI
