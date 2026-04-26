# Notion setup

The assistant needs four databases (**Inbox, Next Actions, Tasks, Notes**) and one page (**📦 Inbox Archive**). 10 minutes to create from scratch, or 30 seconds if you already have a GTD setup.

## Step 1 — create an integration

1. https://www.notion.so/my-integrations → **New internal integration**.
2. Name: `cgtd`. Workspace: yours.
3. Capabilities: Read, Insert, Update content. (Comment is optional.)
4. Copy the **Internal Integration Token**. Paste into `.env`:
   ```
   NOTION_TOKEN=secret_...
   ```

## Step 2 — create the databases

If you already have a GTD setup in Notion, skip this and just record the URLs.

Otherwise, create a parent page (e.g. "GTD") and inside it create four full-page databases. Suggested schemas — adapt as you like:

### Inbox
| Property | Type |
|----------|------|
| Name | Title |
| Source | Select (Telegram / Email / Manual) |
| Created | Created time |
| URL | URL (optional, for attachments) |

### Next Actions
| Property | Type |
|----------|------|
| Name | Title |
| Status | Status (Not started / In progress / Done / Cancelled / Someday/Maybe) |
| Date | Date (with time) |
| Project | Relation → Tasks |
| Eisenhower | Select (Q1/Q2/Q3/Q4) |

### Tasks (multi-step projects)
| Property | Type |
|----------|------|
| Name | Title |
| Status | Status |
| Deadline | Date |

### Notes
| Property | Type |
|----------|------|
| Name | Title |
| Category | Select (Reference / Idea / Recipe / Article / Contact / Quote) |
| Tags | Multi-select |
| Source | Select (Telegram / Web / Email / Manual) |
| URL | URL |

### 📦 Inbox Archive
A regular page (not a database). Inbox items get moved here as children after processing.

## Step 3 — share with the integration

Open each database (and the Archive page). Top-right "Share" → "Connections" → add the integration you created. **Do this for all four databases AND the archive page** — without sharing, the integration can't read or write.

## Step 4 — collect URLs

Open each database and copy its URL. Format:
```
https://www.notion.so/<workspace>/<title-slug>-<32-char-hex>?v=...
```

The 32-char hex at the **end** of the path (immediately before `?v=`) is the data_source ID. The slug before it is decorative and varies. Just paste the whole URL — the init skill extracts the ID for you.

For the archive **page**, copy its page URL the same way.

## Step 5 — run /init-cgtd

Inside the container, `/init-cgtd` asks for each URL one at a time and validates by fetching the database. If validation fails (404 / forbidden), you forgot to share with the integration — go back to Step 3.

## Customizing the schema

The skills reference specific Status values ("Not started", "Done", "Cancelled", "Someday/Maybe"). If you use different names, edit the relevant SKILL.md files in `skills/` to match. Eisenhower (Q1–Q4) is referenced in `morning-ritual` for prioritizing Someday/Maybe; if you don't use Eisenhower, the skill falls back to title-only prioritization (less precise, still works).
