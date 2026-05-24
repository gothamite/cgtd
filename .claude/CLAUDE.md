# Telegram communication rule

Every response to a Telegram message MUST be sent via `mcp__plugin_telegram_telegram__reply`. Console/transcript output is invisible to the user in Telegram. Never rely on text output alone — always call the reply tool. This applies to every turn, including skill results, confirmations, and error messages.

Use `format="markdownv2"` for rich formatting. Escape special chars per MarkdownV2 rules: `.` → `\.`, `-` → `\-`, `(` → `\(`, `)` → `\)`, `!` → `\!`, `_` → `\_` when not used for formatting. Links: `[text](url)`.

# Session startup

At the start of every session, before doing anything else:

1. Read `/data/config.json`. If `config.user.persona_file` is non-empty, also read `/root/.claude/projects/-app/memory/<config.user.persona_file>` and apply the described persona to all Telegram replies from this point on.
2. If `init_complete` is `true` and `jobs` block exists:
   - Call `CronList` to see what's currently scheduled.
   - For each enabled job in `config.jobs`, if its cron is not present in CronList output, recreate it with `CronCreate` (recurring: true) using the schedule and prompt below.
   - After recreating, update `config.jobs.cron_ids` in `/data/config.json` with the new IDs.
3. Do this silently — no Telegram message, no user notification unless something fails.

## Cron prompts and schedules

| Job | config key | cron expression | prompt |
|-----|-----------|-----------------|--------|
| morning-ritual (weekday) | `jobs.morning_ritual` | `config.jobs.morning_ritual.cron_weekday` | `/morning-ritual` |
| morning-ritual (weekend) | `jobs.morning_ritual` | `config.jobs.morning_ritual.cron_weekend` | `/morning-ritual` |
| evening-review | `jobs.evening_review` | `config.jobs.evening_review.cron` | `/evening-review` |
| process-inbox | `jobs.process_inbox` | `config.jobs.process_inbox.cron` | `/process-inbox` |
| tasks-processing | `jobs.tasks_processing` | `config.jobs.tasks_processing.cron` | `/tasks-processing` |
| proactive-inbox (weekday) | `jobs.proactive_inbox` | `config.jobs.proactive_inbox.cron_weekday` | `/proactive-inbox` |
| proactive-inbox (weekend) | `jobs.proactive_inbox` | `config.jobs.proactive_inbox.cron_weekend` | `/proactive-inbox` |

## Matching logic

Compare CronList output against expected cron expressions. A job is "missing" if no entry in CronList has a matching cron expression and prompt. Recreate only missing jobs — don't duplicate.

## Catch-up for missed once-a-day jobs

After recreating cron jobs, check whether `process_inbox`, `tasks_processing`, or `evening_review` were missed (e.g., session restarted after their scheduled time):

For each job:
1. Run `/app/bin/cron-log.sh last-ok <job-name>` to get the last successful run timestamp.
2. Parse the cron expression from `config.jobs` to compute the most recent expected fire time today in `config.user.timezone`.
3. If the expected fire time is **in the past** AND `last-ok` is **before** that expected fire time → run the skill immediately.
4. Run in order: process-inbox first, then tasks-processing (depends on inbox), then evening-review.

**Rule: process-inbox and tasks-processing must both complete before evening-review. Never run evening-review without both having run today.**

Do **not** catch up: `morning-ritual` (time-sensitive, only useful in the morning) and `proactive-inbox` (runs many times a day, gaps are acceptable).

Still do this silently — no Telegram message unless the caught-up skill itself sends one.
