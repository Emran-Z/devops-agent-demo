#!/usr/bin/env bash
# reset-demo.sh — restore the healthy app version on the EC2 via SSM.
#
# Use this after each demo run to get back to the clean baseline.
#
# Prerequisites (set as env vars or edit the defaults below):
#   AWS_REGION        — e.g. us-east-1
#   EC2_INSTANCE_ID   — i-0abc123...
#   DEPLOY_BUCKET     — S3 bucket used by the GitHub Actions workflow
#
# The script assumes that app/ (healthy version) has already been uploaded
# to S3 by a prior workflow run.  If not, run:
#   aws s3 sync app/ s3://<DEPLOY_BUCKET>/devops-agent-demo/app/ --delete
# before running this script.

set -euo pipefail

AWS_REGION="${AWS_REGION:?Set AWS_REGION}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:?Set EC2_INSTANCE_ID}"
DEPLOY_BUCKET="${DEPLOY_BUCKET:?Set DEPLOY_BUCKET}"
APP_DIR="/opt/devops-agent-demo-app"

echo "==> Uploading healthy app to S3 ..."
aws s3 sync app/ \
    "s3://${DEPLOY_BUCKET}/devops-agent-demo/app/" \
    --delete \
    --exclude "__pycache__/*" \
    --exclude "*.pyc" \
    --region "$AWS_REGION"

echo "==> Sending SSM command to restore healthy app on ${EC2_INSTANCE_ID} ..."
COMMAND_ID=$(aws ssm send-command \
    --region "$AWS_REGION" \
    --instance-ids "$EC2_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Reset demo to healthy baseline" \
    --parameters "commands=[
        \"#!/bin/bash\",
        \"set -euo pipefail\",
        \"export PATH=/usr/local/bin:/usr/bin:/bin:\$PATH\",
        \"rm -rf ${APP_DIR}/venv\",
        \"aws s3 sync s3://${DEPLOY_BUCKET}/devops-agent-demo/app/ ${APP_DIR}/\",
        \"python3 -m venv ${APP_DIR}/venv\",
        \"${APP_DIR}/venv/bin/pip install -q --upgrade pip\",
        \"${APP_DIR}/venv/bin/pip install -q -r ${APP_DIR}/requirements.txt\",
        \"chown -R ubuntu:ubuntu ${APP_DIR}\",
        \"systemctl restart devops-agent-demo\",
        \"sleep 2 && systemctl is-active devops-agent-demo && echo 'Service restarted OK'\"
    ]" \
    --timeout-seconds 90 \
    --query "Command.CommandId" \
    --output text)

echo "==> Waiting for SSM command ${COMMAND_ID} ..."
for i in $(seq 1 18); do
    STATUS=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --query "Status" \
        --output text 2>/dev/null || echo "Pending")

    echo "    [${i}/18] status: ${STATUS}"

    case "$STATUS" in
        Success)
            echo ""
            echo "==> Healthy app restored successfully."

            # Fetch the EC2 public IP from SSM Parameter Store
            EC2_IP=$(aws ssm get-parameter \
                --region "$AWS_REGION" \
                --name "/devops-agent-demo/ec2-public-ip" \
                --query "Parameter.Value" \
                --output text 2>/dev/null || echo "")

            if [ -n "$EC2_IP" ]; then
                echo "==> Smoke-testing http://${EC2_IP}:5000/health ..."
                HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://${EC2_IP}:5000/health" || echo "ERR")
                echo "    HTTP status: ${HTTP}"
                [ "$HTTP" = "200" ] && echo "    Health check PASSED." || echo "    WARNING: health check returned ${HTTP}"
            fi
            exit 0
            ;;
        Failed|Cancelled|TimedOut|Undeliverable)
            echo "ERROR: SSM command failed with status ${STATUS}."
            aws ssm get-command-invocation \
                --region "$AWS_REGION" \
                --command-id "$COMMAND_ID" \
                --instance-id "$EC2_INSTANCE_ID" \
                --query "StandardErrorContent" \
                --output text
            exit 1
            ;;
    esac
    sleep 5
done

echo "ERROR: Timed out waiting for SSM command."
exit 1
