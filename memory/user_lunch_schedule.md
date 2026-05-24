---
name: user-lunch-schedule
description: Lunch timing by context — home vs work, for use in day planning
metadata:
  type: user
---

Lunch timing varies by location (store in `config.user.lunch_home` / `config.user.lunch_work` if user specifies custom times, otherwise use defaults):

- **At home** (weekends, remote days): ~14:30–15:00
- **At work** (office days): ~12:20–13:00

Always use the correct window when planning the day — don't slot lunch at 12:30 on a Sunday at home.
