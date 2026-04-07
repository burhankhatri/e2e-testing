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
