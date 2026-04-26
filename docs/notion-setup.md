# Notion setup

The assistant uses Notion for its entire GTD system. There is **no token to paste** — Notion auth happens via OAuth during the Telegram-driven interview (`/gtd-config`). You don't need to do anything in Notion before starting; the interview can even create the GTD databases for you.

This doc covers what the system needs, how access restriction works, and what the default schema looks like if you let the assistant create one.

## Two paths

When the Telegram interview reaches the Notion section, the bot asks: «do you already have a GTD setup in Notion?»

- **No** → the bot creates a parent page «🗂 GTD» (under a location you choose) with four databases (Inbox, Next Actions, Tasks, Notes) and a child page «📦 Inbox Archive». You're done — every shipped skill works out of the box. Schemas listed below.
- **Yes** → the bot asks for the URLs of your existing databases, probes their property layouts, and asks you about Status values, priority scheme, and how you use the system. It then rewrites its skills (in `/data/skills-overlay/`) to use your vocabulary.

In both paths, the user's manual job in Notion is the same single step: **share the GTD parent page with the cgtd integration during the Notion OAuth consent screen.**

## How the OAuth consent screen works

When the Telegram interview opens the Notion authorization link, you'll see Notion's standard consent screen with a list of pages. **Pick the single parent page that holds (or will hold) all your GTD databases.** Sharing is inherited — every database and child page under that parent is automatically accessible.

What this means for privacy: anything in your Notion workspace that you didn't explicitly share is **invisible** to the assistant. Notion enforces this server-side. Even if the assistant somehow guessed a page ID, the API returns 403. You can revoke access at any time from Notion's "Connections" panel.

If you want the strictest possible scope: create one page (e.g. "GTD") and share only that page during OAuth. All four GTD databases live under it. The rest of your workspace is invisible.

## Default schema (what the bot creates if you say "no")

### Inbox database
| Property | Type |
|----------|------|
| Name | Title |
| Source | Select (Telegram / Email / Manual) |
| Created | Created time |
| URL | URL (optional, for attachments) |

### Next Actions database
| Property | Type |
|----------|------|
| Name | Title |
| Status | Status (Not started / In progress / Done / Cancelled / Someday/Maybe) |
| Date | Date (with time) |
| Project | Relation → Tasks |
| Eisenhower | Select (Q1/Q2/Q3/Q4) |

### Tasks database (multi-step projects)
| Property | Type |
|----------|------|
| Name | Title |
| Status | Status |
| Deadline | Date |

### Notes database
| Property | Type |
|----------|------|
| Name | Title |
| Category | Select (Reference / Idea / Recipe / Article / Contact / Quote) |
| Tags | Multi-select |
| Source | Select (Telegram / Web / Email / Manual) |
| URL | URL |

### 📦 Inbox Archive
A regular page (not a database). Inbox items get moved here as children after the nightly `process-inbox` job classifies them.

## Customizing your existing schema

If you already have a GTD setup, the interview asks about each database in turn:

- "Where's your Inbox?" — paste the URL.
- "Where's Next Actions?" — paste.
- "Do you have a Tasks/projects DB? Notes DB? Archive page?" — yes/no + URL.
- "What's your Status property called and what values does it have?" — the bot lists the values it sees and asks you which means «open / in progress / done / cancelled / deferred».
- "Do you use a priority scheme — Eisenhower, P1-P4, MoSCoW, none?" — your answer drives how `morning-ritual` prioritizes Someday/Maybe items.
- "Tell me how you use this system day-to-day, in your own words" — the bot saves this verbatim and feeds it into every skill so morning briefs and evening reviews speak in your terms.

Your answers become customized skill files in `/data/skills-overlay/`. The shipped templates in `/app/skills/` are never modified, so `git pull` + `docker compose build` always brings the latest templates while preserving your overlay.

## Re-running the Notion interview

If you change your Notion setup later (rename a Status value, add a new DB, etc.), DM your bot:

```
/gtd-config
```

Pick "reconfigure Notion" or "regenerate skill overlay" from the menu.

## Re-authorizing Notion

If Notion's OAuth token gets revoked or expires:

```
/cgtd-reauth notion
```

The bot sends a new OAuth link; you re-share pages and pick up where you left off.
