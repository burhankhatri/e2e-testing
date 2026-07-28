#!/bin/bash
# Install Superpowers-inspired global skills for Claude Code
# Usage: bash install.sh

set -e

SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Installing Global Claude Code Skills ==="
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
if [ -f "$CLAUDE_MD" ]; then
  echo "  ⚠ ~/.claude/CLAUDE.md already exists."
  echo "  The new orchestrator CLAUDE.md is saved as:"
  echo "    $SCRIPT_DIR/CLAUDE.md"
  echo ""
  echo "  You can:"
  echo "    1. Merge it manually into your existing CLAUDE.md"
  echo "    2. Replace: cp $SCRIPT_DIR/CLAUDE.md $CLAUDE_MD"
  echo ""
else
  cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_MD"
  echo "  Installed: ~/.claude/CLAUDE.md"
fi

echo ""

# ── Enforcement hooks (opt-in) ────────────────────────────────────────────
# Skills are prompts: they only apply when they load, and the model grades
# itself against them. Hooks are run by the harness, so they hold even when
# nobody remembers. This is the part that actually makes green mean green.
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/tdd-remind.sh" "$SCRIPT_DIR/hooks/tdd-verify.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/tdd-remind.sh" "$HOOKS_DIR/tdd-verify.sh"
echo "  Installed: ~/.claude/hooks/ (tdd-remind.sh, tdd-verify.sh)"
echo ""

wire_hooks() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ⚠ jq not found — hooks need it. Install jq, then re-run this script."
    return 1
  fi
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    echo "  ⚠ $SETTINGS is not valid JSON — not touching it. Fix it and re-run."
    return 1
  fi
  if jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("tdd-verify"))' "$SETTINGS" >/dev/null 2>&1; then
    echo "  Hooks already wired up — leaving settings.json alone."
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
    && echo "  Wired into ~/.claude/settings.json (backup saved alongside)." \
    || { rm -f "$SETTINGS.tmp"; echo "  ⚠ Merge failed — settings.json left unchanged."; return 1; }
}

echo "The hooks add two guarantees, enforced outside the model:"
echo "  • every prompt carries the TDD rules, with no skill to remember"
echo "  • before work is called done, your test suite actually runs —"
echo "    failing or skipped tests send the agent back instead of finishing"
echo ""
echo "They stay quiet when no code changed, and when a project has no suite."
echo "This edits ~/.claude/settings.json (merged, backed up, never overwritten)."
echo ""
if [ -t 0 ]; then
  printf "Enable the enforcement hooks? [y/N] "
  read -r REPLY
  case "$REPLY" in
    [yY]*) wire_hooks ;;
    *) echo "  Skipped. Enable later by re-running this script." ;;
  esac
else
  echo "  Non-interactive install — hooks copied but NOT enabled."
  echo "  Re-run 'bash install.sh' from a terminal to turn them on."
fi

echo ""
echo "=== Done! ==="
echo ""
echo "Installed 8 global skills to $SKILLS_DIR/"
echo ""
echo "Skills available:"
echo "  /start                  — master orchestrator: routes tasks through the full pipeline"
echo "  /tdd                    — strict red-green-refactor TDD"
echo "  /debug                  — 4-phase root cause debugging"
echo "  /verify-done            — evidence before completion claims"
echo "  /brainstorm-and-plan    — design + implementation planning"
echo "  /e2e-playwright         — Playwright E2E golden rules + patterns"
echo "  /test-loop              — autonomous test-fix iteration cycle"
echo "  /code-review            — two-stage spec + quality review"
echo ""
echo "Next steps:"
echo "  1. Open Claude Code in any project"
echo "  2. Skills activate automatically based on context"
echo "  3. Or invoke directly: /tdd, /debug, /test-loop, etc."
echo "  4. Create a testing.md in your project root (see /test-loop)"
