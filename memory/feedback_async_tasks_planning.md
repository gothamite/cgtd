---
name: feedback-async-tasks-planning
description: "Background/async tasks (laundry, 3D printing, cooking) must be split into launch+wait+finish and the wait window filled with other NAs"
metadata:
  type: feedback
---

Some NAs are not single-step — they have a background machine phase. Always detect and split these:

- **Laundry** (стирка, постирать): [put in machine ~10 min] → [machine runs 60–90 min, free] → [hang dry ~15 min]
- **3D printing** (печать, напечатать): [prep: clean resin + load model ~45–60 min] → [printer runs, free] → [post-process: wash + support removal ~20 min]
- **Cooking** (варить, тушить, запекать): [prep] → [oven/stove runs, free] → [finish/plate]

**Why:** "Напечатать" estimated at 25 min when realistic prep alone is 45–60 min, plus autonomous print time. Ignoring the async structure wastes the background window and underestimates effort.

**How to apply:** In morning-ritual and any planning context — when detecting these NA types, explicitly split into 3 slots: launch, background window (fill with other compatible NAs), finish. Track in `/data/background-tasks.json`. Show user only prep + finish slots, no internal annotations.
