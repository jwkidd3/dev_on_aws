# 🧪 Lab 1a — Sign In & Create Your Cloud9 Environment

*Hands-On Lab · 30 min · Console · Day 1 — Environment Setup*

## Objectives & Access (2 min)

- Sign into the class account
- Create your own Cloud9 IDE (m5.large, SSH)
- Attach `LabRole` and turn off managed temporary credentials
- Clone the course repo and verify the files landed
- Run the class setup script (tools + 100 GB disk), then reboot

> **Console:** `https://kiddcorp.signin.aws.amazon.com/console`
> **User:** `user1`, `user2`, … assigned at class start · **Region:** `us-east-1`

> 🏷️ **Unique names — one shared account.** The whole class works in the same AWS account and region, and you're an admin: nothing stops you from overwriting or deleting a classmate's resource with the same name. Every name below uses `user1` — **replace it with your own user ID** (`$USER_ID` does this automatically in the terminal; in the Console you type it).
>
> - Cloud9 environment `dev-on-aws-user1` (its EC2 instance becomes `aws-cloud9-dev-on-aws-user1-…`)
> - The setup script resizes **your instance's own** disk — it finds it from instance metadata, never by name

## Step 1 — Sign In (2 min)

1. Open the console URL in an incognito window
2. Sign in with your assigned user and password
3. Top-right region selector → **US East (N. Virginia) us-east-1**

## Step 2 — Create Your Cloud9 Environment (8 min)

1. Console search → **Cloud9** → **Create environment**
2. Name: `dev-on-aws-user1` (replace with your user)
3. Environment type: **New EC2 instance**
4. Instance type: **m5.large**
5. Platform: **Amazon Linux 2023**
6. Timeout: **30 minutes**
7. Connection: **Secure Shell (SSH)** ← not SSM
8. Network: default VPC, any public subnet
9. **Create** — provisioning takes ~3 min

## Step 3 — Attach LabRole to Your Cloud9 EC2 (4 min)

> By default Cloud9 uses **AWS Managed Temporary Credentials** (AMTC), which block several IAM, STS, and Lambda calls our labs need. We fix this by pointing the underlying EC2 at the pre-provisioned `LabRole` and turning AMTC off.

1. Open the **EC2** console → **Instances**
2. Find the instance named `aws-cloud9-dev-on-aws-userN-…` — that's the EC2 behind your Cloud9
3. Select it → **Actions** → **Security** → **Modify IAM role**
4. Choose `LabRole` → **Update IAM role**

## Step 4 — Disable Managed Credentials in Cloud9 (2 min)

1. Back in the Cloud9 IDE, top-left gear icon → **Preferences**
2. Left panel → **AWS Settings** → **Credentials**
3. Toggle **AWS managed temporary credentials** to **OFF**
4. Close the Preferences tab

> With AMTC off, the SDK/CLI fall through to IMDS and pick up `LabRole`'s credentials — no `aws configure`, no keys on disk. If the Cloud9 instance is stopped and restarted, AMTC stays off; if you delete and recreate the Cloud9, redo both steps.

## Step 5 — Clone the Course Repo & Verify (3 min)

> In the Cloud9 terminal (bottom pane):

```bash
cd ~/environment
git clone https://github.com/jwkidd3/dev_on_aws
cp -r dev_on_aws/labs/files ./dev-on-aws
cd ~/environment/dev-on-aws && ls
```

> Expect `bootstrap.sh  cleanup.sh  lab1 … lab7  refresh-token.sh  setup-cloud9.sh`. Raise your hand if anything's missing.

## Step 6 — Run the Class Setup Script, Then Reboot (5 min)

```bash
bash ~/environment/dev-on-aws/setup-cloud9.sh
```

> Open `setup-cloud9.sh` in the editor while it runs (about a minute). It:

- **Checks you're running as `LabRole`.** If it stops here, Steps 3–4 aren't done; fix them and re-run.
- **Installs the class tools:** boto3, jq, zip, Python 3.12 + pip, the latest SAM CLI, and Docker access for your user
- **Grows your disk from 10 GB to 100 GB.** Lab 7b's `sam build --use-container` pulls multi-GB Docker images.
- **Ends with a ⚠️ REBOOT REQUIRED box**

When you see the box, run:

```bash
sudo reboot
```

> The IDE shows *Reconnecting…* for about a minute, then comes back with your files intact. The reboot applies Docker group access and finishes the disk grow.

## Step 7 — Confirm After the Reboot (2 min)

```bash
aws sts get-caller-identity --query Arn --output text   # assumed-role/LabRole/i-…
df -h /                                                 # Size ≈ 100G
docker ps && sam --version                              # no sudo needed
```

> ARN shows `user/user1` or an AMTC session? Redo Step 4, since Cloud9 sometimes needs a second toggle. Disk still 10G or `docker ps` permission denied? You skipped the reboot; run `sudo reboot`. The script is safe to re-run at any time.

> `bootstrap.sh` is the "catch me up" script. If you ever fall behind, `bash ~/environment/dev-on-aws/bootstrap.sh <labId>` creates-or-reuses every resource that lab needs. Each later lab has a reminder.

## Success Criteria (2 min)

- ✅ Cloud9 `dev-on-aws-userN` created on **m5.large** with **SSH**
- ✅ Underlying EC2 instance has `LabRole` attached and AMTC is off
- ✅ Setup script finished and you rebooted
- ✅ After the reboot: `LabRole` ARN, ~100 GB root disk, `docker ps` and `sam --version` work without `sudo`

> Class conventions — shown now, enforced in later labs:

- **One shared account:** the whole class works in the same AWS account and region. Everything you create carries your user — `student-user1-*`, `Items-user1`, `lab4-user1` — so 25 people never collide on a name.
- **The prefix is a convention, not a wall:** you're an administrator, so IAM will *not* stop you touching someone else's resources. Only ever modify or delete names that contain **your** user.
- **Editor vs. terminal:** source/config files are authored in the Cloud9 editor; commands ≤ ~5 lines go into the terminal.
