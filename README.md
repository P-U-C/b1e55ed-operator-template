# b1e55ed Operator Template (OpenClaw)

Operational template for running a **b1e55ed** instance with **OpenClaw**.

This is not a trading-persona pack. It is an operator runbook + workspace starter for keeping the engine healthy:
- producers emitting
- outcome resolver running
- task queue draining
- review/b1e55ing automation not getting dropped

Use this when:
- you are deploying b1e55ed for the first time, or
- you are spinning a second operator instance (home lab, backup host, separate environment).

---

## Prerequisites

1. **OpenClaw installed and authenticated**
   - `openclaw --version`
   - `openclaw cron list`

2. **b1e55ed installed locally**
   - `b1e55ed --help`
   - default API: `http://localhost:5050`
   - default dashboard: `http://localhost:5051`

3. **Telegram bot connected to OpenClaw**
   - OpenClaw can receive/send operator alerts.

4. **GitHub Personal Access Token** (`GH_TOKEN`)
   - Required for queue automation (`b1e55ing`, review council).
   - Recommended scopes: `repo`, `read:org`, `workflow`.

---

## Setup (5–10 min)

### Step 1 — Install b1e55ed

```bash
curl -sSf https://raw.githubusercontent.com/P-U-C/b1e55ed/main/install.sh | BRANCH=develop bash
```

### Step 2 — Connect a Telegram bot ⚠️ Do this before running setup {#step-2--connect-a-telegram-bot}

You'll need a bot token for OpenClaw to send you alerts. Get one from [@BotFather](https://t.me/BotFather):

```
/newbot → follow prompts → copy the token (looks like 123456:ABC-xxx)
```

Keep it handy — setup will ask for it.

### Step 3 — Set required env vars

```bash
export GH_TOKEN="ghp_xxx"        # GitHub PAT (scopes: repo, workflow, read:org)
export REPO="P-U-C/b1e55ed"      # or your fork

# Optional
export DATABASE_URL="$HOME/b1e55ed/data/brain.db"
```

### Step 4 — Run setup

```bash
git clone https://github.com/<you>/b1e55ed-operator-template.git
cd b1e55ed-operator-template
bash scripts/setup-openclaw.sh
```

The script will:
- prompt for your name, Telegram handle, timezone, GitHub username, and bot token
- auto-detect your node ID from the installed CLI
- write `USER.md` and `CRITICAL.md` with real values (not placeholders)
- **install b1e55ed as a systemd service** (persistent across reboots, no screen needed)
- set up the OpenClaw queue-drain cron

> `setup-openclaw.sh` is non-destructive: it **does not overwrite** existing workspace files.

### Step 5 — Forge your identity (if first time)

```bash
b1e55ed wizard
```

### Step 6 — Verify

```bash
sudo systemctl status b1e55ed    # engine running?
curl -fsS http://localhost:5050/ && echo "API OK"
b1e55ed resolve-outcomes         # resolver functional?
openclaw cron list               # queue drain active?
```

---

## What Each File Does

| File | Purpose |
|---|---|
| `SOUL.md` | Operator identity (SRE-style, non-trading persona) |
| `AGENTS.md` | Execution protocols, queue/review discipline, hard-won lessons |
| `HEARTBEAT.md` | Engine-health heartbeat checks + thresholds |
| `USER.md` | Operator identity/contact template |
| `CRITICAL.md` | Operational critical state (engine + resolver + active alerts) |
| `TOOLS.md` | Endpoints, CLI commands, env vars, cron snippets |
| `BOOTSTRAP.md` | First-run onboarding flow; delete after completion |
| `TASK_QUEUE.md` | Async queue model (enqueue fast, drain via cron) |
| `scripts/enqueue-pending-reviews.sh` | Poll open PRs with `review/pending` and enqueue missing review tasks |
| `scripts/setup-crons.sh` | Add system cron for outcome resolver (30min) |
| `scripts/setup-openclaw.sh` | One-shot workspace install + queue-drain cron setup |
| `scripts/verify-engine.sh` | Quick engine health check (API, producers, resolver, backlog) |
| `.github/ISSUE_TEMPLATE/operator-issue.md` | Issue template for operator incident reporting |

---

## Environment Variables

| Var | Required | Description |
|---|---|---|
| `GH_TOKEN` | Yes | GitHub PAT for b1e55ing + review council + label polling |
| `REPO` | Recommended | Repo to operate (default `P-U-C/b1e55ed`) |
| `DATABASE_URL` | Optional | Custom DB path (default `~/b1e55ed/data/brain.db`) |
| `ALLORA_API_KEY` | Optional | Allora signal consumer |
| `BINANCE_API_KEY` | Optional | Private market API; public fallback is used if absent |

---

## Cron Jobs to Add

### 1) Outcome resolver (system cron)

```cron
*/30 * * * * /usr/local/bin/b1e55ed resolve-outcomes >> /var/log/b1e55ed-resolver.log 2>&1
```

### 2) Queue drain (OpenClaw cron)

Added by `scripts/setup-openclaw.sh` as an isolated job running every 5 minutes.

Confirm:
```bash
openclaw cron list
```

---

## Verify Instance Health

Run these checks after setup:

```bash
# API + dashboard reachable
curl -fsS http://localhost:5050/ >/dev/null && echo "API OK"
curl -fsS http://localhost:5051/ >/dev/null && echo "Dashboard OK"

# Producer forecast activity in last hour
DB_PATH="${DATABASE_URL:-$HOME/b1e55ed/data/brain.db}"
sqlite3 "$DB_PATH" "
  SELECT source, COUNT(*) AS forecasts_last_hour
  FROM events
  WHERE type='forecast.v1' AND datetime(ts) >= datetime('now','-1 hour')
  GROUP BY source
  ORDER BY forecasts_last_hour DESC;
"

# Last forecast outcome event (resolver freshness proxy)
sqlite3 "$DB_PATH" "SELECT MAX(ts) AS last_outcome_ts FROM events WHERE type='forecast.outcome.v1';"

# Queue drain staleness + pending tasks
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.openclaw/workspace/task-queue.json')
if not os.path.exists(p):
    print('queue file missing')
    raise SystemExit(1)
q = json.load(open(p))
pending = [t for t in q.get('tasks', []) if t.get('status') == 'pending']
print('pending_tasks=', len(pending))
print('last_drained=', q.get('last_drained'))
PY
```

Healthy operator baseline:
- producers are emitting,
- `forecast.outcome.v1` is recent,
- unresolved backlog is controlled,
- queue drain is active.

---

## First Boot Behavior

If `BOOTSTRAP.md` exists in your workspace, OpenClaw should run that onboarding flow once, then delete it.

---

## Notes

- This template intentionally excludes personal portfolio/trading context.
- It encodes operational discipline, not discretionary market opinions.
