#!/usr/bin/env bash
# Verify b1e55ed engine health
# Usage: ./verify-engine.sh [--db /path/to/brain.db]

DB="${1:-$HOME/.b1e55ed/brain.db}"
if [ ! -f "$DB" ]; then
    DB=$(find ~/.b1e55ed /var/lib/b1e55ed . -name "brain.db" 2>/dev/null | head -1)
fi

if [ -z "$DB" ]; then
    echo "❌ brain.db not found. Is b1e55ed running?"
    exit 1
fi

echo "🔍 b1e55ed engine health check"
echo "   DB: $DB"
echo ""

# API health
if curl -sf http://localhost:5050/health > /dev/null 2>&1; then
    echo "✅ API: running (localhost:5050)"
else
    echo "❌ API: not responding (run: b1e55ed start)"
fi

# Producer activity
echo ""
echo "📡 Producer activity (last 2h):"
sqlite3 "$DB" "SELECT producer_id, datetime(MAX(ts), 'unixepoch') as last_seen, COUNT(*) as forecasts_2h FROM events WHERE type='FORECAST_V1' AND ts > strftime('%s','now','-2 hours') GROUP BY producer_id ORDER BY last_seen DESC" 2>/dev/null || echo "   (no data yet)"

# Outcome resolver
echo ""
echo "🔄 Outcome resolver:"
LAST=$(sqlite3 "$DB" "SELECT datetime(MAX(resolved_at), 'unixepoch') FROM forecast_resolution_state" 2>/dev/null)
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM events WHERE type='FORECAST_OUTCOME_V1'" 2>/dev/null || echo "0")
echo "   Last run: ${LAST:-never}"
echo "   Total outcomes: $COUNT / 500 (MetaProducer activation)"

# Backlog
BACKLOG=$(sqlite3 "$DB" "SELECT COUNT(*) FROM events e WHERE type='FORECAST_V1' AND NOT EXISTS (SELECT 1 FROM forecast_resolution_state r WHERE r.forecast_event_id = e.id)" 2>/dev/null || echo "unknown")
echo "   Unresolved backlog: $BACKLOG"

echo ""
echo "✓ Health check complete"
