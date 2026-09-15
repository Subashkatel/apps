# Meeting Notes development checklist

## Implemented and regression tested

- [x] Menu-bar recording, microphone/system modes, global shortcuts and audio-level animation.
- [x] Streaming audio retention, interruption recovery, local chunked transcription and playback seeking.
- [x] Editable AI drafts with provenance, source evidence and explicit task review.
- [x] Personal Markdown notes, project filing, local copied attachments and bounded project context.
- [x] Central task search/filter/sort/group, optional deadlines, revision-safe edits and history.
- [x] Recoverable task/meeting deletion; blocked links to trashed meetings; explicit task cascade choice.
- [x] Dock presence while the notebook is open; background recording remains available after closing it.
- [x] Isolated persistence, migration, stale-edit, recovery, task/context/attachment and native UI checks.

## Further validation

- [ ] Continuous one- and two-hour live recordings with device changes.
- [ ] Echo-cancellation behavior across speakers, headsets and call applications.
- [ ] Live provider compatibility and a custom endpoint on the target user's accounts.
- [ ] Shortcut collisions and permission recovery across supported macOS versions.

Keep personal meeting/task content and machine-specific test logs outside the source repository.
