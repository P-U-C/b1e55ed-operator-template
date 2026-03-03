#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
REPO="${REPO:-P-U-C/b1e55ed}"

echo "[setup] template root: $TEMPLATE_ROOT"
echo "[setup] workspace: $WORKSPACE"
echo "[setup] repo: $REPO"

mkdir -p "$WORKSPACE" "$WORKSPACE/scripts" "$WORKSPACE/memory" "$WORKSPACE/data"

copy_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ -e "$dst" ]]; then
    echo "[setup] skip existing: $dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "[setup] copied: $dst"
  fi
}

# Core workspace files
for f in SOUL.md AGENTS.md HEARTBEAT.md USER.md CRITICAL.md TOOLS.md BOOTSTRAP.md TASK_QUEUE.md; do
  copy_if_missing "$TEMPLATE_ROOT/$f" "$WORKSPACE/$f"
done

# Queue helper script
copy_if_missing "$TEMPLATE_ROOT/scripts/enqueue-pending-reviews.sh" "$WORKSPACE/scripts/enqueue-pending-reviews.sh"
chmod +x "$WORKSPACE/scripts/enqueue-pending-reviews.sh"

# Seed queue file if missing
if [[ ! -f "$WORKSPACE/task-queue.json" ]]; then
  cat > "$WORKSPACE/task-queue.json" <<'JSON'
{
  "tasks": [],
  "last_drained": null
}
JSON
  echo "[setup] created: $WORKSPACE/task-queue.json"
fi

# Seed heartbeat state if missing
if [[ ! -f "$WORKSPACE/memory/heartbeat-state.json" ]]; then
  cat > "$WORKSPACE/memory/heartbeat-state.json" <<'JSON'
{
  "lastChecks": {
    "producer_health": 0,
    "outcome_resolver": 0,
    "resolution_backlog": 0,
    "metaproducer_progress": 0,
    "db_health": 0,
    "pending_reviews": 0,
    "unblessed_prs": 0
  },
  "last_blessed_pr": 0
}
JSON
  echo "[setup] created: $WORKSPACE/memory/heartbeat-state.json"
fi

# Configure OpenClaw queue-drain cron job
if command -v openclaw >/dev/null 2>&1; then
  existing_id="$({ openclaw cron list --json 2>/dev/null || true; } | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {'jobs': []}
for job in data.get('jobs', []):
    if job.get('name') == 'b1e55ed Queue Drain (5min)':
        print(job.get('id', ''))
        break
" 2>/dev/null || true)"

  if [[ -n "$existing_id" ]]; then
    echo "[setup] queue drain cron already exists: $existing_id"
  else
    DRAIN_MSG="Read $WORKSPACE/task-queue.json and follow $WORKSPACE/TASK_QUEUE.md.

STEP 0: Run: REPO=$REPO GH_TOKEN=\${GH_TOKEN} QUEUE_PATH=$WORKSPACE/task-queue.json bash $WORKSPACE/scripts/enqueue-pending-reviews.sh

STEP 1: For each pending task (priority desc, created_at asc): set processing, increment attempts, execute by type.
- b1e55ing: spawn a Codex subagent (do NOT execute inline)
- review: run review council flow
- address_review: address concern/block findings, test, commit, push, comment
- notify: send notification
- custom: execute instruction

STEP 2: On success mark done. On failure set failed; retry next cycle if attempts < max_attempts. Write queue updates back. Update last_drained."

    openclaw cron add \
      --name "b1e55ed Queue Drain (5min)" \
      --description "Drains b1e55ed operator task queue" \
      --every 5m \
      --session isolated \
      --no-deliver \
      --message "$DRAIN_MSG" \
      2>/dev/null && echo "[setup] created queue drain cron" \
      || echo "[setup] WARNING: failed to add queue drain cron. Run manually:
  openclaw cron add --name 'b1e55ed Queue Drain (5min)' --every 5m --session isolated --no-deliver --message '<drain instructions>'"
  fi
else
  echo "[setup] WARNING: openclaw CLI not found; skipping cron setup"
fi

cat <<EOF

  Setup complete.

Next steps:
1) Ensure environment variables are exported (especially GH_TOKEN).
2) Start services: b1e55ed start
3) Test resolver: b1e55ed resolve-outcomes
4) Verify cron: openclaw cron list
5) Confirm queue file: $WORKSPACE/task-queue.json

EOF
