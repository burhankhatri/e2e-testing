#!/bin/bash
# UserPromptSubmit hook — keeps the two TDD rules in context on every turn,
# so the discipline doesn't depend on remembering to invoke a skill.
# Stays quiet outside code projects so it isn't noise in a notes folder.
set -u

# Switched off via `bash toggle.sh off` — check this before anything else.
[ -f "$HOME/.claude/hooks/.disabled" ] && exit 0

looks_like_code=0
git rev-parse --git-dir >/dev/null 2>&1 && looks_like_code=1
for f in package.json pyproject.toml go.mod Cargo.toml Gemfile pom.xml build.gradle Package.swift; do
  [ -e "$f" ] && looks_like_code=1 && break
done
ls *.xcodeproj >/dev/null 2>&1 && looks_like_code=1

[ "$looks_like_code" -eq 0 ] && exit 0

read -r -d '' NOTE <<'EOF'
TDD rules for any code change in this project:
1. Write the failing test FIRST and show it fail before implementing. Commit the red test on its own.
2. Never skip, weaken, or delete a test to reach green. A skipped test is a failing test — always report passed/failed/SKIPPED counts.
3. If a test cannot be made real (needs auth, a test DB, credentials), STOP and ask the user for that one-time setup. Do not mock around it.
EOF

jq -n --arg c "$NOTE" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
