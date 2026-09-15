# VoiceBridge

Double-tap Control to start recording; double-tap again to transcribe. Speech recognition runs locally with whisper.cpp. Text is delivered to the focused app by default, with an optional iTerm2 target.

## Setup

From the repository root:

```sh
brew install whisper-cpp
python3 tools/download-voice-model.py
./build.sh VoiceBridge
./install.sh VoiceBridge
```

The download is roughly 465 MB. It is a separate step from building; a partial download is not installed, and an existing model is left unchanged. Set `whisperModel` to use an existing compatible model or `whisperCLI` for a custom whisper.cpp executable. The default model path is `<dataRoot>/VoiceBridge/ggml-small.en.bin`.

For stable permissions across rebuilds, configure a signing identity as described in the [root README](../README.md#signing-and-permissions). Then launch the app and grant **Accessibility** and **Microphone** permissions. The iTerm2 target additionally needs Automation permission. Avoid assigning the built-in macOS Dictation shortcut to the same double-tap Control combination.

## Your vocabulary

Files in `~/.config/voicebridge`, or your configured `voiceConfigDirectory`, are reread for each transcription:

- `vocabulary.txt`: names and terms the recognizer gets wrong. Keep it short; the prompt has a limited token budget.
- `replacements.txt`: literal corrections, one per line, in the form `wrong => right`.

Fresh files contain instructions only, with no personal cluster names or corrections from another developer. Existing files are preserved.

## Commands

Use the installed executable or `~/Library/Caches/LocalApps/Builds/VoiceBridge.app/Contents/MacOS/VoiceBridge`:

```sh
/Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --status
/Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --selftest
/Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --transcribe /path/to/clip.wav
/Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --target focused
/Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --target iterm
/Applications/VoiceBridge.app/Contents/MacOS/VoiceBridge --enable-login-item
```

There is no menu bar or Dock icon. `--status` reports the GUI's last known permission/hotkey status. The self-test checks hotkey logic; it does not verify microphone capture or recognition accuracy. Delivery failures retain the transcript on the clipboard. Text sent into another app follows that app's normal behavior.
