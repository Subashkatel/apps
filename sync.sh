#!/bin/bash
# Optional import from another checkout, with a preview by default.
set -euo pipefail
cd "$(dirname "$0")"
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: ./sync.sh /absolute/path/to/source [--apply]" >&2
  exit 1
fi
source_root="$1"
[ -d "$source_root" ] || { echo "Source directory not found" >&2; exit 1; }
source_root=$(cd "$source_root" && pwd -P)
[ "$source_root" != "$(pwd -P)" ] || { echo "Source and destination must differ" >&2; exit 1; }
args=(-a --itemize-changes)
if [ "${2:-}" = "--apply" ]; then :
elif [ $# -eq 1 ]; then args+=(--dry-run)
else echo "Unknown option: $2" >&2; exit 1
fi
for app in CodingAgentUsage Frontier Jot MeetingNotes PaperNotes Pomodoro VoiceBridge Shared; do
  [ -d "$source_root/$app" ] || continue
  rsync "${args[@]}" --exclude '.git' --exclude '.build' --exclude '/build' \
    --exclude '.DS_Store' --exclude 'models' --exclude 'reference' --exclude '*.app' --exclude 'build.noindex' \
    --exclude 'Recordings' --exclude 'Backups' --exclude '*.sqlite*' --exclude '*.caf' --exclude 'auth.json' \
    --exclude '*.iconset' "$source_root/$app/" "$app/"
done
[ "${2:-}" = "--apply" ] || echo "Preview only; use --apply to copy. Destination-only files are retained."
