#!/usr/bin/env bash
# Setup b1e55ed operational cron jobs
# Usage: GH_TOKEN=xxx REPO=owner/repo ./setup-crons.sh

set -e

GH_TOKEN="${GH_TOKEN:?Set GH_TOKEN env var}"
REPO="${REPO:-P-U-C/b1e55ed}"

echo "Setting up b1e55ed operational crons..."

# 1. Outcome resolver (every 30min)
(crontab -l 2>/dev/null; echo "*/30 * * * * /usr/local/bin/b1e55ed resolve-outcomes >> /var/log/b1e55ed-resolver.log 2>&1") | crontab -
echo "✅ Outcome resolver: every 30min"

# 2. OpenClaw queue drain (handled by openclaw cron — just print reminder)
echo ""
echo "📌 Also run: openclaw cron add --name 'queue-drain' --interval 5m --message 'Process task queue...'"
echo "   (See TASK_QUEUE.md for full drain cron setup)"
echo ""
echo "Done. Verify with: crontab -l"
