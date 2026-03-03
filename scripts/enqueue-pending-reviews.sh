#!/usr/bin/env bash
# Enqueue any open PRs with review/pending label that aren't already in the task queue.
# Called by drain cron as Step 0 every cycle.
# Usage: REPO=owner/repo GH_TOKEN=xxx ./enqueue-pending-reviews.sh

set -euo pipefail

REPO="${REPO:-P-U-C/b1e55ed}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN required}"
QUEUE_PATH="${QUEUE_PATH:-$HOME/.openclaw/workspace/task-queue.json}"

export REPO GH_TOKEN QUEUE_PATH

python3 <<'PY'
import json
import os
import time
import urllib.request
from datetime import datetime, timezone

repo = os.environ['REPO']
token = os.environ['GH_TOKEN']
queue_path = os.path.expanduser(os.environ['QUEUE_PATH'])

headers = {
    'Authorization': f'token {token}',
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'b1e55ed-operator-template',
}

def gh_get(url: str):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())

# Fetch open PRs (up to 100)
prs = gh_get(f'https://api.github.com/repos/{repo}/pulls?state=open&per_page=100')

# Load queue (or initialize)
try:
    with open(queue_path) as f:
        q = json.load(f)
    if not isinstance(q, dict) or 'tasks' not in q:
        raise ValueError('invalid queue shape')
except Exception:
    q = {'tasks': [], 'last_drained': None}

review_result_labels = {'review/pass', 'review/concern', 'review/block', 'review/human-required'}
enqueued = []

for p in prs:
    labels = {l.get('name', '') for l in p.get('labels', [])}

    if 'review/pending' not in labels:
        continue
    if labels & review_result_labels:
        continue

    pr_num = int(p['number'])
    sha = str(p['head']['sha'])[:8]
    task_key = f'review:{repo}:{pr_num}:{sha}'

    already = any(
        t.get('type') == 'review'
        and t.get('payload', {}).get('task_key') == task_key
        and t.get('status') in ('pending', 'processing')
        for t in q.get('tasks', [])
    )
    if already:
        continue

    now = datetime.now(timezone.utc).isoformat()
    q['tasks'].append({
        'id': f'task_{int(time.time())}_review_{pr_num}',
        'type': 'review',
        'status': 'pending',
        'priority': 2,
        'payload': {
            'pr_number': pr_num,
            'repo': repo,
            'branch': p['head']['ref'],
            'sha': p['head']['sha'],
            'pr_title': p['title'],
            'task_key': task_key,
        },
        'created_at': now,
        'updated_at': now,
        'attempts': 0,
        'max_attempts': 3,
        'error': None,
        'completed_at': None,
    })
    enqueued.append(f"#{pr_num} {p['title'][:70]}")

if enqueued:
    os.makedirs(os.path.dirname(queue_path), exist_ok=True)
    with open(queue_path, 'w') as f:
        json.dump(q, f, indent=2)
    print(f'[enqueue-pending-reviews] enqueued={len(enqueued)}')
    for line in enqueued:
        print(f'  - {line}')
else:
    print('[enqueue-pending-reviews] no new review tasks')
PY
