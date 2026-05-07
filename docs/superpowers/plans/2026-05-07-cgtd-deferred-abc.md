# cGTD Deferred Features A+B+C Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add timezone management skill, email dedup watermark, and cron persistence across container restarts.

**Architecture:** All changes are to Markdown skill files, a shell script, and a JSON config template. No executable code is compiled or tested — verification is reading the resulting files and confirming the expected sections are present and correct. All five changes ship in one commit.

**Tech Stack:** Bash (entrypoint.sh), JSON (config.example.json), Markdown (SKILL.md files).

**Spec:** `docs/superpowers/specs/2026-05-07-cgtd-deferred-abc-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `config.example.json` | Modify lines 34-39 | Add `cron_weekday`/`cron_weekend` split for `proactive_inbox`; add `cron_ids` template key |
| `entrypoint.sh` | Insert before line 47 | TZ drift warning using jq |
| `skills/cgtd-timezone/SKILL.md` | Create | New skill: validate IANA TZ, update config, recreate all crons |
| `skills/inbox-router/SKILL.md` | Modify | Add cron pre-flight block; add `/cgtd-timezone` dispatch + help text |
| `skills/proactive-inbox/SKILL.md` | Modify | Add email watermark pre-fetch, post-fetch filter, post-processing write |

---

## Task 1: Update `config.example.json`

**Files:**
- Modify: `config.example.json:34-39`

- [ ] **Step 1: Replace the `jobs` block**

Open `config.example.json`. Replace the current `jobs` block (lines 34–39):

```json
  "jobs": {
    "proactive_inbox": { "enabled": true,  "cron": "13 8-20/2 * * *" },
    "morning_ritual":  { "enabled": true,  "cron": "30 8 * * *" },
    "evening_review":  { "enabled": true,  "cron": "28 21 * * *" },
    "process_inbox":   { "enabled": true,  "cron": "57 20 * * *" }
  }
```

with:

```json
  "jobs": {
    "proactive_inbox": {
      "enabled": true,
      "cron_weekday": "13 8-20/2 * * 1-5",
      "cron_weekend": "13 8,21 * * 0,6"
    },
    "morning_ritual":  { "enabled": true, "cron": "30 8 * * *" },
    "evening_review":  { "enabled": true, "cron": "28 21 * * *" },
    "process_inbox":   { "enabled": true, "cron": "57 20 * * *" },
    "cron_ids": {
      "morning_ritual": null,
      "evening_review": null,
      "process_inbox": null,
      "proactive_inbox_weekday": null,
      "proactive_inbox_weekend": null
    }
  }
```

Note: `cron_ids` is a sibling key inside `jobs`, not a separate job — it stores the live cron IDs written by gtd-interview.

- [ ] **Step 2: Verify valid JSON**

```bash
python3 -m json.tool config.example.json > /dev/null && echo OK
```

Expected output: `OK`

---

## Task 2: Add TZ drift warning to `entrypoint.sh`

**Files:**
- Modify: `entrypoint.sh:46` (insert before the final `exec "$@"`)

- [ ] **Step 1: Insert the warning block**

Open `entrypoint.sh`. Insert the following block immediately before the final `exec "$@"` line (currently line 47):

```bash
# Warn if container TZ doesn't match config.user.timezone
if [ -f "$DATA/config.json" ]; then
  cfg_tz=$(jq -r '.user.timezone // empty' "$DATA/config.json" 2>/dev/null)
  if [ -n "$cfg_tz" ] && [ "$cfg_tz" != "$TZ" ]; then
    echo "⚠ TZ mismatch: container TZ=$TZ but config.user.timezone=$cfg_tz. Update TZ in docker-compose.yml and run 'docker compose up -d'."
  fi
fi
```

Note: uses `$DATA` (not hardcoded `/data`) to respect the `CGTD_DATA_DIR` env var — an intentional improvement over the spec's snippet.

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n entrypoint.sh && echo OK
```

Expected output: `OK`

---

## Task 3: Create `skills/cgtd-timezone/SKILL.md`

**Files:**
- Create: `skills/cgtd-timezone/SKILL.md`

- [ ] **Step 1: Create the file**

```bash
mkdir -p skills/cgtd-timezone
```

Create `skills/cgtd-timezone/SKILL.md` with this exact content:

```markdown
---
name: cgtd-timezone
description: Update the assistant's timezone. Validates the IANA timezone string, updates config.user.timezone, recreates all cron jobs with updated IDs.
---

# Timezone update

Invoked by inbox-router when the user sends `/cgtd-timezone <tz>`.

## Procedure

1. **Parse argument.** Extract `<tz>` from the command. If missing or empty, reply:
   > Укажи часовой пояс: `/cgtd-timezone Europe/Berlin`
   Then exit.

2. **Validate IANA timezone.**
   ```bash
   python3 -c "import zoneinfo; zoneinfo.ZoneInfo('<tz>')"
   ```
   If the command exits non-zero, reply:
   > Неверный часовой пояс: `<tz>`. Используй формат IANA, например `Europe/Berlin`.
   Then exit.

3. **Update config.** Read `/data/config.json`. Set `config.user.timezone = <tz>`. Write back.

4. **Delete existing crons.** Read `config.jobs.cron_ids`. For each value that is not null: call `CronDelete(id)`.

5. **Recreate crons.** Read `config.jobs`. For each job:

   - **`morning_ritual`**: `CronCreate` with expression `config.jobs.morning_ritual.cron`, prompt `Invoke skill morning-ritual. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.morning_ritual`.
   - **`evening_review`**: `CronCreate` with expression `config.jobs.evening_review.cron`, prompt `Invoke skill evening-review. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.evening_review`.
   - **`process_inbox`**: `CronCreate` with expression `config.jobs.process_inbox.cron`, prompt `Invoke skill process-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.process_inbox`.
   - **`proactive_inbox` (weekday)**: `CronCreate` with expression `config.jobs.proactive_inbox.cron_weekday` (fall back to `config.jobs.proactive_inbox.cron` if absent), prompt `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.proactive_inbox_weekday`.
   - **`proactive_inbox` (weekend)**: `CronCreate` with expression `config.jobs.proactive_inbox.cron_weekend` (fall back to `config.jobs.proactive_inbox.cron` if absent), prompt `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.proactive_inbox_weekend`.

6. **Write new IDs.** Save the updated `config.jobs.cron_ids` back to `/data/config.json`.

7. **Reply to user:**
   > ✓ Часовой пояс обновлён на `<tz>`. Cron-задачи перезапланированы.
   >
   > Текущий TZ контейнера: `$TZ`. Если он отличается — обнови `TZ=<tz>` в docker-compose.yml и перезапусти: `docker compose up -d`.

## Failure modes

- If `CronDelete` fails for an ID (already gone) — ignore and continue.
- If `CronCreate` fails for a job — note it in the reply after the success message: «⚠ Не удалось создать cron для `<job_name>` — проверь вручную.»
```

- [ ] **Step 2: Verify file created**

```bash
cat skills/cgtd-timezone/SKILL.md | head -5
```

Expected: frontmatter block starting with `---`

---

## Task 4: Update `skills/inbox-router/SKILL.md`

Two changes: (a) cron pre-flight block at the top, (b) `/cgtd-timezone` in dispatch table and help text.

**Files:**
- Modify: `skills/inbox-router/SKILL.md`

- [ ] **Step 1: Add cron pre-flight block**

Insert the following new section at the very beginning of the skill body, immediately after the frontmatter (after line 8, before `## Pre-init guard`):

```markdown
## Cron pre-flight (every message)

Before any routing, silently check and restore missing cron jobs:

1. Read `/data/config.json`. If `config.jobs.cron_ids` is absent, empty, or all values are null → skip (init not complete yet).
2. Call `CronList` → collect the set of active cron IDs.
3. For each key in `config.jobs.cron_ids`:
   - If the stored ID is null or not in the active CronList set → recreate it:
     - **`proactive_inbox_weekday`**: expression = `config.jobs.proactive_inbox.cron_weekday` (fall back to `config.jobs.proactive_inbox.cron`); prompt = `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`proactive_inbox_weekend`**: expression = `config.jobs.proactive_inbox.cron_weekend` (fall back to `config.jobs.proactive_inbox.cron`); prompt = `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`morning_ritual`**: expression = `config.jobs.morning_ritual.cron`; prompt = `Invoke skill morning-ritual. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`evening_review`**: expression = `config.jobs.evening_review.cron`; prompt = `Invoke skill evening-review. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`process_inbox`**: expression = `config.jobs.process_inbox.cron`; prompt = `Invoke skill process-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - Save the new ID back to `config.jobs.cron_ids[key]`.
4. If any ID was recreated, write the updated `config.json` to disk.
5. No user notification. Continue to routing.

```

- [ ] **Step 2: Add `/cgtd-timezone` to dispatch table**

In the `## Recognized commands (post-init)` section, find the exact line:
```
- `/status` → reply with last-ok timestamps from `cron-log.sh last-ok` for each configured job
```
Insert the following line immediately after it:
```
- `/cgtd-timezone <tz>` → invoke `cgtd-timezone` skill
```

- [ ] **Step 3: Add `/cgtd-timezone` to help text**

In the `## Recognized commands (post-init)` section, find the help text block. Locate the line:
```
> `/status` — статус cron-задач
```
Insert the following line immediately after it (before the `>` blank separator line):
```
> `/cgtd-timezone <tz>` — изменить часовой пояс
```

- [ ] **Step 4: Verify sections present**

```bash
grep -n "Cron pre-flight\|cgtd-timezone" skills/inbox-router/SKILL.md
```

Expected: at least 3 matches (section header, dispatch entry, help text entry).

---

## Task 5: Update `skills/proactive-inbox/SKILL.md`

Add email watermark: read before fetch, filter after fetch, write after processing.

**Files:**
- Modify: `skills/proactive-inbox/SKILL.md`

- [ ] **Step 1: Add watermark pre-fetch section**

Insert the following new section immediately before the `## Sources` section (before the line `## Sources (per account in...`):

~~~markdown
## Email watermark

Before fetching Gmail, load the seen-ID sets from `/data/email-watermarks.json`:

    {"email@gmail.com": ["msg_id_1", "msg_id_2"]}

- If the file is absent or cannot be parsed (malformed JSON): treat all accounts as having no watermark (first-run fallback). Continue without aborting.
- For each account, extract its list of seen IDs (default empty list if key absent). Store in memory as `watermark[email]`.

~~~

- [ ] **Step 2: Add post-fetch filter in Sources section**

In the `## Sources` section, after the existing "Header scan" step (step 1 of the two-step Gmail fetch) for each account, add:

```markdown
  - After the header scan: filter out any message whose ID is already in `watermark[email]`. Only pass the remaining (unseen) messages to step 2 (full content fetch) and to classification.
```

The existing text for the header scan step currently reads:
```
  1. **Header scan**: `mcp__google-workspace__search_gmail_messages ...`
  2. **Full content fetch**: ...
```

The filter line goes between steps 1 and 2.

- [ ] **Step 3: Add watermark write section**

Insert the following new section immediately before the `## Failure modes` section:

```markdown
## Watermark write (per account, after processing)

After processing each account's messages:

1. Collect **all message IDs returned by `search_gmail_messages`** for this account in this run — including those skipped as duplicates. These are the IDs from the header scan, not just actionable ones.
2. Write to `/data/email-watermarks.json`:
   - Read the current file (or start with `{}`).
   - Set `watermarks[account_email]` to the list of all IDs from this run.
   - Write the full dict back. Do not touch other accounts' keys.
3. If no messages were found for an account, write `[]` for that account's key (clears stale IDs from the previous run).
4. If the account returned an auth or network error, skip watermark update for that account (preserve its existing key).
5. If the watermarks file was unreadable on load (parse error): overwrite it cleanly with the data from this run.

```

- [ ] **Step 4: Verify sections present**

```bash
grep -n "Email watermark\|Watermark write\|watermark\[email\]" skills/proactive-inbox/SKILL.md
```

Expected: at least 3 matches.

---

## Task 6: Commit all changes

- [ ] **Step 1: Stage all changed files**

```bash
git add config.example.json entrypoint.sh skills/cgtd-timezone/SKILL.md skills/inbox-router/SKILL.md skills/proactive-inbox/SKILL.md
```

- [ ] **Step 2: Verify staged files**

```bash
git diff --cached --name-only
```

Expected: exactly 5 files listed.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: timezone skill, email watermark, cron persistence"
```

Expected: commit created on branch `main`.
