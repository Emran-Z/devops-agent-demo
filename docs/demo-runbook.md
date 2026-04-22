# Live Demo Runbook — AWS DevOps Agent Webinar (May 3, 2026)

**Slot:** 1:00–2:00 PM GMT+3  
**Demo window:** ~20 minutes (within the 60-minute session)

---

## Windows to have open before you go live

| Window | What |
|---|---|
| Terminal A | Local terminal for running scripts |
| Terminal B | `watch -n 5 'curl -s http://<EC2_IP>:5000/metrics'` — live memory view |
| Browser tab 1 | AWS CloudWatch → Alarms dashboard |
| Browser tab 2 | AWS DevOps Agent console |
| Browser tab 3 | GitHub repo → Actions tab |
| Browser tab 4 | Slack channel receiving agent notifications |

---

## T-5 min — Final pre-demo check

```bash
# Confirm healthy app is up
curl http://<EC2_IP>:5000/health
# Expected: {"status": "ok", "version": "1.0.0-healthy"}

# Confirm CloudWatch alarm is in OK state (check browser tab 1)

# Confirm memory baseline is low
curl http://<EC2_IP>:5000/metrics
# Expected: process_rss_mb ~50–80, system_used_pct ~20–30
```

---

## Minute-by-minute script

### 0:00 — Introduce the demo scenario (2 min)

> "We have a Python Flask inventory API running on an EC2 t3.micro — 1 GB of RAM.
> Everything looks healthy right now. In a moment we'll push a commit that a developer
> might have accidentally slipped in: a result-caching pattern with no eviction policy.
> We'll watch AWS DevOps Agent catch it, diagnose it, and tell us exactly what to fix —
> without us touching anything."

Show **Terminal B** (`watch` output) — point out low RSS.

---

### 2:00 — Push the buggy commit (1 min)

```bash
# In Terminal A — copy buggy app over the healthy one and push
cp app-buggy/app.py app/app.py
git add app/app.py
git commit -m "perf: cache process results in memory for faster repeat lookups"
git push origin main
```

Switch to **Browser tab 3 (GitHub Actions)** — show the workflow starting automatically.

> "The commit message looks innocent — 'cache process results for faster repeat lookups'.
> GitHub Actions picks it up and deploys to EC2 via SSM, with no AWS credentials stored
> anywhere — pure OIDC."

Wait for the Actions run to show **Success** (~60–90 s).

---

### 3:30 — Confirm new version is live (30 s)

```bash
curl http://<EC2_IP>:5000/health
# Expected: {"status": "ok", "version": "1.1.0-buggy"}
```

---

### 4:00 — Generate load to accelerate the leak (1 min)

```bash
# Terminal A — 4 requests/sec; each request adds ~2 MB to the unbounded cache
./scripts/trigger-leak.sh <EC2_IP> 4 900
```

Switch to **Terminal B** — watch `process_rss_mb` and `system_used_pct` climb in real time.

> "This simulates production traffic hitting that new endpoint.
> Watch the RSS — it's already climbing. Every call to /api/process caches
> its result in an unbounded list. Nothing is ever evicted."

---

### 5:30 — Memory is visibly rising (2 min narration)

Point to Terminal B — RSS should be at 200–400 MB and rising.  
Point to CloudWatch Alarms tab — alarm moves from **OK → In alarm** when `mem_used_percent > 70%`.

> "CloudWatch is watching `mem_used_percent`. Once it breaches 70% for two consecutive
> 1-minute periods, it fires — that signal goes straight to AWS DevOps Agent."

---

### 7:30 — DevOps Agent receives the alarm (1 min)

Switch to **Browser tab 2 (DevOps Agent console)**.

> "The agent received the CloudWatch alarm. Watch what it does next — it doesn't just
> page someone. It starts investigating autonomously."

Show the agent's investigation steps as they appear:
- Pulling CloudWatch metrics history
- Correlating the memory spike with recent deployment events
- Examining the commit that deployed immediately before the spike

---

### 9:00 — Agent posts findings to Slack (2 min)

Switch to **Browser tab 4 (Slack)**.

The agent should have posted a message containing:
- The alarm name and current severity
- A timeline showing memory was flat → spiked after commit `<SHA>`
- The commit message ("perf: cache process results...")
- Root cause summary: `_leak_storage` list in `app.py` grows without bound
- Recommendation: add an eviction limit or use `functools.lru_cache`

> "No human looked at this. The agent correlated a CloudWatch memory alarm with a
> deployment event and a code change — and pinpointed the bug."

---

### 11:00 — Walk through the agent's investigation trail (3 min)

Back in the **DevOps Agent console**, walk through each step the agent took:

1. Alarm received → fetched `mem_used_percent` metric for the past hour
2. Noticed the inflection point matched the SSM deploy timestamp
3. Fetched the GitHub commit diff for that deploy
4. Identified `_leak_storage.append(...)` with no eviction logic on line 84
5. Generated prevention recommendations

---

### 14:00 — Reset for Q&A (1 min)

```bash
# Stop the load generator (Ctrl-C in Terminal A)
# Restore healthy app
./scripts/reset-demo.sh
```

Confirm memory drops back to baseline in Terminal B.

> "And just like that — one command, we're back to the healthy baseline.
> The agent already has everything documented in Slack."

---

## Fallback plan

If the CloudWatch alarm is slow to fire (evaluation period = 2 × 1 min):

1. You can manually push the alarm into **ALARM** state for the demo:
   ```bash
   aws cloudwatch set-alarm-state \
     --alarm-name "devops-agent-demo-high-memory" \
     --state-value ALARM \
     --state-reason "Manual trigger for demo"
   ```
2. This still exercises the full agent investigation and Slack notification flow.
3. Reset afterward:
   ```bash
   aws cloudwatch set-alarm-state \
     --alarm-name "devops-agent-demo-high-memory" \
     --state-value OK \
     --state-reason "Demo reset"
   ```

---

## Key talking points to weave in

- **No AWS keys in GitHub** — OIDC means zero long-lived credentials
- **SSM, not SSH** — no port 22 required; the agent communicates over HTTPS
- **mem_used + mem_used_percent** — two CloudWatch metrics from the CW agent; the alarm uses `mem_used_percent` for the threshold but the agent can show both in its investigation
- **Agent Spaces** — the agent is scoped to this project's space; it only has access to the resources it needs
- **Prevention, not just detection** — the agent doesn't just alert, it tells you what to fix and why
