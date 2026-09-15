#!/usr/bin/env python3
"""Run local regression checks with temporary application data and bounded runtimes."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--gui', action='store_true', help='Also run Jot and Frontier UI/WebKit checks')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
apps = [('CodingAgentUsage', 'Coding Agent Usage'), ('PaperNotes', 'Paper Notes'), ('Pomodoro', 'Pomodoro'), ('VoiceBridge', 'VoiceBridge'), ('MeetingNotes', 'Meeting Notes')]
if args.gui:
    apps += [('Jot', 'Jot'), ('Frontier', 'Frontier')]
failures = []
with tempfile.TemporaryDirectory(prefix='local-app-tests-') as temp:
    scratch = Path(temp)
    config = scratch/'config.json'
    config.write_text('{}\n')
    env = {**os.environ, 'LOCAL_APPS_DATA_ROOT': str(scratch/'data'),
           'LOCAL_APPS_CONFIG': str(config), 'LOCAL_APPS_TESTING': '1',
           'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null', 'VOICEBRIDGE_CONFIG_DIR': str(scratch/'voice-config'),
           'POMODORO_WORK_APPS': str(scratch/'work-apps.txt')}
    # User environment must not select a live remote while testing a temporary library.
    env.pop('PAPER_NOTES_REMOTE', None)
    env.pop('PAPER_NOTES_TEST_PDFS', None)
    for directory in ('Jot/.trash', 'Paper Notes/papers', 'Frontier/concepts'):
        (scratch/'data'/directory).mkdir(parents=True, exist_ok=True)
    shared_command = ['swift', 'run', '--cache-path', str(scratch/'swift-cache')]
    if env.get('SWIFT_DISABLE_SANDBOX') == '1':
        shared_command.append('--disable-sandbox')
    shared_command.append('LocalSupportChecks')
    commands = [('Setup', [sys.executable, str(root/'tools/test-setup.py')], root),
                ('Publication guard', [sys.executable, str(root/'tools/check-publication.py'), '--self-test'], root),
                ('Installer', [sys.executable, str(root/'tools/test-installation.py')], root),
                ('Shared', shared_command, root/'Shared')]
    for app, bundle in apps:
        build_root = Path(os.environ.get('APP_BUILD_ROOT', str(Path.home()/'Library/Caches/LocalApps/Builds')))
        executable = build_root/f'{bundle}.app'/'Contents'/'MacOS'/app
        commands.append((app, [str(executable), '--self-test' if app == 'MeetingNotes' else '--selftest'], root))
    for name, command, cwd in commands:
        print(f'Checking {name}…', flush=True)
        try:
            result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, timeout=180)
            if result.returncode:
                failures.append(name)
                print(f'  FAILED (exit {result.returncode})')
                print('\n'.join(line for line in result.stdout.splitlines() if line.startswith(('FAIL', 'SKIP')) or 'FAILURE' in line))
                print(result.stdout[-1500:] + result.stderr[-3000:])
            else:
                passed = sum(line.startswith('PASS') for line in result.stdout.splitlines())
                print(f'  PASS' + (f' ({passed} checks)' if passed else ''))
        except (OSError, subprocess.TimeoutExpired) as error:
            failures.append(name)
            print(f'  FAILED: {error}')
print('Coding Agent Usage: mocked checks only; verify live account logins separately.')
if not args.gui:
    print('Jot and Frontier GUI tests skipped; use --gui in a desktop session.')
raise SystemExit(1 if failures else 0)
