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

# Work out how to run this project's tests. Prefer an explicit script, but
# fall back to the runner the project obviously uses: a suite that exists
# without being wired to a script is exactly the case that used to slip past
# this hook entirely, which made it silent on the projects most likely to
# have been built in a hurry.
RUN=""

if [ -f package.json ]; then
  PM=npm
  [ -f pnpm-lock.yaml ] && PM=pnpm
  [ -f yarn.lock ] && PM=yarn
  [ -f bun.lockb ] && PM=bun

  SCRIPT=""
  for s in test:run test:ci test; do
    if jq -e --arg s "$s" '.scripts[$s] // empty' package.json >/dev/null 2>&1; then SCRIPT="$s"; break; fi
  done

  if [ -n "$SCRIPT" ]; then
    CMD=$(jq -r --arg s "$SCRIPT" '.scripts[$s]' package.json)
    case "$CMD" in
      # a watch-mode script never exits; leave it alone rather than hang
      *--watch*|*watch*) exit 0 ;;
      # bare `vitest` also watches forever — force a single run
      *vitest*) case "$CMD" in
                  *" run"*|*--run*) RUN="$PM run $SCRIPT" ;;
                  *)                RUN="$PM run $SCRIPT -- --run" ;;
                esac ;;
      *) RUN="$PM run $SCRIPT" ;;
    esac
  fi
fi

# No script, but there may still be a suite sitting right there.
# NB: `ls a b` exits non-zero when ANY operand is missing, even if others
# matched — so check the expanded globs for a real file instead.
any_exists() { for f in "$@"; do [ -e "$f" ] && return 0; done; return 1; }

if [ -z "$RUN" ]; then
  if any_exists ./*.test.js ./*.test.mjs ./*.test.cjs \
                tests/*.test.js tests/*.test.mjs test/*.test.js test/*.test.mjs; then
    command -v node >/dev/null 2>&1 && RUN="node --test"
  elif any_exists ./test_*.py tests/test_*.py test/test_*.py; then
    command -v pytest >/dev/null 2>&1 && RUN="pytest -q"
  fi
fi

[ -z "$RUN" ] && exit 0

OUT=$($RUN 2>&1) ; CODE=$?
# Runners emit ANSI colour and carriage returns when they think they're on a
# TTY; strip them so the report stays readable and can't corrupt the JSON.
TAIL=$(printf '%s' "$OUT" | tail -c 1500 \
  | LC_ALL=C sed $'s/\033\[[0-9;?]*[a-zA-Z]//g' \
  | LC_ALL=C tr -d '\r\000-\010\013\014\016-\037')

# Runners disagree on word order: vitest/playwright/pytest say "18 skipped",
# node --test says "skipped 1". Match both, take the largest, and treat 0 as
# healthy — blocking a suite that proudly reports "0 skipped" would be absurd.
SKIPNUM=$(printf '%s' "$OUT" \
  | grep -Eio '([0-9]+[[:space:]]+skipped|skipped[[:space:]:]+[0-9]+)' \
  | grep -Eo '[0-9]+' | sort -rn | head -1 || true)

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
