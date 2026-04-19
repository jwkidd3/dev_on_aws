# Developing on AWS

A 3-day, introductory-level, **lab-heavy** workshop for developers who want to build a real serverless web application on AWS using the SDKs, CLI, and the Console. **15 hands-on labs**, each ≤ 45 minutes, build the application piece by piece inside AWS Cloud9.

## Audience

Software developers, solution architects, and IT professionals with:

- AWS Technical Essentials-level knowledge or equivalent
- Working programming experience in **Python**, **.NET (C#)**, or **Java**

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
- **Pre-seeded per student:** the IAM user `userN` plus prefix-enforcing policies attached to that user. *Everything else* — Cloud9, DynamoDB tables, Lambda roles, S3 buckets, Cognito pools, API Gateway, SAM stacks — students create in the labs.
- **Prefix convention:** every resource a student creates starts with their user ID (`student-user1-…`, `Items-user1`, `lab4-user1`, `StudentLambdaRole-user1`). The IAM policies enforce this.
- **Credentials:** AWS Managed Temporary Credentials flow from the Cloud9-owning IAM user — no `aws configure`, no access keys on laptops.
- **Editor vs. terminal:** class convention set in Lab 1a — source/config files are authored in the Cloud9 **editor**; commands ≤ ~5 lines go into the **terminal**. Never paste multi-line source into a shell prompt.

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
| 10:30 – 11:15 | **[Lab 1a — Sign In, Cloud9 & Orientation](labs/lab1a-signin-orientation.html)** | 45 min |
| 11:15 – 12:00 | **[Lab 1b — First SDK Call in Cloud9](labs/lab1b-cli-sdk-profile.html)** | 45 min |
| 12:00 – 13:00 | *Lunch*                                          | 60 min |
| 13:00 – 13:45 | **[Lab 1c — IAM Policy Authoring](labs/lab1c-iam-policy.html)** | 45 min |
| 13:45 – 13:57 | [M5 — Getting Started with Storage](presentations/05-getting-started-storage.html) | ~12 min |
| 13:57 – 14:10 | [M6 — Processing Your Storage Operations](presentations/06-processing-storage-operations.html) | ~13 min |
| 14:10 – 14:25 | *Break*                                          | 15 min |
| 14:25 – 15:10 | **[Lab 2a — S3 in the Console](labs/lab2a-s3-crud.html)** | 45 min |
| 15:10 – 15:55 | **[Lab 2b — S3 via SDK & Presigned URLs](labs/lab2b-s3-presigned.html)** | 45 min |
| 15:55 – 16:00 | *Day-1 wrap / Q&A*                                | 5 min  |

**Day 1 totals:** lecture 100 min · lab 225 min · **lab share 69%**

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
| **Hands-on lab (15 labs)** | **11h 25m**    |
| Total working time         | 16h (3 × 5h 20m) |
| **Lab share**              | **~71%** ✓     |

## Lab Dependency Chain

Labs within a day build on earlier ones. Blocks across days depend on prior days:

```
1a → 1b → 1c                 (Cloud9 / IAM)
      ↓
2a → 2b                      (S3 — uses student-userN- prefix)
      ↓
3a → 3b                      (DynamoDB — uses Items-userN)
      ↓
4a → 4b                      (Lambda — needs 2a bucket, 3a table)
      ↓
5a                           (API Gateway — needs 4b function)
      ↓
6a → 6b → 6c                 (Cognito + capstone — creates site bucket)
      ↓
7a → 7b                      (X-Ray + SAM — needs 6a pool, 6b client)
```

A student who falls behind can copy another student's `~/environment/dev-on-aws/` directory forward; labs are self-contained, so any one student's end-state lets another skip ahead cleanly.

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
└── labs/files/              ← source files students sync into Cloud9
    ├── lab1/  (smoke_test.py, Program.cs, SmokeTest.java)
    ├── lab3/  (seed.py, bulk_load.py)
    ├── lab4/  (handler.py, lambda-perms.json, notify.json)
    ├── lab6/  (add_methods.sh, site-policy.json, web/*.html)
    └── lab7/  (template.yaml, python/handler.py)
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
- That's it — Cloud9 provides the IDE, AWS CLI, Python, .NET, Java, `git`, `curl`, `jq`, Docker, and SAM CLI
