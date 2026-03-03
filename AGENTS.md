# AGENTS.md — b1e55ed Operator Playbook

This workspace runs an operations assistant for b1e55ed.
It is optimized for reliability, queue discipline, and safe automation.

---

## 1) Session Startup Protocol (Mandatory)

At session start, read in this order:

1. `SOUL.md`
2. `USER.md`
3. `CRITICAL.md`
4. `memory/YYYY-MM-DD.md` (today; yesterday if context is thin)

In main/direct operator sessions, also load `MEMORY.md` for curated long-term context.

---

## 2) Parallel Execution Protocol

- Independent tasks must run in parallel.
- Use up to **4 concurrent subagents**.
- Never run independent tasks sequentially.
- Keep each spawned task narrow and finishable.

---

## 3) Anti-Compaction Protocol

Context compaction happens. Files are source-of-truth.

Rules:
1. Before claiming completion, check `git log --oneline -10`.
2. During long sessions, write `STATE_SNAPSHOT` notes to `memory/YYYY-MM-DD.md`:
   - completed work
   - in-progress work
   - promises made
   - blockers
3. After compaction, re-read state files and recent commits before answering status questions.
4. Never contradict repo state with memory guesses.

---

## 4) Memory System

### Files
- Daily log: `memory/YYYY-MM-DD.md`
- Curated memory: `MEMORY.md`

### Tags (required for structured logging)
- `[FACT]` objective observation
- `[DECISION]` decision + rationale
- `[LEARN]` reusable lesson
- `[ERROR]` mistake + fix
- `[TODO]` pending action

Write important operational facts to files immediately. Chat is not durable memory.

---

## 5) Codex Spawn Best Practices

When spawning coding subagents:

1. Keep tasks small and focused (target **≤3 files**).
2. Include explicit commit instructions:
   - verify file writes (`cat <file>`)
   - `git add -A && git commit -m "..."`
3. Include PR body requirement:
   - “Read `.github/PULL_REQUEST_TEMPLATE.md` and use it exactly.”
4. Set tool output limits to avoid silent truncation.
5. After completion, verify with:
   - `git status`
   - `git log --oneline -5`

---

## 6) PR Discipline (Mandatory)

- Always use the repo PR template.
- Always add labels after PR creation.
- Merge strategy: **squash-and-merge only**.
- Never merge without review.
- Never merge to `main` without explicit human sign-off.

---

## 7) `[b1e55ing]` Protocol

Trigger phrase: inbound message contains `[b1e55ing]`.

Actions:
1. Extract `PR_NUMBER`, `BRANCH`, `PR_TITLE`.
2. Enqueue task in `task-queue.json` (type `b1e55ing`).
3. Do **not** process inline.

Queue payload shape:

```json
{
  "type": "b1e55ing",
  "status": "pending",
  "priority": 3,
  "payload": {
    "pr_number": 123,
    "branch": "feat/example",
    "repo": "P-U-C/b1e55ed",
    "pr_title": "feat: ..."
  }
}
```

**Execution rule:** queue drain cron must spawn a **Codex subagent** for `b1e55ing` tasks; never run them inline in the drain turn.

**Every heartbeat:** run unblessed PR check and enqueue any misses.

---

## 8) `[review]` Protocol (Review Council)

Trigger phrase: inbound message contains `[review]`.

Actions:
1. Extract `PR_NUMBER`, `REPO`, `BRANCH`, `SHA`, `PR_TITLE`, `TASK_KEY`.
2. Enqueue task type `review`.
3. Dedupe by `TASK_KEY` for pending/processing tasks.

Heartbeat fallback: poll open PRs with `review/pending` label each heartbeat and enqueue missing review tasks.

---

## 9) Task Queue Protocol

Queue file: `~/.openclaw/workspace/task-queue.json`

Task types:
- `b1e55ing`
- `review`
- `address_review`
- `notify`
- `custom`

Drain cron contract:
- runs every 5 minutes,
- step 0 runs `scripts/enqueue-pending-reviews.sh`,
- processes pending tasks by `priority desc, created_at asc`,
- writes status transitions (`pending -> processing -> done|failed`),
- updates `last_drained`.

Drain cron ID placeholder (fill after setup):
- `DRAIN_CRON_ID: <set via openclaw cron list --json>`

---

## 10) Key Lessons Learned (Do Not Relearn These)

1. Never add `tests/engine/__init__.py` or `tests/engine/core/__init__.py`.
   - These can shadow/import-conflict the real `engine` package.

2. `engine/brain/orchestrator.py` must never be modified.

3. Push with PAT like this:
   - `git push "https://x-access-token:${GH_TOKEN}@github.com/<owner>/<repo>.git" <branch>`
   - Do not use `oauth2:` remote format.

4. Do not use `gh` CLI for PR creation in automation paths.
   - Use GitHub REST API directly.

5. Squash merge can inherit `[skip ci]` from commit body history.
   - Use `workflow_dispatch` fallback when CI does not trigger.

6. `b1e55ing` must be Codex-subagent execution from queue drain.
   - Not inline in the drain cron turn.

7. Shell env scoping with pipes matters:
   - `BRANCH=x curl ... | bash` sets `BRANCH` for `curl`, not `bash`.
   - Use `curl ... | BRANCH=x bash` when `bash` needs the variable.

8. macOS Forge binaries may require quarantine removal:
   - `xattr -dr com.apple.quarantine <binary-or-dir>`

---

## Safety + Source-of-Truth

- `CRITICAL.md` is authoritative for operational critical state.
- Prefer recoverable operations and explicit confirmations for destructive actions.
- If state in chat conflicts with files, files win.
