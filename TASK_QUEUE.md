# TASK_QUEUE.md — Async Queue Protocol

Queue file: `~/.openclaw/workspace/task-queue.json`

---

## Why this exists

Real-time triggers get dropped when the main session is busy.
The queue makes automation reliable:

1. **Enqueue fast** on trigger
2. **Process asynchronously** via cron

Never process heavy triggered flows inline if they can be queued.

---

## Task Types

- `b1e55ing`
  - Blessing/easter-egg workflow for merged PRs.

- `review`
  - Review council run for PRs with `review/pending`.

- `address_review`
  - Follow-up fixes for concern/block findings.

- `notify`
  - Send status/alert notifications.

- `custom`
  - Explicit custom instruction payload.

---

## Queue Schema

```json
{
  "tasks": [
    {
      "id": "task_1700000000_review_123",
      "type": "review",
      "status": "pending",
      "priority": 2,
      "payload": {},
      "created_at": "2026-03-03T00:00:00+00:00",
      "updated_at": "2026-03-03T00:00:00+00:00",
      "attempts": 0,
      "max_attempts": 3,
      "error": null,
      "completed_at": null
    }
  ],
  "last_drained": null
}
```

---

## Manual Enqueue (Example)

```bash
python3 - <<'PY'
import json, time, os
from datetime import datetime, timezone

path = os.path.expanduser('~/.openclaw/workspace/task-queue.json')
try:
    q = json.load(open(path))
except Exception:
    q = {'tasks': [], 'last_drained': None}

task = {
    'id': f'task_{int(time.time())}_custom_manual',
    'type': 'custom',
    'status': 'pending',
    'priority': 1,
    'payload': {'instruction': 'describe queue health'},
    'created_at': datetime.now(timezone.utc).isoformat(),
    'updated_at': datetime.now(timezone.utc).isoformat(),
    'attempts': 0,
    'max_attempts': 3,
    'error': None,
    'completed_at': None,
}
q['tasks'].append(task)
json.dump(q, open(path, 'w'), indent=2)
print('enqueued', task['id'])
PY
```

---

## Drain Cron Behavior (every 5 min)

Step 0:
- Run `scripts/enqueue-pending-reviews.sh` to catch missed review triggers.

Step 1:
- Load queue.
- Sort `pending` tasks by `priority DESC`, then `created_at ASC`.

Step 2:
- For each task:
  - set `processing`
  - increment `attempts`
  - execute by task type
  - on success → `done` + `completed_at`
  - on failure:
    - if attempts < max_attempts → reset to `pending`
    - else → `failed` and alert operator

Step 3:
- Update `last_drained`.

---

## Queue Status Checks

```bash
# Quick summary
python3 - <<'PY'
import json, os, collections
path = os.path.expanduser('~/.openclaw/workspace/task-queue.json')
q = json.load(open(path))
c = collections.Counter(t.get('status', 'unknown') for t in q.get('tasks', []))
print('status_counts=', dict(c))
print('last_drained=', q.get('last_drained'))
PY

# View pending tasks only
python3 - <<'PY'
import json, os
path = os.path.expanduser('~/.openclaw/workspace/task-queue.json')
q = json.load(open(path))
for t in q.get('tasks', []):
    if t.get('status') == 'pending':
        print(t['id'], t['type'], t.get('payload', {}).get('pr_number', ''))
PY
```

---

## Helper Script

- `scripts/enqueue-pending-reviews.sh`
  - Polls GitHub for open PRs with `review/pending` and enqueues missing review tasks.
  - Use as drain-cron Step 0.
