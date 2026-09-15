#!/usr/bin/env python3
"""Exercise documented configuration with temporary, credential-free settings."""
import json
import os
from pathlib import Path
import tempfile
from unittest.mock import patch
import doctor

root = Path(__file__).resolve().parent.parent
example = json.loads((root / 'config.example.json').read_text())
with tempfile.TemporaryDirectory(prefix='local-app-setup-test-') as directory:
    config = Path(directory) / 'settings.json'
    config.write_text(json.dumps(example))
    with patch.dict(os.environ, {'LOCAL_APPS_CONFIG': str(config)}, clear=True):
        _, loaded = doctor.config()
        assert set(loaded) == set(doctor.CONFIG_KEYS)
        assert loaded['codexPath'] == loaded['antigravityPath'] == ''
    with patch.dict(os.environ, {'LOCAL_APPS_CONFIG': str(config), 'LOCAL_APPS_CODEX': '/tmp/example-codex'}, clear=True):
        assert doctor.config()[1]['codexPath'] == '/tmp/example-codex'
    for bad in ({'claudePath': 'relative/bin'}, {'unknownKey': ''}, {'dataRoot': 123}):
        config.write_text(json.dumps(bad))
        with patch.dict(os.environ, {'LOCAL_APPS_CONFIG': str(config)}, clear=True):
            try:
                doctor.config()
            except ValueError:
                pass
            else:
                raise AssertionError('Invalid configuration was accepted')
print('PASS example configuration, provider paths, environment precedence and invalid-input checks')
