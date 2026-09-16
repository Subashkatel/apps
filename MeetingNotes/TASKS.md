# Meeting Notes development checklist

## Implemented and regression tested

- [x] Menu-bar recording, microphone/system modes, global shortcuts and audio-level animation.
- [x] Streaming audio retention, interruption recovery, local chunked transcription and playback seeking.
- [x] Editable AI drafts with provenance, source evidence and explicit task review.
- [x] Personal Markdown notes, project filing, local copied attachments and bounded project context.
- [x] Compact task search/filter controls with sorting, grouping, optional deadlines, revision-safe edits and history.
- [x] Recoverable task/meeting deletion; blocked links to trashed meetings; explicit task cascade choice.
- [x] Dock presence while the notebook is open; background recording remains available after closing it.
- [x] Separate collapsible topic overview and detailed summary, legacy draft loading, and exports retaining both.
- [x] Shared provider/model dropdown in summary settings and discussion, optional custom model IDs and explicit connection checks.
- [x] Classified Antigravity failures and bounded transient retry without silently changing providers or models.
- [x] Long-summary checkpoints and resume, visible progress, and settings/retry recovery controls.
- [x] Recording animation timer disabled while idle; reduced monitoring frequency when animation is disabled.
- [x] Preserve detailed summaries when task proposals reference missing/repeated tasks; retain excluded proposals for review without applying them.
- [x] Project-or-standalone choice before summarization; project background notes inform future summaries.
- [x] Retain raw AI responses locally before validation and preserve review suggestions through long-summary merging and exports.
- [x] Reviewed calendar copies for meetings/tasks via Apple Calendar, Google Calendar or .ics export; no automatic sync.
- [x] Calendar date validation, all-day/DST/time-zone handling, URL encoding and iCalendar escaping/folding.
- [x] Isolated persistence, migration, stale-edit, recovery, task/context/attachment and native UI checks.
- [x] Preview bundle identities force synthetic data without relying on launch arguments; previews omit menu-bar icons and global shortcuts.

## AI discussion

- [x] Optional closable right panel; existing summary, transcript and My notes retained.
- [x] Durable local history and unsent drafts; restart recovery for interrupted requests.
- [x] Per-conversation model and reasoning effort selection, with previous reply provenance retained.
- [x] Synthetic Claude, Codex and Antigravity live two-turn checks with explicit model/effort and verified references.
- [x] Bounded context coverage, project context, source snapshots and a fresh thread when changing scope.
- [x] Stop/retry and editable note append with duplicate prevention.
- [x] Return sends; Option–Return inserts a newline.
- [x] Numbered grouped citation links navigate directly; changed/deleted originals retain a readable snapshot fallback.
- [x] Consistent sidebar visibility when discussion opens/closes and native narrow/wide layout checks.
- [x] Synthetic persistence/recovery/context tests and note/task regression tests.

## Further validation and deferred work

- [ ] Continuous one- and two-hour live recordings with device changes.
- [ ] Echo-cancellation behavior across speakers, headsets and call applications.
- [ ] Live provider compatibility and a custom endpoint across supported configurations.
- [ ] Shortcut collisions and permission recovery across supported macOS versions.
- [ ] Broader long-meeting validation after task-proposal recovery changes.
- [ ] Token-streamed partial discussion answers; current replies appear on completion.
- [ ] Full Google Calendar editor verification beyond event-link launch.

Keep personal meeting/task content, AI response checkpoints, calendar exports and machine-specific test logs outside the source repository. Use synthetic fixtures for development and retire test app bundles after checking them.
