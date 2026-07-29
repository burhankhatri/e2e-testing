#!/bin/bash
# Turn the reminder and the test-checker on or off, instantly.
#
# This never touches ~/.claude/settings.json. It just drops (or removes) a
# small marker file that both hooks check for themselves before doing
# anything else. That means:
#   - toggling can never corrupt your settings
#   - it works even if this repo is later deleted (the marker lives in
#     ~/.claude/hooks/, alongside the scripts it controls)
#
# Usage:
#   bash toggle.sh off       switch off — nothing is deleted
#   bash toggle.sh on        switch back on
#   bash toggle.sh status    show which it currently is
set -u

FLAG="$HOME/.claude/hooks/.disabled"

usage() {
  echo "Usage: bash toggle.sh [off|on|status]"
  echo ""
  echo "  off      Claude stops being reminded to test first, and stops"
  echo "           being checked before it can call anything done."
  echo "           Nothing is deleted — just switched off."
  echo "  on       Switch it back on."
  echo "  status   Show whether it's currently on or off."
}

case "${1:-}" in
  off)
    mkdir -p "$(dirname "$FLAG")"
    touch "$FLAG"
    echo "Off."
    echo "Claude won't be reminded to test first, and won't be checked before it says it's done."
    echo "Turn it back on any time:  bash toggle.sh on"
    ;;
  on)
    rm -f "$FLAG"
    echo "On."
    echo "Every message reminds Claude to test first. Tests run before Claude can call anything done."
    ;;
  status)
    if [ ! -f "$HOME/.claude/hooks/tdd-verify.sh" ]; then
      echo "Not installed yet. Run: bash install.sh"
    elif [ -f "$FLAG" ]; then
      echo "Currently: OFF"
    else
      echo "Currently: ON"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
