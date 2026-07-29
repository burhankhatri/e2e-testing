---
name: toggle-tdd
description: "Turn the TDD enforcement hooks on or off, or check which they currently are. Use when the user says anything like 'turn off the tests', 'disable the TDD hooks', 'stop checking my tests', 'I don't want this enforced right now', 'turn testing back on', 're-enable the TDD stuff', or asks whether the hooks are currently on or off. Also covers /toggle-tdd."
---

# Toggle TDD Enforcement

The user wants to switch the reminder hook and the test-checking hook on, off,
or wants to know which they currently are. Just do it — don't explain the
mechanism unless asked.

```bash
bash ~/.claude/hooks/toggle.sh off      # user wants it off
bash ~/.claude/hooks/toggle.sh on       # user wants it back on
bash ~/.claude/hooks/toggle.sh status   # user is asking, not telling
```

Run the one that matches what they asked for, then report the single line it
prints back — don't add anything else unless they ask.

If the command fails because the file doesn't exist, the hooks were never
installed on this machine. Tell the user that plainly and point them at
`bash install.sh` in this repo.
