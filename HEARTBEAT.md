# HEARTBEAT.md — b1e55ed Operational Heartbeat

Focus: **engine health**, not market commentary.

---

## State File

Path: `memory/heartbeat-state.json`

Expected schema:

```json
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
```

Use Unix seconds for timestamps.

---

## Every Heartbeat (Always)

1. Read `CRITICAL.md`.
2. Read `memory/heartbeat-state.json`.
3. Run **unblessed PR check** (enqueue `b1e55ing` tasks if needed).
4. Run **pending review poll** (enqueue `review` tasks if needed).
5. Run due rotational checks by interval.
6. Update `memory/heartbeat-state.json`.
7. If nothing actionable: `HEARTBEAT_OK`.

---

## Rotational Checks

## 1) Producer health (every 30 min)

Goal: all configured producers emitted `forecast.v1` within the last hour.

```bash
DB_PATH="${DATABASE_URL:-$HOME/b1e55ed/data/brain.db}"
python3 - <<'PY'
import sqlite3, os
from datetime import datetime, timezone

db = os.path.expanduser(os.environ.get('DB_PATH', ''))
conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row

def parse_iso(s):
    if not s:
        return None
    s = str(s)
    if s.endswith('Z'):
        s = s[:-1] + '+00:00'
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt

now = datetime.now(timezone.utc)
producers = [r['name'] for r in conn.execute('SELECT name FROM producer_health ORDER BY name')]
rows = conn.execute("SELECT source, MAX(ts) AS last_ts FROM events WHERE type='forecast.v1' GROUP BY source").fetchall()

last_by_name = {}
for r in rows:
    src = (r['source'] or '').strip()
    name = src.split('@', 1)[0] if src else 'unknown'
    dt = parse_iso(r['last_ts'])
    if dt is None:
        continue
    if name not in last_by_name or dt > last_by_name[name]:
        last_by_name[name] = dt

for name in producers:
    dt = last_by_name.get(name)
    if dt is None:
        print(f'WARNING producer={name} status=no_forecast_events')
        continue
    age_min = (now - dt).total_seconds() / 60.0
    level = 'OK'
    if age_min > 120:
        level = 'ALERT'
    elif age_min > 60:
        level = 'WARNING'
    print(f'{level} producer={name} age_min={age_min:.1f} last={dt.isoformat()}')
PY
```

- Silent >1h: alert operator.
- Silent >2h: 🚨 **ALERT**.

---

## 2) Outcome resolver health (every 1h)

Goal: resolver ran in last 35 minutes (or at least outcomes are fresh).

```bash
DB_PATH="${DATABASE_URL:-$HOME/b1e55ed/data/brain.db}"
python3 - <<'PY'
import os, sqlite3
from datetime import datetime, timezone

db = os.path.expanduser(os.environ.get('DB_PATH', ''))
conn = sqlite3.connect(db)
row = conn.execute("SELECT MAX(ts) FROM events WHERE type='forecast.outcome.v1'").fetchone()
last = row[0]

def parse_iso(s):
    if not s:
        return None
    s = str(s)
    if s.endswith('Z'):
        s = s[:-1] + '+00:00'
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt

dt = parse_iso(last)
if not dt:
    print('WARNING resolver=no_outcome_events_yet')
    raise SystemExit(0)

age_min = (datetime.now(timezone.utc) - dt).total_seconds() / 60.0
if age_min > 60:
    print(f'WARNING resolver_stale age_min={age_min:.1f} last={dt.isoformat()}')
else:
    print(f'OK resolver age_min={age_min:.1f} last={dt.isoformat()}')
PY
```

- Resolver not run >1h: ⚠️ **WARNING**.

---

## 3) Resolution backlog (every 4h)

Goal: unresolved **eligible** forecasts should stay low.

```bash
DB_PATH="${DATABASE_URL:-$HOME/b1e55ed/data/brain.db}"
python3 - <<'PY'
import os, re, json, sqlite3
from datetime import datetime, timezone

db = os.path.expanduser(os.environ.get('DB_PATH', ''))
conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row

def parse_ts(s):
    s = str(s)
    if s.endswith('Z'):
        s = s[:-1] + '+00:00'
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt

def horizon_seconds(label):
    m = re.fullmatch(r"\s*(\d+)\s*([mhd])\s*", str(label).lower())
    if not m:
        return None
    qty = int(m.group(1))
    unit = m.group(2)
    return qty*60 if unit=='m' else qty*3600 if unit=='h' else qty*86400

rows = conn.execute(
    """
    SELECT e.id, e.ts, e.payload
    FROM events e
    LEFT JOIN forecast_resolution_state rs ON rs.forecast_event_id = e.id
    WHERE e.type='forecast.v1' AND rs.forecast_event_id IS NULL
    """
).fetchall()

now = datetime.now(timezone.utc).timestamp() - 300  # 5-min buffer
eligible = 0
for r in rows:
    try:
        payload = json.loads(r['payload'] or '{}')
        h = horizon_seconds(payload.get('horizon'))
        if not h:
            continue
        target = parse_ts(r['ts']).timestamp() + h
        if target <= now:
            eligible += 1
    except Exception:
        continue

if eligible > 100:
    print(f'ALERT backlog_eligible={eligible}')
elif eligible > 50:
    print(f'WARNING backlog_eligible={eligible}')
else:
    print(f'OK backlog_eligible={eligible}')
PY
```

- Eligible unresolved >50: alert operator.
- Eligible unresolved >100: 🚨 **ALERT**.

---

## 4) MetaProducer progress (every 6h)

Goal: track outcomes toward 500 activation threshold.

```bash
DB_PATH="${DATABASE_URL:-$HOME/b1e55ed/data/brain.db}"
sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM events WHERE type='forecast.outcome.v1';"
```

Report:
- current outcome count
- remaining to 500
- % progress

---

## 5) DB health (every 12h)

```bash
DB_PATH="${DATABASE_URL:-$HOME/b1e55ed/data/brain.db}"

# integrity + row count
sqlite3 "$DB_PATH" "PRAGMA integrity_check;"
sqlite3 "$DB_PATH" "SELECT COUNT(*) AS events_count FROM events;"

# disk usage
du -h "$DB_PATH"

# producer errors surfaced by health table
sqlite3 "$DB_PATH" "
  SELECT name, consecutive_failures, last_error
  FROM producer_health
  WHERE COALESCE(consecutive_failures,0) > 0 OR (last_error IS NOT NULL AND last_error != '')
  ORDER BY consecutive_failures DESC, name ASC;
"
```

- Any DB integrity issue or persistent producer DB error: 🚨 **ALERT**.

---

## 6) Unblessed PR check (every heartbeat)

Enqueue missing `b1e55ing` tasks for merged PRs that were never blessed.

```bash
REPO="${REPO:-P-U-C/b1e55ed}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN required}"
QUEUE_PATH="${QUEUE_PATH:-$HOME/.openclaw/workspace/task-queue.json}"
STATE_PATH="${STATE_PATH:-$HOME/.openclaw/workspace/memory/heartbeat-state.json}"

python3 - <<'PY'
import json, os, time, urllib.request
from datetime import datetime, timezone

repo = os.environ['REPO']
token = os.environ['GH_TOKEN']
queue_path = os.path.expanduser(os.environ['QUEUE_PATH'])
state_path = os.path.expanduser(os.environ['STATE_PATH'])

headers = {
    'Authorization': f'token {token}',
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'b1e55ed-operator-heartbeat',
}

try:
    state = json.load(open(state_path))
except Exception:
    state = {'lastChecks': {}, 'last_blessed_pr': 0}

last_blessed = int(state.get('last_blessed_pr', 0) or 0)

req = urllib.request.Request(
    f'https://api.github.com/repos/{repo}/pulls?state=closed&sort=created&direction=desc&per_page=50',
    headers=headers,
)
prs = json.loads(urllib.request.urlopen(req).read())

try:
    q = json.load(open(queue_path))
except Exception:
    q = {'tasks': [], 'last_drained': None}

skip_titles = ('auto-update dependency', 'a b1e55ing', 'chore: a b1e55ing')
enqueued = 0

def queue_has(pr_num):
    return any(
        t.get('type') == 'b1e55ing'
        and int(t.get('payload', {}).get('pr_number', -1)) == int(pr_num)
        and t.get('status') in ('pending', 'processing')
        for t in q.get('tasks', [])
    )

for p in prs:
    if not p.get('merged_at'):
        continue
    pr_num = int(p['number'])
    if pr_num <= last_blessed:
        break
    title = (p.get('title') or '').lower()
    if any(s in title for s in skip_titles):
        continue

    commits_req = urllib.request.Request(p['commits_url'], headers=headers)
    commits = json.loads(urllib.request.urlopen(commits_req).read())
    blessed = any('a b1e55ing' in (c.get('commit', {}).get('message', '').lower()) for c in commits)
    if blessed or queue_has(pr_num):
        continue

    q['tasks'].append({
        'id': f"task_{int(time.time())}_b1e55ing_{pr_num}",
        'type': 'b1e55ing',
        'status': 'pending',
        'priority': 3,
        'payload': {
            'pr_number': pr_num,
            'branch': p['head']['ref'],
            'repo': repo,
            'pr_title': p['title'],
        },
        'created_at': datetime.now(timezone.utc).isoformat(),
        'updated_at': datetime.now(timezone.utc).isoformat(),
        'attempts': 0,
        'max_attempts': 3,
        'error': None,
        'completed_at': None,
    })
    enqueued += 1
    print(f"ENQUEUED b1e55ing for PR #{pr_num}")

if enqueued:
    with open(queue_path, 'w') as f:
        json.dump(q, f, indent=2)
else:
    print('ALL_BLESSED_OR_ALREADY_QUEUED')
PY
```

---

## 7) Pending review poll (every heartbeat)

Run:

```bash
REPO="${REPO:-P-U-C/b1e55ed}" GH_TOKEN="${GH_TOKEN:?GH_TOKEN required}" \
  QUEUE_PATH="${QUEUE_PATH:-$HOME/.openclaw/workspace/task-queue.json}" \
  bash "$HOME/.openclaw/workspace/scripts/enqueue-pending-reviews.sh"
```

---

## Alert Thresholds (Canonical)

- Producer silent >2h → 🚨 **ALERT**
- Resolver not run in >1h → ⚠️ **WARNING**
- Resolution backlog >100 → 🚨 **ALERT**
- DB errors/integrity failures → 🚨 **ALERT**
