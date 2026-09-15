#!/bin/bash
# Assemble signed bundles without installing or launching them.
set -euo pipefail
cd "$(dirname "$0")"
apps=("$@")
[ ${#apps[@]} -ne 0 ] || apps=(CodingAgentUsage Frontier Jot MeetingNotes PaperNotes Pomodoro VoiceBridge)
for app in "${apps[@]}"; do
  case "$app" in CodingAgentUsage|Frontier|Jot|MeetingNotes|PaperNotes|Pomodoro|VoiceBridge) ;; *) echo "Unknown app: $app" >&2; exit 1;; esac
done
for app in "${apps[@]}"; do
  echo "Building $app"
  INSTALL=0 NO_LAUNCH=1 "$app/build.sh"
done
