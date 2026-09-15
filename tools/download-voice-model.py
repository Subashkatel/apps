#!/usr/bin/env python3
"""Download the standard whisper.cpp model atomically; existing models are preserved."""
from pathlib import Path
import os
import subprocess
import tempfile
from doctor import config

_, settings = config()
data_root = Path(settings['dataRoot'] or Path.home()/'Library/Application Support')
target = Path(settings['whisperModel'] or data_root/'VoiceBridge/ggml-small.en.bin')
if target.exists():
    raise SystemExit(f'Already exists, left unchanged: {target}')
target.parent.mkdir(parents=True, exist_ok=True)
url = os.environ.get('WHISPER_MODEL_URL', 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin')
if not url.startswith('https://'):
    raise SystemExit('WHISPER_MODEL_URL must use HTTPS')
fd, tmp = tempfile.mkstemp(prefix='.model-', suffix='.download', dir=target.parent)
os.close(fd)
try:
    subprocess.run(['curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
                    '--retry', '3', '--output', tmp, url], check=True)
    if Path(tmp).stat().st_size < 1_000_000:
        raise SystemExit('Download is too small to be a Whisper model; nothing installed')
    # Linking is exclusive, so a concurrent download cannot overwrite an existing model.
    os.link(tmp, target)
    print(f'Model saved to {target}')
finally:
    Path(tmp).unlink(missing_ok=True)
