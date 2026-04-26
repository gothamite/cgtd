# Example: workday-reminder

Adapt-it-yourself example. A short Telegram reminder pinging you on weekdays at a fixed time to log time in your company's timesheet system. Day-job-specific; not shipped by default.

## Add the skill

Create `skills/workday-reminder/SKILL.md`:

```markdown
---
name: workday-reminder
description: Short one-line Telegram reminder to log yesterday's time in <your timesheet system>. Weekdays only.
---

# Workday-reminder

Invoked by cron (default `33 10 * * 1-5`) or manually.

## Pre-flight

Read `/data/config.json`. Required: `telegram.chat_id`, `user.locale`.

## Logging wrapper

\```
RID=$(/app/bin/cron-log.sh start workday-reminder)
/app/bin/cron-log.sh lock workday-reminder || exit 0
\```

End with `ok "$RID"` or `fail "$RID" "msg"`.

## Procedure

Send one short line to `config.telegram.chat_id` via `mcp__plugin_telegram_telegram__reply`. Vary wording to avoid notification fatigue. Examples by locale:

- en: "log yesterday's hours" / "Workday reminder: time entry due" / "ping: timesheet"
- ru: «не забудь затрекать вчерашнее время» / «Workday: внеси часы за вчера»
- de: "Zeiterfassung für gestern nicht vergessen"

Skip if it's Saturday or Sunday (the cron expression already excludes weekends; manual invocation on weekend should reply «выходной, тайм-трекинг не нужен»).
```

## Add the cron

Inside the container:

```
docker compose exec assistant claude
```

Then in Claude Code:

```
add a cron `cgtd-${install_id}-workday-reminder` with expression `33 10 * * 1-5` and prompt: Invoke skill workday-reminder. install_dir=/data. Wrap with /app/bin/cron-log.sh.
```

Or edit `config.json` to add it under `jobs` and re-run `/init-cgtd` → "reconcile crons".

## Customize

- Change cron expression for your timezone / preferred ping time.
- Add a link to your timesheet web app in the message body.
- Branch by day-of-week (e.g. silent reminders Mon–Thu, louder on Fri because end-of-week deadline).
- Suppress when you've already logged time (call your timesheet API first; skip the ping if today's entry is filed).

## More ideas for custom skills

- `weekly-review` — Friday afternoon, summarize the week, prep next-week's anchors.
- `gym-prompt` — every Tuesday/Thursday morning, ask if today is a gym day, add NA.
- `bday-watch` — daily, scan Notion contacts for upcoming birthdays, add gift NA with appropriate buffer.
- `expense-capture` — when a Telegram message looks like a receipt photo, OCR it and append to a Notion expenses DB instead of generic Inbox.

The shipped skills are deliberately simple. Fork them, copy-paste, and shape the assistant to your life.
