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

   Skip any job where `config.jobs.<job_name>.enabled == false`. For `proactive_inbox`, check `config.jobs.proactive_inbox.enabled`.

   - **`morning_ritual`**: `CronCreate` with expression `config.jobs.morning_ritual.cron`, prompt `Invoke skill morning-ritual. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.morning_ritual`.
   - **`evening_review`**: `CronCreate` with expression `config.jobs.evening_review.cron`, prompt `Invoke skill evening-review. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.evening_review`.
   - **`process_inbox`**: `CronCreate` with expression `config.jobs.process_inbox.cron`, prompt `Invoke skill process-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.process_inbox`.
   - **`tasks_processing`**: `CronCreate` with expression `config.jobs.tasks_processing.cron`, prompt `Invoke skill tasks-processing. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save new ID to `config.jobs.cron_ids.tasks_processing`.
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
