# AWS DevOps Agent — Live Demo

> Companion repository for the **AWS DevOps Agent Webinar** (May 3, 2026 · 1–2 PM GMT+3).

This repo contains everything needed to run the live incident-detection demo: a Flask app, deployment scripts, and a step-by-step runbook. The EC2 instance and CloudWatch agent are already provisioned.

---

## Demo Scenario

| Phase | What happens |
|---|---|
| **Baseline** | Healthy Flask app running on EC2 t3.micro (1 GB RAM). CloudWatch alarms armed. AWS DevOps Agent watching. |
| **Trigger** | A commit that introduces a memory leak is pushed to `main`. GitHub Actions deploys it automatically. |
| **Leak** | The `/api/process` endpoint accumulates request data in an unbounded global list. Memory climbs ~100 MB/min under load. |
| **Alarm** | CloudWatch `mem_used_percent > 70%` alarm fires → SNS → AWS DevOps Agent. |
| **Investigation** | Agent pulls CloudWatch metrics, reads recent deployment events, correlates the timing of the commit with the memory spike. |
| **Slack** | Agent posts findings to the channel with root-cause summary, offending commit SHA, and the exact line of code. |
| **Prevention** | Agent generates fix recommendations and optionally opens a GitHub issue. |

---

## Repository Layout

```
devops-agent-demo/
├── app/                           # Healthy version of the Flask app
│   ├── app.py
│   └── requirements.txt
├── app-buggy/                     # Buggy version — memory leak introduced here
│   ├── app.py
│   └── requirements.txt
├── infra/
│   └── devops-agent-demo.service  # systemd unit file (install once on EC2)
├── scripts/
│   ├── trigger-leak.sh            # Generate load to accelerate memory climb
│   └── reset-demo.sh              # Restore healthy app via SSM
├── .github/workflows/
│   └── deploy.yml                 # Auto-deploy on push to main (OIDC + SSM, no keys)
└── docs/
    ├── setup.md                   # One-time AWS + DevOps Agent setup guide
    └── demo-runbook.md            # Minute-by-minute live demo script
```

---

## Quick Start

```bash
# 1. Deploy the healthy app (one-time baseline setup)
export AWS_REGION=<YOUR_REGION>
export EC2_INSTANCE_ID=<YOUR_INSTANCE_ID>
export DEPLOY_BUCKET=<YOUR_S3_BUCKET>
./scripts/reset-demo.sh

# 2. Verify the app is up
curl http://<EC2_PUBLIC_IP>:5000/health

# 3. On demo day — push the buggy commit
cp app-buggy/app.py app/app.py
git add app/app.py
git commit -m "perf: cache process results in memory for faster repeat lookups"
git push origin main

# 4. Generate load to accelerate the memory leak
./scripts/trigger-leak.sh <EC2_PUBLIC_IP> 4 900
```

See [docs/setup.md](docs/setup.md) for full AWS + DevOps Agent configuration, and [docs/demo-runbook.md](docs/demo-runbook.md) for the minute-by-minute live script.

---

## Prerequisites

- AWS account with DevOps Agent enabled in your region
- EC2 t3.micro already running Ubuntu with CloudWatch agent installed
- GitHub repository variables configured (see `docs/setup.md`)
- Python 3.11+ (on EC2)
- Slack workspace connected to AWS DevOps Agent
