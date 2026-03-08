#!/bin/bash
# Smart sleep: disable sleep on AC, enable on battery
# Runs on power source change via launchd WatchPaths
POWER=$(pmset -g ps | head -1)
if echo "$POWER" | grep -q "AC Power"; then
  sudo pmset -a disablesleep 1
  sudo pmset -a sleep 0
  # caffeinate keeps network alive even with lid closed
  pgrep -f "caffeinate -s" >/dev/null || nohup caffeinate -s &>/dev/null &
else
  sudo pmset -a disablesleep 0
  sudo pmset -a sleep 1
  # let Mac sleep normally on battery
  pkill -f "caffeinate -s" 2>/dev/null
fi
