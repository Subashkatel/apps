#!/usr/bin/env python3
"""Exercise the actual install transaction in disposable directories, with no real apps."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
for app in ('CodingAgentUsage', 'Frontier', 'Jot', 'PaperNotes', 'Pomodoro', 'VoiceBridge'):
    source = (root/app/'build.sh').read_text()
    start = source.index('STAGED=')
    ends = [source.find(marker, start) for marker in ('/System/Library/Frameworks/CoreServices', 'if [ "${NO_LAUNCH')]
    transaction = source[start:min(end for end in ends if end >= 0)]
    for mode in ('success', 'replacement-fails', 'rollback-fails'):
        with tempfile.TemporaryDirectory(prefix='install-check-') as temp:
            base = Path(temp)
            bundle = base/'built.app'; bundle.mkdir(); (bundle/'marker').write_text('new')
            destination = base/'applications'; destination.mkdir()
            original = destination/'Demo.app'; original.mkdir(); (original/'marker').write_text('original')
            commands = base/'commands'; commands.mkdir()
            for name in ('codesign', 'xattr'):
                executable = commands/name
                executable.write_text('#!/bin/sh\nexit 0\n'); executable.chmod(0o755)
            mover = commands/'mv'
            mover.write_text('''#!/bin/sh
case "$1" in
  */.local-app-install.*/Demo.app)
    [ "$TEST_MODE" = success ] || exit 1;;
  */.local-app-install.*/previous.app)
    [ "$TEST_MODE" != rollback-fails ] || exit 1;;
esac
exec /bin/mv "$@"
''')
            mover.chmod(0o755)
            env = {**os.environ, 'PATH': str(commands)+':/usr/bin:/bin', 'TEST_MODE': mode,
                   'TEST_SOURCE': str(bundle), 'TEST_INSTALL': str(destination)}
            script = 'set -euo pipefail\nAPP=Demo\nBUNDLE="$TEST_SOURCE"\nINSTALL_DIR="$TEST_INSTALL"\n'+transaction
            result = subprocess.run(['/bin/bash', '-c', script], env=env, capture_output=True, text=True)
            if mode == 'success':
                assert result.returncode == 0, result.stderr
                assert (original/'marker').read_text() == 'new'
            elif mode == 'replacement-fails':
                assert result.returncode != 0
                assert (original/'marker').read_text() == 'original'
            else:
                assert result.returncode != 0
                saved = list(destination.glob('.local-app-install.*/previous.app/marker'))
                assert len(saved) == 1 and saved[0].read_text() == 'original'
            print(f'PASS  {app}: {mode}')
