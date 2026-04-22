# One-Time Setup Guide

Everything here is done **once before the webinar**. The EC2 instance is already running with the CloudWatch agent installed.

---

## 1. Bootstrap the EC2 instance

SSH into the instance and run these commands once to prepare the app directory and install the systemd service.

```bash
# Create app directory
sudo mkdir -p /opt/devops-agent-demo-app
sudo chown ubuntu:ubuntu /opt/devops-agent-demo-app

# Install Python venv tooling (if not already present)
sudo apt-get install -y python3-venv python3-pip

# Create virtual environment
python3 -m venv /opt/devops-agent-demo-app/venv

# Install the systemd service unit
sudo cp infra/devops-agent-demo.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable devops-agent-demo
```

---

## 2. S3 bucket for deployment artefacts

Create a bucket (or reuse an existing one) for GitHub Actions to stage app files:

```bash
aws s3 mb s3://<YOUR_BUCKET_NAME> --region <YOUR_REGION>
```

The bucket does **not** need to be public. The EC2 IAM role needs `s3:GetObject` and `s3:ListBucket` on it.

---

## 3. IAM role for EC2

Attach a policy to the EC2 instance role that allows:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::<YOUR_BUCKET_NAME>",
    "arn:aws:s3:::<YOUR_BUCKET_NAME>/*"
  ]
}
```

Also ensure the role has `ssm:*` permissions (required for SSM agent) and `cloudwatch:PutMetricData` (required for the CW agent memory metrics).

---

## 4. IAM role for GitHub Actions (OIDC)

### 4a. Create the OIDC provider (once per AWS account)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 4b. Create the deploy role

Trust policy — replace `<ORG>/<REPO>`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<ORG>/<REPO>:ref:refs/heads/main"
      }
    }
  }]
}
```

Permissions the role needs:

| Service | Actions |
|---|---|
| S3 | `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on the deploy bucket |
| SSM | `ssm:SendCommand`, `ssm:GetCommandInvocation` on the EC2 instance |
| SSM | `ssm:GetParameter` on `/devops-agent-demo/*` |

---

## 5. GitHub repository variables

Go to **Settings → Secrets and variables → Actions → Variables** and add:

| Name | Example value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789012:role/devops-agent-demo-deploy` |
| `DEPLOY_BUCKET` | `my-devops-demo-artefacts` |
| `EC2_INSTANCE_ID` | `i-0abc1234567890def` |

---

## 6. Store the EC2 public IP in SSM Parameter Store

The GitHub Actions smoke-test and `reset-demo.sh` look up the IP here:

```bash
aws ssm put-parameter \
  --name "/devops-agent-demo/ec2-public-ip" \
  --value "<EC2_PUBLIC_IP>" \
  --type String \
  --overwrite
```

---

## 7. Initial deployment (healthy app)

```bash
# From the repo root on your local machine
export AWS_REGION=<YOUR_REGION>
export DEPLOY_BUCKET=<YOUR_BUCKET_NAME>
export EC2_INSTANCE_ID=<YOUR_INSTANCE_ID>

./scripts/reset-demo.sh
```

Verify:

```bash
curl http://<EC2_PUBLIC_IP>:5000/health
# → {"status": "ok", "version": "1.0.0-healthy"}
```

---

## 8. CloudWatch alarm

The EC2 CloudWatch agent reports `mem_used_percent` under the `CWAgent` namespace. Create an alarm on that metric:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "devops-agent-demo-high-memory" \
  --alarm-description "Memory utilization > 70% on demo EC2" \
  --metric-name mem_used_percent \
  --namespace CWAgent \
  --dimensions Name=InstanceId,Value=$EC2_INSTANCE_ID \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data missing
```

Connect the SNS topic to the AWS DevOps Agent as an alarm source inside the Agent Spaces console.

---

## 9. Pre-demo checklist

Run through this list the morning of May 3:

- [ ] EC2 instance is running and healthy app responds on port 5000
- [ ] `curl http://<EC2_IP>:5000/health` returns `200`
- [ ] CloudWatch alarm is in **OK** state
- [ ] AWS DevOps Agent is connected to the GitHub repo and the Slack channel
- [ ] A test alarm was fired and appeared in Slack (fire manually, then reset)
- [ ] `scripts/reset-demo.sh` was run and confirmed working
- [ ] `scripts/trigger-leak.sh` was tested (rate ≤ 2 rps) and confirmed memory rises
