#!/usr/bin/env bash
# HomeView serverini to‘xtatish va o‘chirish.
set -euo pipefail
LABEL="uz.homeview.server"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Server to‘xtatildi. Papka saqlab qolindi: $HOME/HomeViewServer (kerak bo‘lmasa o‘chiring)."
