---
name: process-inbox
description: Classify entries in Notion Inbox and route to Next Actions / Tasks / Notes, then archive originals. Cron job (default 20:57); also runs on demand via /inbox or «разбери инбокс».
---

# Process Notion Inbox

Invoked by cron `cgtd-${install_id}-process-inbox` (default `57 20 * * *`) or manually via `/inbox`.

## Pre-flight

Read `/data/config.json`. Required: `notion.capture.db_id`, `telegram.chat_id`. If `notion.enabled=false` → log `ok` (no-op), exit.

## Runtime role resolution

Read the semantic roles from config before any Notion call:

```
capture_id   = notion.capture.db_id
capture_name = notion.capture.db_name

actions_id   = notion.actions.db_id  (empty if same_as_capture or not set)
               → if same_as_capture=true or empty: use capture_id
actions_fields = notion.actions.fields  (status, status_open, status_done,
                 status_cancelled, status_deferred, date, priority, project_relation)
               → fallback if field empty: Status / "Not started" / "Done" /
                 "Cancelled" / "Someday·Maybe" / Date / Priority / null

projects_id     = notion.projects.db_id  (empty if same_as or not set)
                  → if same_as_actions=true: use actions_id
                  → if same_as_capture is implied: use capture_id
projects_filter = {property: projects.filter_property, value: projects.filter_value}  or null
projects_fields = notion.projects.fields

reference_id = notion.reference.db_id  (null if not set)
```

If `config.gtd.unmappable_warning: true` → create all entries with Name + body only; skip all Status/Date/Priority fields; label output «⚠️ схема не распознана — создано без полей».

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start process-inbox)
/app/bin/cron-log.sh lock process-inbox || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## MCP guard

Before any API call, attempt `mcp__notion__API-post-search query=""`.

- If the tool returns a **tool-not-found / not-available error** (MCP server not loaded in this session):
  1. Try `mcp__plugin_telegram_telegram__reply chat_id=<config.telegram.chat_id>` with:
     > ⚠️ Обработка Inbox не запустилась: MCP-серверы не загрузились. Запусти channel-сессию:
     > ```
     > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
     > ```
  2. `cron-log.sh fail "$RID" "mcp_unavailable: start channel session"`. Exit.
- Auth error → continue; handled in Failure modes.

## Procedure

1. Query the Inbox DB via `mcp__notion__API-query-data-source` with `data_source_id = capture_id` (fallback: `mcp__notion__API-post-search` on `capture_id`). Note: `data_source_id` = the database UUID from config; if the call fails with a 404, call `mcp__notion__API-retrieve-a-database` first to get the actual data_source_id from the response.
2. For each entry, extract implicit date/deadline per `/data/memory/feedback_implicit_dates.md` + `feedback_contextual_deadlines.md`.

   **Status–Date invariant** (applies when actions DB has a date field). An open-status entry MUST have a Date if the actions DB supports it. Inference chain:
   1. Implicit phrases in text (per `feedback_implicit_dates.md`).
   2. Contextual heuristics (per `feedback_contextual_deadlines.md`).
   3. Cross-Notion lookup: search actions DB by event title → subtract domain lead time.
   4. If date still unknown → leave in Inbox with note «дата не найдена — уточнить». Route to deferred/someday status only when actions DB has such a value; otherwise leave in Inbox.
   The deferred status (`actions_fields.status_deferred`) is the ONLY status that may have no Date. If actions DB has no status field → omit all status assignments.

3. **Dedup check.** Before creating in destination, `mcp__notion__API-post-search` the target DB for the entry's title — fuzzy match. If candidate duplicate exists AND not done/cancelled:
   - Exact/near-exact → skip create; trash the Inbox entry; mention in ⚠️ «duplicate, existing: [link]».
   - Partial match → surface in ⚠️, ask user «дубликат X? [a] объединить / [b] оставить обе / [c] отменить».
   - Duplicate is done/cancelled → proceed.

4. **Classify and route:**

   **Context inference** (apply to all action items before creating): if `config.gtd.contexts.mode = "explicit"` and `contexts_field` is set in the actions DB → detect context from the entry title/body and set the contexts_field value. If `mode = "auto"` → no field to set, context is inferred at runtime by morning-ritual. If `mode = "none"` → skip.

   **(a) atomic action with date** → `actions_id`. If `actions_id != capture_id` → create new entry with status = `actions_fields.status_open`, date = extracted date. If `actions_id == capture_id` → update the existing entry in place; only set fields that actually exist in the DB (check `notion.actions.fields` — skip any field that is null or empty); add date and status info to the entry body as text if the corresponding property doesn't exist in the DB; do NOT create a duplicate.

   **(a') atomic without time signal** → `actions_id` with status = `actions_fields.status_deferred` (if the field exists). Apply contextual inference first. If `status_deferred` is null (field doesn't exist in the DB) → leave the entry in Inbox as-is; append a note to its body: «💡 Действие без даты — запланируй когда будешь готов».

   **(a'') booking/ticket/event without explicit date** → fetch Gmail message body if source known, re-parse. If date found → rule (a). If still not found → leave in Inbox with note «дата не найдена — уточнить».

   **(b) multi-step / project** (several verbs, «проект», "organize", "prepare for X") → `projects_id` if set; else `actions_id`; else `capture_id`. Apply `projects_filter` when creating if set and the target is a shared DB. List the sub-steps in the entry body. If `projects_id == actions_id == capture_id` → enrich the existing entry body with «Шаги: 1. … 2. … 3. …», do NOT create a duplicate. Apply `/data/memory/feedback_task_vs_na.md`: if exactly 1 atomic action → classify as (a).

   **(c) informational** (reference, link, idea, article, contact — no action, no event) → `reference_id` if set, using `reference.fields.*` for category/tags/source/url. If `reference_id` is null → add to body of the Inbox entry with «📚» prefix and trash the original.

   Create destination via `mcp__notion__API-post-page`.

5. After routing → trash the Inbox entry: PATCH `/pages/{id}` with `{"in_trash": true}` (30-day recovery). Exception: if `actions_id == capture_id`, the entry was updated in place — do not trash.
6. Ambiguous entries → leave in Inbox, collect for ⚠️ section.

## Attachments

If an Inbox entry references a file URL hosted outside Drive (e.g. inline-uploaded by inbox-router), the file should already be in `config.google.drive_inbox_folder_id` on the **primary** account. Skill itself does no Drive uploads — that's inbox-router's job. Just preserve the link in the destination page body.

## Idempotency

If the skill is killed mid-run and retries, a second pass sees only not-yet-trashed entries (Notion excludes trashed pages from query results). Already-processed items are in trash. No further dedup needed.

## Output (one Telegram message)

«📥 Обработано: N записей» + sections using the user's actual DB names:
- **`actions_name`** (with dates, links) — if actions_id is set and items were routed there
- **Отложено** (titles, links) — deferred/someday items
- **`projects_name`** (titles, links) — if projects_id is set and items were routed there
- **`reference_name`** (with category/tags, links) — if reference_id is set
- **⚠️ Уточнить** — ambiguous ones with 2–3 options

If all roles point to the same DB — show one section with counts per status/tag.
Silent if Inbox is empty.

## Failure modes

- Notion MCP unauthenticated → send Telegram «⚠️ Notion недоступен — Inbox не обработан. Запусти `/cgtd-reauth notion`». Log `ok` (not `fail` — not a system error).
- Partial failure mid-batch: trash each Inbox item right after creating its destination so a crash leaves processed items consistent.
