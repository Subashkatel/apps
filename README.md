# macOS apps

Seven small native macOS utilities. Their online integrations remain available. Build only the apps you want. Personal libraries, recordings and credentials live outside this source checkout.

| App | What it does | Additional setup |
| --- | --- | --- |
| [Coding Agent Usage](CodingAgentUsage/README.md) | Menu bar icon opens usage for multiple Claude and Codex accounts | Local logins detected automatically; add, rename, reorder accounts and save renewal/end dates |
| [Frontier](Frontier/README.md) | Book/paper library, document reading, notes, prerequisite graph and AI lessons | Claude, Codex, Antigravity CLI, or a custom Chat Completions server |
| [Jot](Jot/README.md) | Markdown sticky notes with math rendering | None |
| [Meeting Notes](MeetingNotes/README.md) | Menu-bar meeting recording, local transcripts, editable summaries and project tasks | macOS 15+, microphone/system audio permission, local Whisper; AI provider for summaries |
| [Paper Notes](PaperNotes/README.md) | PDF reading notes, citation graph, recommendations and AI grading | Selected AI provider for AI features; optional personal Git remote |
| [Pomodoro](Pomodoro/README.md) | Focus timer, breaks and session history | Optional work-app list |
| [VoiceBridge](VoiceBridge/README.md) | Local speech recognition and dictation into the focused app or iTerm2 | whisper.cpp, a model, microphone and Accessibility permissions |

## Requirements

- macOS 14 or newer for six apps; **Meeting Notes requires macOS 15 or newer**. Use macOS 15+ to run the full collection.
- A recent Swift 6 toolchain and macOS SDK from Command Line Tools (`xcode-select --install`) or Xcode. Packages use Swift 5 language mode; validation used Swift 6.3. Full Xcode is not required.
- Python 3 for the setup report, model downloader and test runner.
- Git for cloning and Paper Notes version history.

The apps use Swift Package Manager in Swift 5 language mode. `Shared/` contains the local configuration and file-writing helpers. Keep the whole checkout together when building an app.

## Get started

```sh
git clone https://github.com/Subashkatel/apps.git
cd apps
python3 tools/doctor.py
./build.sh                         # build all seven; no installation or launch
./build.sh Jot Pomodoro             # or build selected apps
```

Bundles are created in `~/Library/Caches/LocalApps/Builds`, outside synced source folders. Set `APP_BUILD_ROOT` to use a different absolute path. This avoids cloud file-provider metadata invalidating app signatures. Compilation does not require signing in to a service or downloading a speech model.

When ready to install:

```sh
./install.sh                       # install all seven; do not launch
./install.sh Jot Pomodoro           # install selected apps
./install.sh --launch Jot            # install and launch explicitly
INSTALL_DIR="$HOME/Applications" ./install.sh
```

The default destination is `/Applications`. Installation replaces only the selected app bundles, with the previous bundle retained until the replacement is in place. App data is stored separately. Each app's own `build.sh` also builds only; `INSTALL=1` enables installation and `NO_LAUNCH=0` enables launching.

Jot, Coding Agent Usage and Pomodoro appear in the menu bar. VoiceBridge has no Dock or menu bar icon; its hotkey and command-line status are described in its README.

## First launch

1. Install selected apps, then open them from Applications or use `--launch` above. Builds do not bundle your provider accounts or personal data.
2. For **Coding Agent Usage**, install and sign in to the Claude/Codex CLI accounts you want to track. For **Frontier**, **Paper Notes** and **Meeting Notes**, choose a provider in AI settings. CLI login is managed by the provider; use the app's Sign in action when available.
3. For **VoiceBridge** and **Meeting Notes**, install [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (`brew install whisper-cpp` if using Homebrew), then run `python3 tools/download-voice-model.py`, or configure an existing model. Grant the permissions listed in each app's README.
4. Jot and Pomodoro need no AI account. Customize hotkeys/work-app detection as described in their guides.

Provider setup: [Claude Code](https://code.claude.com/docs/en/setup), [Codex CLI](https://developers.openai.com/codex/cli/), [Antigravity CLI](https://antigravity.google/docs/cli/install/). Install only the providers you intend to use. A subscription's eligibility and limits are determined by its provider; the apps do not include subscriptions. Custom servers use Chat Completions-compatible endpoints and keep API keys in Keychain.

**Troubleshooting:** if a CLI is not found from Finder, set its absolute path in configuration or AI settings. If recording fails, check Microphone/System Audio Recording permissions; VoiceBridge also needs Accessibility. If a provider rejects a request, verify its CLI login/model first. Missing speech models affect transcription, not installation.

## Configuration

Defaults work for standard installations. To customize paths, copy the example once and edit it:

```sh
mkdir -p ~/.config/local-apps
cp -n config.example.json ~/.config/local-apps/config.json
```

Use absolute paths or `~/…`. Empty values use automatic discovery or the documented default. `LOCAL_APPS_CONFIG` selects another JSON file. Environment variables override JSON settings; GUI apps launched from Finder normally use the JSON file, not your terminal environment. Restart an app after changing paths.

| JSON key | Environment override | Default / purpose |
| --- | --- | --- |
| `dataRoot` | `LOCAL_APPS_DATA_ROOT` | `~/Library/Application Support`; each app gets its own subfolder |
| `claudePath` | `LOCAL_APPS_CLAUDE` | Find `claude` on PATH or common macOS installation paths |
| `antigravityPath` | `LOCAL_APPS_ANTIGRAVITY` | Find `agy` on PATH or common macOS installation paths |
| `codexPath` | `LOCAL_APPS_CODEX` | Find `codex` on PATH or common macOS installation paths |
| `codexAuthFile` | `CODEX_AUTH_FILE` | `$CODEX_HOME/auth.json`, or `~/.codex/auth.json` |
| `paperNotesRemote` | `PAPER_NOTES_REMOTE` | Empty; set your own notes repository URL when needed |
| `whisperCLI` | `WHISPER_CLI` | Find `whisper-cli` on PATH or common macOS installation paths |
| `whisperModel` | `WHISPER_MODEL` | `<dataRoot>/VoiceBridge/ggml-small.en.bin` |
| `voiceConfigDirectory` | `VOICEBRIDGE_CONFIG_DIR` | `~/.config/voicebridge` |
| `frontierReaderProfile` | `FRONTIER_READER_PROFILE` | Optional text file describing your learning background |
| `frontierCoursesFile` | `FRONTIER_COURSES_FILE` | Optional JSON course list; otherwise bundled reference courses |
| `pomodoroWorkAppsFile` | `POMODORO_WORK_APPS` | `~/.config/pomodoro/work-apps.txt` |

`python3 tools/doctor.py` checks configuration and reports missing prerequisites without reading credentials or contacting providers. Do not put access tokens in the configuration file. Credentials continue to be managed by the provider CLIs and macOS Keychain.

Changing `dataRoot` selects a different library; it does not move existing files. Quit the apps and copy the relevant folders yourself if migrating. Existing vocabulary, followed authors, preferences and Git remotes are preserved. Fresh installations contain no personal notes or curriculum from the original developer.

## Data and integrations

- Jot, Frontier, Paper Notes, Meeting Notes, Pomodoro and VoiceBridge store data under their named folders in the configured data root. Paper Notes uses the folder name `Paper Notes`.
- Paper Notes keeps markdown history with Git and excludes stored PDFs from Git. It adds an `origin` only when you provide a remote; an existing `origin` is preserved. Enable pushing in the app when you want sync.
- Coding Agent Usage queries Claude and Codex usage endpoints using their existing credentials. Paper Notes uses paper metadata/recommendation services and its selected provider for AI features. Frontier fetches course material and uses the AI provider selected in its settings. Local documents can be added for reading without AI. These features are retained.
- VoiceBridge transcribes locally with whisper.cpp, then sends text to the selected destination. Configuration files contain your own vocabulary and corrections; they start empty.

Back up the data folders separately from this source repository. Build output, models and local configuration should not be committed. See [PRIVACY.md](PRIVACY.md) for data flows and publication checks, and [third-party notices](ThirdParty/README.md) for bundled component licenses.

## Signing and permissions

Builds use ad-hoc signing unless `SIGNING_IDENTITY` names an installed signing identity. For a stable local identity that preserves VoiceBridge permission grants across rebuilds:

```sh
SIGNING_IDENTITY="Local Apps Development" ./VoiceBridge/Tools/make-signing-identity.sh
SIGNING_IDENTITY="Local Apps Development" ./build.sh VoiceBridge
```

The identity helper creates a local code-signing certificate in your login Keychain; it does not add certificate trust settings. No identity is created by a normal build. VoiceBridge's README explains its one-time permissions and model setup.

## Verification and current limitations

```sh
python3 tools/test.py                # storage/configuration, installer and headless app checks
python3 tools/test.py --gui          # also Jot and Frontier tests; requires a desktop session
```

Build bundles before running app checks. The test runner creates temporary data directories and applies timeouts. Coding Agent Usage checks use synthetic credentials and mocked requests; a successful build or self-test does not verify live provider authentication.

Known limitations are recorded in [HANDOFF.md](HANDOFF.md), including Jot's undo grouping and Frontier's scheduling limitations. Frontier's updated reader has passed native-window rendering, resizing, fallback and recovery checks.

`sync.sh /path/to/another/checkout` is an optional, non-destructive preview of source imports. Add `--apply` to copy changes. It never assumes a particular home directory or deletes destination-only files.
