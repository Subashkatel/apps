# Data and publication boundaries

This repository contains application source, documentation, synthetic test fixtures, bundled rendering libraries and app artwork. It is not an app-data backup. A new installation creates its own library; it does not inherit another user's meetings, notes, account profiles, settings or credentials.

## Keep outside Git

The default runtime root is `~/Library/Application Support`. Each app stores its data in a separate subfolder. Configuration lives in `~/.config/local-apps/config.json` and app-specific configuration directories. Provider CLIs and macOS Keychain manage credentials.

Do not set `dataRoot`, provider profile paths, speech models or a Paper Notes library inside this source checkout. Recordings, transcriptions, attachments, reading libraries, notes, usage identities, private test output and backups belong outside it. `.gitignore` excludes common forms of these files, but ignore rules do not remove files already tracked by Git.

Paper Notes can sync its own notes library to a remote you explicitly configure. That is separate from publishing this source repository. Check the target remote before enabling note sync.

## Network behavior

- VoiceBridge and Meeting Notes transcribe locally using whisper.cpp after a separate model download.
- Coding Agent Usage contacts Claude/Codex usage services using the selected local account.
- Frontier downloads source documents/pages when you import URLs or request external sources. Generating explanations/lessons sends the relevant material and context to your chosen AI.
- Paper Notes retrieves paper metadata/recommendations and sends selected review/document context when you request AI features. Remote Git sync is optional.
- Meeting Notes sends the current transcript, notes, task context and bounded earlier project notes when you press Summarize. Recording alone does not trigger that request. Attachment contents are not included automatically.
- A custom AI endpoint receives the text submitted to it. Configure a local endpoint if local processing is required.

Publishing source does not upload the application's data folders or Keychain. Using an online feature later has the data flow described above.

## Before publishing

```sh
git status --short
git diff --stat
python3 tools/check-publication.py       # check tracked and untracked source candidates
# Stage only the intended source/documentation changes.
python3 tools/check-publication.py --staged
git diff --cached --stat
```

The checker flags runtime-data filenames, suspicious binaries, private home paths and common credential formats without printing matched secret values. It is a guardrail, not proof that arbitrary prose or images contain no private information. Review documentation, screenshots and fixtures manually too. Check new commits and their metadata; use a GitHub noreply email if you do not want a personal email in commit history.

Existing public Git history is not erased by removing a file in a later commit. If credentials were ever published, revoke them and assess history cleanup separately.
