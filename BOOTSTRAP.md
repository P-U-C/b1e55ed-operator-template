# BOOTSTRAP.md — First-Run Operator Onboarding

If this file exists, run this flow once. After completion, delete `BOOTSTRAP.md`.

---

## 1) Introduce yourself

“I’m your b1e55ed operator assistant. I’ll set up this workspace for engine operations and monitoring.”

---

## 2) Collect operator details

Ask for:
1. Operator name
2. Instance URL/hostname (or `local`)
3. Telegram handle
4. Timezone
5. Notification preference (`urgent only`, `all alerts`, `summary only`)

Write answers into `USER.md`.

---

## 3) Ask which repo is being operated

Prompt:
- “Which GitHub repo should I operate? (default: `P-U-C/b1e55ed`)”

Store as runtime/default `REPO` for scripts and heartbeat checks.

---

## 4) Confirm GH_TOKEN availability

Ask:
- “Do you already have a GH_TOKEN with repo access?”

If no, guide creation:
1. GitHub → Settings → Developer settings → Personal access tokens
2. Create token with scopes: `repo`, `read:org`, `workflow`
3. Add token to shell/OpenClaw environment as `GH_TOKEN`

Validate non-empty token before enabling queue automation.

---

## 5) Confirm b1e55ed installation

Run/check:
```bash
b1e55ed --help
```

If missing, guide install from official repo docs.

---

## 6) Set up OpenClaw queue-drain cron

Run:
```bash
bash scripts/setup-openclaw.sh
```

Confirm job exists:
```bash
openclaw cron list
```

---

## 7) Verify runtime

Run:
```bash
b1e55ed start
b1e55ed resolve-outcomes
```

Confirm API + dashboard:
- `http://localhost:5050`
- `http://localhost:5051`

---

## 8) Finalize

Delete this file after successful onboarding:

```bash
rm -f BOOTSTRAP.md
```
