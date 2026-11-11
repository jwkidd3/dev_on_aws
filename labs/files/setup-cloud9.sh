#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Class setup for your Cloud9 environment — run ONCE in Lab 1a, after LabRole is
# attached and AWS managed temporary credentials are OFF:
#
#     bash ~/environment/dev-on-aws/setup-cloud9.sh
#
# 1. Installs / updates the class tools: boto3, jq, zip/unzip, Python 3.12 + pip,
#    the latest AWS SAM CLI, and makes sure Docker is running for you.
# 2. Grows THIS instance's root EBS volume to 100 GB (sam build --use-container
#    pulls multi-GB Docker images; the default 10 GB fills up).
# 3. Tells you to reboot.
#
# Safe in the shared class account: it only ever touches the instance it runs on
# (found via instance metadata). Safe to re-run — finished steps are skipped.
# -----------------------------------------------------------------------------
set -uo pipefail

SIZE_GB="${1:-100}"
say()  { printf "\n\033[1m── %s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
die()  { printf "  \033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ── Preflight: on EC2, running as LabRole ───────────────────────────────────
say "Preflight"
IMDS=http://169.254.169.254/latest
TOKEN=$(curl -sf -X PUT "$IMDS/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 600") \
  || die "No instance metadata — run this in your Cloud9 terminal, not on a laptop."
md() { curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/meta-data/$1"; }
INSTANCE_ID=$(md instance-id)
export AWS_DEFAULT_REGION=$(md placement/region)
ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
case "$ARN" in
  *assumed-role/LabRole/*) ok "running as LabRole on $INSTANCE_ID ($AWS_DEFAULT_REGION)" ;;
  *) die "Running as '${ARN:-unknown}'. Finish Lab 1a Steps 3–4 (attach LabRole, turn managed credentials OFF), then re-run." ;;
esac

# ── 1. Class tools ──────────────────────────────────────────────────────────
say "Class tools"
sudo dnf install -y -q jq zip unzip git python3-pip cloud-utils-growpart >/dev/null 2>&1 \
  && ok "jq, zip, unzip, git, pip, growpart" || warn "dnf install of base tools reported an error"

pip3 install --user --quiet --upgrade boto3 >/dev/null 2>&1 \
  && ok "boto3 $(python3 -c 'import boto3; print(boto3.__version__)')" || warn "boto3 install failed"

# Python 3.12 matches the Lambda runtime — lets `sam build` work even without Docker
if ! command -v python3.12 >/dev/null 2>&1; then
  sudo dnf install -y -q python3.12 >/dev/null 2>&1 || warn "python3.12 not installable from dnf"
fi
if command -v python3.12 >/dev/null 2>&1 && ! python3.12 -m pip --version >/dev/null 2>&1; then
  sudo dnf install -y -q python3.12-pip >/dev/null 2>&1 \
    || sudo python3.12 -m ensurepip --upgrade >/dev/null 2>&1 || true
fi
python3.12 -m pip --version >/dev/null 2>&1 && ok "Python 3.12 + pip" || warn "Python 3.12 + pip not available (Lab 7b will use Docker instead)"

case "$(uname -m)" in aarch64) SAM_PKG=arm64 ;; *) SAM_PKG=x86_64 ;; esac
TMPD=$(mktemp -d)
if curl -sSfL -o "$TMPD/sam.zip" \
     "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-$SAM_PKG.zip" \
   && unzip -q -o "$TMPD/sam.zip" -d "$TMPD/sam" \
   && sudo "$TMPD/sam/install" --update >/dev/null 2>&1; then
  ok "$(sam --version 2>/dev/null)"
else
  warn "SAM CLI update failed — keeping $(sam --version 2>/dev/null || echo 'none')"
fi
rm -rf "$TMPD"

command -v docker >/dev/null 2>&1 || sudo dnf install -y -q docker >/dev/null 2>&1
sudo systemctl enable --now docker >/dev/null 2>&1
sudo usermod -aG docker "$(id -un)" >/dev/null 2>&1
systemctl is-active --quiet docker && ok "Docker running (group membership applies after reboot)" \
  || warn "Docker is not running"

# ── 2. Root volume → ${SIZE_GB} GB ──────────────────────────────────────────
say "Disk: root volume → ${SIZE_GB} GB"
ROOT_DEVNAME=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].RootDeviceName' --output text)
VOL=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --output text \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName=='$ROOT_DEVNAME'].Ebs.VolumeId | [0]")
CUR=$(aws ec2 describe-volumes --volume-ids "$VOL" --query 'Volumes[0].Size' --output text)
if [ "$CUR" -ge "$SIZE_GB" ]; then
  ok "$VOL is already ${CUR} GB"
else
  aws ec2 modify-volume --volume-id "$VOL" --size "$SIZE_GB" >/dev/null \
    || die "modify-volume on $VOL failed"
  printf "  … resizing %s from %s GB to %s GB" "$VOL" "$CUR" "$SIZE_GB"
  for i in $(seq 1 60); do
    STATE=$(aws ec2 describe-volumes-modifications --volume-ids "$VOL" \
      --query 'VolumesModifications[0].ModificationState' --output text 2>/dev/null)
    case "$STATE" in optimizing|completed) break ;; esac
    printf "."; sleep 5
  done; echo
  ok "EBS volume is ${SIZE_GB} GB ($STATE)"
fi

# Grow the partition + filesystem online; the reboot finishes it if the kernel
# hasn't noticed the bigger disk yet (cloud-init grows the root fs at boot).
ROOT_SRC=$(findmnt -n -o SOURCE /)
DISK=$(lsblk -no PKNAME "$ROOT_SRC" | head -1)
PART=$(cat "/sys/class/block/$(basename "$ROOT_SRC")/partition" 2>/dev/null)
sleep 3
[ -n "$DISK" ] && [ -n "$PART" ] && sudo growpart "/dev/$DISK" "$PART" >/dev/null 2>&1
case "$(findmnt -n -o FSTYPE /)" in
  xfs)  sudo xfs_growfs -d / >/dev/null 2>&1 ;;
  ext4) sudo resize2fs "$ROOT_SRC" >/dev/null 2>&1 ;;
esac
ok "filesystem: $(df -h / | awk 'NR==2 {print $2 " total, " $4 " free"}')"

touch ~/.dev-on-aws-setup-done

# ── 3. Reboot notice ────────────────────────────────────────────────────────
cat <<'EOF'

  ┌──────────────────────────────────────────────────────────────────────┐
  │  ⚠️  REBOOT REQUIRED                                                  │
  │                                                                      │
  │  Run:   sudo reboot                                                  │
  │                                                                      │
  │  The IDE shows "Reconnecting…" for about a minute, then comes back.  │
  │  The reboot applies Docker group access and completes the disk grow. │
  │  Your files in ~/environment are kept.                               │
  └──────────────────────────────────────────────────────────────────────┘
EOF
