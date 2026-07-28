#!/bin/bash
# Stop hook — before work can be called done, actually run the tests.
# This is the machinery half of the TDD skills: a rule the model grades
# itself on is a rule it can talk itself out of. This one it cannot.
#
# Deliberately quiet unless it has something real to say:
#   - no code changed this turn        -> silent
#   - project has no runnable suite    -> silent
#   - tests pass                       -> silent
#   - tests fail, or tests are skipped -> block, hand the output back
set -u

INPUT=$(cat 2>/dev/null || echo '{}')

# Never fight our own previous block — prevents a stop/fix/stop loop.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Only bother when source actually changed this turn.
CHANGED=$(git status --porcelain 2>/dev/null \
  | grep -Ev '(^.. )?(tests?|__tests__|e2e)/' \
  | grep -Eic '\.(ts|tsx|js|jsx|mjs|cjs|py|swift|go|rb|rs|java|kt)"?$' || true)
[ "${CHANGED:-0}" -eq 0 ] && exit 0

[ -f package.json ] || exit 0

# Pick a runner that exits on its own — never a watch-mode script.
PM=npm
[ -f pnpm-lock.yaml ] && PM=pnpm
[ -f yarn.lock ] && PM=yarn
[ -f bun.lockb ] && PM=bun

SCRIPT=""
for s in test:run test:ci test; do
  if jq -e --arg s "$s" '.scripts[$s] // empty' package.json >/dev/null 2>&1; then SCRIPT="$s"; break; fi
done
[ -z "$SCRIPT" ] && exit 0

CMD=$(jq -r --arg s "$SCRIPT" '.scripts[$s]' package.json)
EXTRA=""
# `vitest` with no subcommand watches forever; force a single run.
case "$CMD" in
  *vitest*) case "$CMD" in *" run"*|*--run*) ;; *) EXTRA="--run" ;; esac ;;
  *--watch*) exit 0 ;;
esac

OUT=$("$PM" run "$SCRIPT" ${EXTRA:+-- $EXTRA} 2>&1) ; CODE=$?
TAIL=$(printf '%s' "$OUT" | tail -c 1500)

# Number only — "0 skipped" is a healthy suite, not a problem to block on.
SKIPNUM=$(printf '%s' "$OUT" | grep -Eio '[0-9]+ skipped' | head -1 | grep -Eo '^[0-9]+' || true)

if [ $CODE -ne 0 ]; then
  jq -n --arg r "Tests are failing, so this work is not done. Fix the CODE, not the test — do not skip, weaken, or delete any test to get to green. If a test cannot be made real without setup you can't do (auth, test DB, credentials), stop and ask the user for it.

$TAIL" '{decision:"block",reason:$r}'
  exit 0
fi

if [ -n "$SKIPNUM" ] && [ "$SKIPNUM" -gt 0 ]; then
  jq -n --arg r "The suite reports $SKIPNUM skipped. A skipped test is a failing test — it has never proven anything. Either make those tests run for real, or ask the user for the setup they need (test account, database, credentials). Do not report this suite as passing.

$TAIL" '{decision:"block",reason:$r}'
  exit 0
fi

exit 0
