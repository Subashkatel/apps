# Pomodoro

A menu bar focus timer with full-screen break reminders and local session history.

Build: `./build.sh Pomodoro` from the repository root. Install: `./install.sh Pomodoro`.

Set work and break durations in the app. The timer uses elapsed time rather than assuming every timer callback arrives on schedule. Session records are stored in `<dataRoot>/Pomodoro/sessions.jsonl`.

Optional work detection uses the foreground app and input-idle duration. The default mode asks before starting a session. Add your own app names or bundle identifiers to `~/.config/pomodoro/work-apps.txt`, or configure `pomodoroWorkAppsFile`. A new list starts empty; existing lists are preserved. No window contents or typed text are read.

Run the headless logic checks with:

```sh
"$HOME/Library/Caches/LocalApps/Builds/Pomodoro.app/Contents/MacOS/Pomodoro" --selftest
```

`POMO_SELFTEST=1` remains supported. App artwork lives in `Resources/`. Historical app bundles and local preference exports are not included. Builds use current source and write to the cache directory; only the installed bundle should appear in Spotlight.
