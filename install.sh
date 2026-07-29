#!/bin/bash
# Install Superpowers-inspired global skills for Claude Code
# Usage: bash install.sh

set -e

SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Test-First Skills for Claude Code ==="
echo ""
echo "What this is for:"
echo "  Claude writes code fast, but it will also tell you something works"
echo "  when it doesn't. This makes Claude write a test BEFORE the code, and"
echo "  actually run your tests before it says the work is done."
echo ""
echo "It will ask you 2 yes/no questions. Nothing is changed without asking,"
echo "and anything it edits gets backed up first."
echo ""

# Create skills directory
mkdir -p "$SKILLS_DIR"

# List of skills to install
SKILLS=(
  "start"
  "tdd"
  "systematic-debugging"
  "verification"
  "brainstorming-and-planning"
  "e2e-playwright"
  "test-automation-loop"
  "code-review"
)

for skill in "${SKILLS[@]}"; do
  src="$SCRIPT_DIR/skills/$skill"
  dest="$SKILLS_DIR/$skill"
  
  if [ -d "$dest" ]; then
    echo "  Updating: $skill"
    rm -rf "$dest"
  else
    echo "  Installing: $skill"
  fi
  
  cp -r "$src" "$dest"
done

echo ""

# Handle CLAUDE.md
# ~/.claude/CLAUDE.md loads in EVERY session with nothing to invoke, which
# makes it the piece that actually routes work into the skills. Leaving it
# out because a file already exists means the skills mostly never fire — so
# offer to append the rules instead of just warning and walking away.
MARKER_BEGIN="<!-- BEGIN e2e-testing skills — TDD rules -->"
MARKER_END="<!-- END e2e-testing skills -->"

append_essentials() {
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak-$(date +%Y%m%d-%H%M%S)"
  {
    printf '\n%s\n' "$MARKER_BEGIN"
    cat "$SCRIPT_DIR/claude-md-essentials.md"
    printf '%s\n' "$MARKER_END"
  } >> "$CLAUDE_MD"
  echo "  Done — rules added to the bottom of your file. Old copy saved next to it."
}

if [ ! -f "$CLAUDE_MD" ]; then
  cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_MD"
  echo "  Set up your standing notes for Claude: ~/.claude/CLAUDE.md"
elif grep -qF "$MARKER_BEGIN" "$CLAUDE_MD" 2>/dev/null; then
  echo "  Your notes already have these rules — nothing to do."
elif grep -qF "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST" "$CLAUDE_MD" 2>/dev/null; then
  echo "  Your notes already say to test first — leaving them alone."
else
  echo "  ── Question 1 of 2 ──────────────────────────────────────────────"
  echo ""
  echo "  You already have a file at ~/.claude/CLAUDE.md. That's your"
  echo "  standing notes to Claude — it reads them at the start of every"
  echo "  chat. If the testing rules aren't in there, Claude will usually"
  echo "  ignore them."
  echo ""
  echo "  We can add about 20 lines to the BOTTOM of that file: the testing"
  echo "  rules, plus a short list of when to use each skill."
  echo ""
  echo "  Saying yes:  nothing you wrote is changed or deleted, and a copy"
  echo "               of your current file is saved first."
  echo "  Saying no:   the skills still install, but Claude will mostly"
  echo "               forget to use them."
  echo ""
  if [ -t 0 ]; then
    printf "  Add the testing rules to your notes? [y/N] "
    read -r REPLY
    case "$REPLY" in
      [yY]*) append_essentials ;;
      *) echo "  Skipped. You can add them any time by running:"
         echo "    cat $SCRIPT_DIR/claude-md-essentials.md >> $CLAUDE_MD" ;;
    esac
  else
    echo "  (Not a terminal, so nothing was asked or changed.)"
    echo "  To add the rules yourself:"
    echo "    cat $SCRIPT_DIR/claude-md-essentials.md >> $CLAUDE_MD"
  fi
  echo ""
fi

echo ""

# ── Enforcement hooks (opt-in) ────────────────────────────────────────────
# Skills are prompts: they only apply when they load, and the model grades
# itself against them. Hooks are run by the harness, so they hold even when
# nobody remembers. This is the part that actually makes green mean green.
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/tdd-remind.sh" "$SCRIPT_DIR/hooks/tdd-verify.sh" "$SCRIPT_DIR/toggle.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/tdd-remind.sh" "$HOOKS_DIR/tdd-verify.sh" "$HOOKS_DIR/toggle.sh"
echo "  Copied 2 helper scripts to ~/.claude/hooks/ (not switched on yet)"
echo "  You can turn them off any time with:  bash ~/.claude/hooks/toggle.sh off"
echo ""

wire_hooks() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  Can't switch these on: a tool called 'jq' isn't installed."
    echo "  Install it (on a Mac: brew install jq), then run this script again."
    return 1
  fi
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    echo "  Your ~/.claude/settings.json has a typo in it, so it wasn't touched."
    echo "  Fix that file, then run this script again."
    return 1
  fi
  if jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("tdd-verify"))' "$SETTINGS" >/dev/null 2>&1; then
    echo "  These are already switched on — nothing to do."
    return 0
  fi

  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  jq '. + {hooks: ((.hooks // {}) + {
    UserPromptSubmit: ((.hooks.UserPromptSubmit // []) + [{
      hooks: [{ type: "command", command: "\"$HOME/.claude/hooks/tdd-remind.sh\"", timeout: 10 }]
    }]),
    Stop: ((.hooks.Stop // []) + [{
      hooks: [{ type: "command", command: "\"$HOME/.claude/hooks/tdd-verify.sh\"", timeout: 120, statusMessage: "Verifying tests before finishing…" }]
    }])
  })}' "$SETTINGS" > "$SETTINGS.tmp" \
    && jq -e . "$SETTINGS.tmp" >/dev/null \
    && mv "$SETTINGS.tmp" "$SETTINGS" \
    && echo "  Done — both are on. Old settings file saved next to it." \
    || { rm -f "$SETTINGS.tmp"; echo "  Something went wrong — your settings were left as they were."; return 1; }
}

echo "  ── Question 2 of 2 ──────────────────────────────────────────────"
echo ""
echo "  Two optional helpers. Unlike the rules above, these are run by"
echo "  your computer, not by Claude — so Claude can't forget them or"
echo "  talk itself out of them."
echo ""
echo "    1. A reminder. Every message you send quietly re-states the"
echo "       testing rules, so you never have to type a command."
echo ""
echo "    2. A checker. When Claude thinks it has finished, your tests"
echo "       are actually run. If a test fails — or was skipped — Claude"
echo "       is sent back to fix it instead of telling you it's done."
echo ""
echo "  They stay out of your way: nothing runs when you haven't changed"
echo "  any code, or in projects that don't have tests yet."
echo ""
echo "  Saying yes:  adds 2 lines to ~/.claude/settings.json. A copy is"
echo "               saved first, and nothing already in there is removed."
echo "  Saying no:   the skills still work; you just have to ask for them."
echo ""
if [ -t 0 ]; then
  printf "  Switch on the reminder and the checker? [y/N] "
  read -r REPLY
  case "$REPLY" in
    [yY]*) wire_hooks ;;
    *) echo "  Skipped. Run this script again any time to switch them on." ;;
  esac
else
  echo "  (Not a terminal, so nothing was asked or changed.)"
  echo "  Run 'bash install.sh' in a terminal to switch them on."
fi

echo ""
echo "=== All set ==="
echo ""
echo "Open Claude Code in any project and type one of these:"
echo ""
echo "  /start <what you want>   The whole routine: plan it, write the test"
echo "                           first, build it, then prove it works."
echo "                           Start here — it runs the rest for you."
echo ""
echo "  /tdd                     Build one piece, test written first"
echo "  /debug                   Something's broken — find the real cause"
echo "                           before changing anything"
echo "  /verify-done             Prove it works before believing it"
echo "  /brainstorm-and-plan     Think a design through before any code"
echo "  /e2e-playwright          Tests that click through your app like a user"
echo "  /test-loop               Let Claude keep fixing until tests pass"
echo "  /code-review             Check finished work against the plan"
echo ""
echo "Try this first:"
echo "  /start add a login page"
echo ""
echo "You should see it write a test, watch it fail, then write the code."
echo "That failing test is the point — it proves the test actually checks"
echo "something. If you never see one fail, it isn't really testing."
