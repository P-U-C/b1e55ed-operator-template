# TOOLS.md — Operator Tools & Config

This file stores environment-specific operational notes.

---

## b1e55ed Endpoints

- API: `http://localhost:5050`
- Dashboard: `http://localhost:5051`

---

## Core CLI Commands

- `b1e55ed start`
  - Starts API + dashboard.

- `b1e55ed resolve-outcomes`
  - Runs one resolver pass for elapsed forecasts.

- `b1e55ed status`
  - If available in your installed version, use it for service status.
  - If unavailable, use process checks + endpoint health checks.

---

## Cron Templates

```cron
# Outcome resolver (every 30min)
*/30 * * * * /usr/local/bin/b1e55ed resolve-outcomes >> /var/log/b1e55ed-resolver.log 2>&1

# Queue drain (every 5min) — handled by OpenClaw cron
```

---

## Environment Variables

| Var | Required | Description |
|-----|----------|-------------|
| GH_TOKEN | Yes | GitHub PAT for b1e55ing + review council |
| ALLORA_API_KEY | Optional | Allora Network signal consumer |
| BINANCE_API_KEY | Optional | Price data (fallback to public API if absent) |
| DATABASE_URL | Optional | Custom DB path (default: brain.db) |

---

## Suggested Defaults

```bash
export REPO="P-U-C/b1e55ed"
export DATABASE_URL="$HOME/b1e55ed/data/brain.db"
```
