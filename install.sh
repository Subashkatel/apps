#!/bin/bash
# Build and install selected apps. Launch only when --launch is passed.
set -euo pipefail
cd "$(dirname "$0")"
apps=()
launch=1
for arg in "$@"; do
  case "$arg" in
    --launch) launch=0;;
    CodingAgentUsage|Frontier|Jot|MeetingNotes|PaperNotes|Pomodoro|VoiceBridge) apps+=("$arg");;
    *) echo "Usage: ./install.sh [--launch] [CodingAgentUsage Frontier Jot MeetingNotes PaperNotes Pomodoro VoiceBridge]" >&2; exit 1;;
  esac
done
[ ${#apps[@]} -ne 0 ] || apps=(CodingAgentUsage Frontier Jot MeetingNotes PaperNotes Pomodoro VoiceBridge)
for app in "${apps[@]}"; do
  INSTALL=1 NO_LAUNCH="$launch" "$app/build.sh"
done
echo "Installed in ${INSTALL_DIR:-/Applications}."
