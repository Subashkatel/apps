#!/usr/bin/env python3
"""Read-only setup report. Never prints credentials or calls provider endpoints."""
import json
import os
from pathlib import Path
import shutil
import sys

CONFIG_KEYS = {
    'dataRoot': 'LOCAL_APPS_DATA_ROOT', 'claudePath': 'LOCAL_APPS_CLAUDE',
    'codexPath': 'LOCAL_APPS_CODEX', 'antigravityPath': 'LOCAL_APPS_ANTIGRAVITY',
    'codexAuthFile': 'CODEX_AUTH_FILE', 'paperNotesRemote': 'PAPER_NOTES_REMOTE',
    'whisperCLI': 'WHISPER_CLI', 'whisperModel': 'WHISPER_MODEL',
    'voiceConfigDirectory': 'VOICEBRIDGE_CONFIG_DIR',
    'frontierReaderProfile': 'FRONTIER_READER_PROFILE',
    'frontierCoursesFile': 'FRONTIER_COURSES_FILE',
    'pomodoroWorkAppsFile': 'POMODORO_WORK_APPS',
}

def config():
    path = Path(os.environ.get('LOCAL_APPS_CONFIG', '~/.config/local-apps/config.json')).expanduser()
    values = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(values, dict):
        raise ValueError('Configuration must be a JSON object')
    for key, value in values.items():
        if key not in CONFIG_KEYS:
            raise ValueError(f'Unknown configuration key: {key}')
        if not isinstance(value, str):
            raise ValueError(f'{key} must be a string')
    for key, env in CONFIG_KEYS.items():
        value = os.environ.get(env) or values.get(key, '')
        if value and key != 'paperNotesRemote':
            value = os.path.expanduser(value)
            if not os.path.isabs(value):
                raise ValueError(f'{key} must be an absolute path or start with ~/')
        values[key] = value
    return path, values

def executable(override, name):
    if override:
        return override if os.access(override, os.X_OK) else None
    candidates = [shutil.which(name)] + [str(Path(p).expanduser() / name)
        for p in ('~/.local/bin', '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin')]
    return next((p for p in candidates if p and os.access(p, os.X_OK)), None)

def main():
    try:
        path, settings = config()
    except (ValueError, OSError) as error:
        print(f'Configuration error: {error}', file=sys.stderr)
        return 1
    print(f'Configuration: {path}' + (' (defaults; file absent)' if not path.exists() else ''))
    print('Platform:', sys.platform)
    print('Swift:', shutil.which('swift') or 'MISSING — install macOS Command Line Tools')
    print('Git:', shutil.which('git') or 'MISSING')
    print('Claude CLI:', executable(settings['claudePath'], 'claude') or 'MISSING — AI features need it')
    print('Codex CLI:', executable(settings['codexPath'], 'codex') or 'not installed (optional)')
    print('Antigravity CLI:', executable(settings['antigravityPath'], 'agy') or 'not installed (optional)')
    auth = Path(settings['codexAuthFile'] or str(Path(os.environ.get('CODEX_HOME', str(Path.home()/'.codex'))) / 'auth.json'))
    print('Codex credential file:', 'present (contents not read)' if auth.is_file() else 'absent')
    print('Whisper CLI:', executable(settings['whisperCLI'], 'whisper-cli') or 'MISSING — VoiceBridge and Meeting Notes need whisper-cpp')
    data_root = Path(settings['dataRoot'] or Path.home()/'Library/Application Support')
    model = Path(settings['whisperModel'] or data_root/'VoiceBridge/ggml-small.en.bin')
    print('Whisper model:', str(model), '(present)' if model.is_file() else '(not downloaded)')
    print('Data root:', data_root)
    print('Paper Notes remote:', 'configured (existing origin takes precedence)' if settings['paperNotesRemote'] else 'no default remote; configure your own when needed')
    if sys.platform != 'darwin':
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
