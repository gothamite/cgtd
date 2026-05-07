# cGTD Deferred Features A+B+C — Design Spec

Date: 2026-05-07  
Scope: Three deferred items from cgtd-issues-report — timezone skill (A), email watermark (B), cron persistence (C). Delivered in a single commit.

---

## A. cgtd-timezone skill

### New file: `skills/cgtd-timezone/SKILL.md`

**Trigger:** `/cgtd-timezone <tz>` dispatched from inbox-router.

**Procedure:**

1. Parse `<tz>` from the command argument. If missing, reply with usage: `/cgtd-timezone Europe/Berlin`.
2. Validate: `python3 -c "import zoneinfo; zoneinfo.ZoneInfo('<tz>')"`. If it raises, reply: «Неверный часовой пояс: `<tz>`. Используй формат IANA, например `Europe/Berlin`.»
3. Read `/data/config.json`. Update `config.user.timezone = <tz>`.
4. Read `config.jobs.cron_ids`. For each non-null ID: `CronDelete(id)`.
5. Read `config.jobs`. For each job, `CronCreate` with its expression(s) and prompt:
   - **For all jobs except `proactive_inbox`:** one `CronCreate` call using `config.jobs.<job_name>.cron`. Save the new ID to `config.jobs.cron_ids[<job_name>]`. The key name equals the job name (e.g., key `morning_ritual` → job `morning_ritual`).
   - **For `proactive_inbox`:** two `CronCreate` calls:
     - expression from `config.jobs.proactive_inbox.cron_weekday` (fall back to `config.jobs.proactive_inbox.cron` if absent) → save ID to `config.jobs.cron_ids.proactive_inbox_weekday`
     - expression from `config.jobs.proactive_inbox.cron_weekend` (fall back to `config.jobs.proactive_inbox.cron` if absent) → save ID to `config.jobs.cron_ids.proactive_inbox_weekend`
   - **Prompt for all CronCreate calls** (including both proactive_inbox entries): `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` — substituting the correct skill name for each job:
     - `morning_ritual` → `morning-ritual`
     - `evening_review` → `evening-review`
     - `process_inbox` → `process-inbox`
     - `proactive_inbox` (both) → `proactive-inbox`
6. Write new IDs back to `config.jobs.cron_ids` in `/data/config.json`.
7. Reply to user:
   > ✓ Часовой пояс обновлён на `<tz>`. Cron-задачи перезапланированы.
   >
   > Текущий TZ контейнера: `$TZ`. Если он отличается — обнови `TZ=<tz>` в docker-compose.yml и перезапусти: `docker compose up -d`.

### Dispatch in `skills/inbox-router/SKILL.md`

Add to the post-init command dispatch table:

```
/cgtd-timezone <tz>  →  invoke cgtd-timezone skill
```

Also update the "Неизвестная команда" help text block to include `/cgtd-timezone <tz>` in the list of available commands.

### `entrypoint.sh` TZ drift warning

Insert the following block in `entrypoint.sh` **before** the final `exec "$@"` line (after the config-seeding section so `/data/config.json` already exists):

```bash
if [ -f /data/config.json ]; then
  cfg_tz=$(jq -r '.user.timezone // empty' /data/config.json 2>/dev/null)
  if [ -n "$cfg_tz" ] && [ "$cfg_tz" != "$TZ" ]; then
    echo "⚠ TZ mismatch: container TZ=$TZ but config.user.timezone=$cfg_tz. Update TZ in docker-compose.yml and run 'docker compose up -d'."
  fi
fi
```

### `config.example.json` — update `proactive_inbox` schema

Replace the single `cron` field under `proactive_inbox` with the weekday/weekend split that gtd-interview writes to the live config:

```json
"proactive_inbox": {
  "enabled": true,
  "cron_weekday": "13 8-20/2 * * 1-5",
  "cron_weekend": "13 8,21 * * 0,6"
}
```

Also add a `cron_ids` key to `config.jobs` (currently absent from the example) to document the schema:

```json
"cron_ids": {
  "morning_ritual": null,
  "evening_review": null,
  "process_inbox": null,
  "proactive_inbox_weekday": null,
  "proactive_inbox_weekend": null
}
```

---

## B. Email watermark

### Runtime file: `/data/email-watermarks.json`

Format:
```json
{"email@gmail.com": ["msg_id_1", "msg_id_2", ...]}
```

One key per Google account. Value is the set of message IDs returned by `search_gmail_messages` (the header scan) in the **most recent successful run** for that account. Created/updated by proactive-inbox after each run.

### Changes to `skills/proactive-inbox/SKILL.md`

**Pre-fetch (per account):**
- Read `/data/email-watermarks.json`. If file is absent or cannot be parsed (malformed JSON), treat all accounts as having no watermark (first-run fallback). Log a note but do not abort.
- Extract the list of seen IDs for this account from the watermark (default: empty list if key absent).

**Fetch (unchanged from current behavior):**
- Always use `newer_than:24h` in `search_gmail_messages`. The watermark does not change the query — it filters results after fetching.

**Post-fetch filter:**
- From the results of `search_gmail_messages`, discard any message whose ID is already in the watermark list for this account.
- Process only the remaining messages.

**Post-processing (per account):**
- Collect **all message IDs returned by `search_gmail_messages`** for this account in this run — including those that were skipped as duplicates. These are the IDs from the header scan step, not just the actionable ones passed to full-content fetch.
- Merge into `/data/email-watermarks.json`: write the new list under this account's key. Do not touch other accounts' keys:
  ```python
  watermarks[account_email] = all_ids_from_search_results_this_run
  # write full watermarks dict back to file
  ```
- The watermark stores only IDs from the **current run**. On the next run (24h later), `newer_than:24h` returns a similar window — any message still within that window that was already stored gets skipped. Messages older than 24h fall out of both the query results and the stored watermark automatically.

**Error handling:**
- If an account returns an auth or network error, skip watermark update for that account (preserve existing watermark).
- If no messages found for an account, write an empty list `[]` for that account's key (clears old IDs from the previous run).
- If the watermarks file is present but cannot be parsed, treat as absent for all accounts and overwrite the file cleanly after this run.

---

## C. Cron persistence

### Changes to `skills/inbox-router/SKILL.md`

Add a **pre-flight block** that runs at the start of every message handler, before any routing. The pre-flight completes before routing begins, so it cannot conflict with the timezone skill (which runs after routing completes).

1. Read `/data/config.json`. If `config.jobs.cron_ids` is absent, empty, or all values are null, skip (init not yet complete).
2. `CronList` → collect active cron IDs as a set.
3. For each key in `config.jobs.cron_ids`: if the stored ID is null or not in the active set, recreate it:
   - Look up the expression from `config.jobs`:
     - Key `proactive_inbox_weekday`: use `config.jobs.proactive_inbox.cron_weekday` (fall back to `config.jobs.proactive_inbox.cron` if absent)
     - Key `proactive_inbox_weekend`: use `config.jobs.proactive_inbox.cron_weekend` (fall back to `config.jobs.proactive_inbox.cron` if absent)
     - All other keys: the key name equals the job name; use `config.jobs.<key>.cron`
   - `CronCreate` with that expression and prompt: `Invoke skill <skill-name>. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` — skill name mapping: `morning_ritual` → `morning-ritual`, `evening_review` → `evening-review`, `process_inbox` → `process-inbox`, both `proactive_inbox_*` → `proactive-inbox`.
   - Update `config.jobs.cron_ids[key]` with the new ID.
4. If any IDs were recreated, write the updated `config.json` to disk.
5. No user notification. Silent operation.

---

## Files Changed

| File | Change |
|------|--------|
| `skills/cgtd-timezone/SKILL.md` | New file |
| `skills/inbox-router/SKILL.md` | Add `/cgtd-timezone` dispatch + help text + cron pre-flight |
| `skills/proactive-inbox/SKILL.md` | Email watermark logic |
| `entrypoint.sh` | TZ drift warning |
| `config.example.json` | Update proactive_inbox schema + add cron_ids template |

All changes delivered in one commit: `feat: timezone skill, email watermark, cron persistence`.

---

## Out of Scope

- Self-hosted Notion MCP migration (separate cycle, item D)
- UI for listing/removing Google accounts
