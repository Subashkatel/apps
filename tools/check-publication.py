#!/usr/bin/env python3
"""Scan the source candidate set or Git index without printing secret values."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

RUNTIME_NAMES = {'auth.json', '.credentials.json', 'ai-settings.json', 'claude-accounts.json',
                 'runtime.json', 'sessions.jsonl', 'transcript.json', 'transcript.txt',
                 'meeting.json', 'my-notes.txt', 'meeting-note.md', 'config.local.json'}
PRIVATE_PARTS = {'.private', '.local', '.build', 'build', 'build.noindex', 'Recordings',
                 'Backups', 'ClaudeProfiles', 'CodexProfiles', 'reference'}
BINARY_ASSETS = {'.png', '.icns', '.woff2'}
FORBIDDEN_SUFFIXES = {'.sqlite', '.db', '.caf', '.wav', '.m4a', '.mp3', '.mp4', '.pdf',
                      '.epub', '.zip', '.dmg', '.pkg', '.pem', '.key', '.p12', '.pfx', '.log'}
PATTERNS = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'GitHub token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b',
    'provider secret': rb'\bsk-(?:ant-|proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b',
    'AWS access key': rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'literal home directory': rb'/Users/[A-Za-z][A-Za-z0-9_.-]+/',
    'JWT-shaped token': rb'\beyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b',
}

def findings(name, data):
    path = Path(name)
    result = []
    if (path.name in RUNTIME_NAMES or any(part in PRIVATE_PARTS or part.endswith('.app') for part in path.parts)
            or path.suffix.lower() in FORBIDDEN_SUFFIXES or '.sqlite' in path.name
            or path.name == '.env' or (path.name.startswith('.env.') and path.name != '.env.example')):
        result.append('runtime data, private material or build artifact')
    if len(data) > 10_000_000:
        result.append('file exceeds source-review size limit')
    for label, pattern in PATTERNS.items():
        if re.search(pattern, data):
            result.append(label)
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        if path.suffix.lower() not in BINARY_ASSETS:
            result.append('unreviewed binary type')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true', help='Read the exact Git index contents')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        assert findings('copy/auth.json', b'{}')
        assert findings('source.txt', ('ghp_' + 'a' * 40).encode())
        assert findings('source.txt', ('/Users/' + 'person' + '/notes').encode())
        assert not findings('config.example.json', b'{"claudePath":""}')
        assert not findings('Sources/Test.swift', b'let token = "synthetic-token"')
        print('PASS publication guard detects data paths and secret-shaped content')
        return 0
    root = Path(__file__).resolve().parent.parent
    command = ['git', 'ls-files', '-z', '--cached']
    if not args.staged:
        command += ['--others', '--exclude-standard']
    names = sorted(set(subprocess.check_output(command, cwd=root).decode().strip('\0').split('\0')) - {''})
    problems, scanned = [], 0
    for name in names:
        if args.staged:
            data = subprocess.check_output(['git', 'show', ':' + name], cwd=root)
        else:
            path = root / name
            if not path.exists():
                continue
            if path.is_symlink():
                problems.append((name, ['symlink requires manual review']))
                continue
            data = path.read_bytes()
        scanned += 1
        reasons = findings(name, data)
        if reasons:
            problems.append((name, reasons))
    for name, reasons in problems:
        print(f'REVIEW {name}: {", ".join(reasons)}')
    print(f'{"FAIL" if problems else "PASS"}: scanned {scanned} {"staged" if args.staged else "candidate"} files; {len(problems)} flagged files. No matched values printed.')
    return int(bool(problems))

if __name__ == '__main__':
    sys.exit(main())
