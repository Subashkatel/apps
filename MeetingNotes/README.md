# Meeting Notes

A local macOS meeting recorder and notebook. Bear = in person (microphone); chicken = online meeting (microphone + all system audio). Click the menu-bar animal to start/stop. Its mouth follows the microphone's volume; the underline remains while recording is active, including silence.

## Setup

From the repository root:

```sh
brew install whisper-cpp                    # requires Homebrew
python3 tools/download-voice-model.py        # or configure your existing model
./build.sh MeetingNotes
./install.sh --launch MeetingNotes
```

Open Settings to verify the Whisper executable/model. Grant Microphone and, for calls, System Audio Recording when prompted. Select an AI provider and use Sign in for summaries, or configure your server. Recording and local transcription do not require an AI account. A stable signing identity is optional; see the [collection setup guide](../README.md#signing-and-permissions).

## Keyboard

- Control–Option–R: start / stop from any app.
- Control–Option–Command–S: stop only. Jot uses Control–Option–S, so this app leaves it alone.
- Control–Option–M: switch the next recording between in-person and online mode.
- Command–R / Command–S: start / stop while Meeting Notes is active.

Right-click the animal to change modes, open the notebook, or reach Settings. Mode changes during capture affect the next recording; the icon continues to describe the active capture. Global shortcut conflicts are reported, and global shortcuts can be disabled. No Accessibility grant is needed for these shortcuts.

## Recording and transcription

Grant Microphone permission for in-person meetings and System Audio Recording for online meetings. Recordings start without an AI connection or title/project form. Select a remembered default project in Settings, or file the meeting afterward.

Audio is streamed to PCM CAF files, with bounded write buffering and visible write/device errors. While recording, the app prevents idle system sleep. Deliberate sleep/lid closure or capture failure stops recording and retains captured audio. System capture uses the Core Audio tap approach adapted from [Quill](https://github.com/digimata/quill); its MIT license is included. Headphones are recommended for calls to avoid microphone echo; optional echo cancellation is available for speaker playback.

Transcription runs locally using `whisper-cli` and a local model. Existing Local Apps/VoiceBridge configuration is auto-detected; executable/model paths and language are editable. English-only models require English. A serial transcription queue lets another recording start while earlier work is transcribed. Click Listen to open the playback timeline; drag to seek, pause/resume, or skip 15 seconds. Long audio is converted in a stream and split into ten-minute chunks, with track offsets retained. Model errors never delete recordings; Retry is available.

## Summaries and tasks

**What we talked about** is an optional, editable topic list inside a collapsible section, above the separate **Detailed summary**. New AI drafts include both: brief bullets for scanning and natural paragraphs preserving the discussion's reasoning, context and nuances. The app remembers whether you leave the topic list expanded. Decided, Still open and Tasks keep their separate roles. Existing summaries remain intact; they are not automatically rewritten or sent to AI again. For an older note, use Add section to write topics yourself. Markdown exports preserve both sections.

AI settings shows the selected provider/model. For Antigravity, Refresh models loads its available model list; choose a model or keep the CLI default. Check connection sends only a small test phrase, not meeting content. Temporary capacity failures get one bounded retry; usage, login and invalid-model errors ask for the relevant action. A model or provider is never changed automatically.

Long summaries show section progress and save completed section drafts locally under the meeting's `Summary progress` folder. Retrying identical inputs reuses completed sections. Changes to the source, notes, context, tasks or settings start separate work; after a successful summary, an explicitly requested new draft starts fresh. These local checkpoints contain private meeting text and belong with app data, not the source repository.

“Summarize & find tasks” is explicit, with provider/model visible beside it. Review suggested actions, then save the note and selected tasks. Recording alone does not call the AI. A “Find tasks” action recovers suggestions for older notes without replacing their summaries. Claude, Codex, Gemini through Antigravity, and an OpenAI-compatible server use the existing LocalSupport adapters. Login occurs in Terminal. A custom server key is kept in Keychain, not in notes. This app has its own settings and does not change Frontier/Paper Notes settings.

The transcript, original notes, relevant open tasks and bounded prior project context are provided for summarization; the Project context disclosure lists included meetings and any omissions. Long transcripts are summarized in bounded sections, then combined; this uses multiple AI requests and remains subject to the selected provider’s limits. There is no automatic network summary request. The AI returns a structured draft; sources/IDs and dates are validated before task proposals are shown. Review those proposals before applying them. This checks referential validity, not whether an AI interpretation is correct—source timestamps let you listen and judge.

Stable task IDs, revision checks and a database transaction prevent duplicate retries and overwriting intervening task edits. Unfiled meetings keep their own tasks without requiring a project; they never modify another meeting’s or project’s tasks. All saved tasks appear in the Tasks list and remain visible in their source meeting. Ownership is not inferred merely from an audio track. Summaries preserve the original notes used for the request. Requested model names are recorded; a CLI default is explicitly labelled as not an exact reported model.

## Storage and recovery

Default data folder: `~/Library/Application Support/Meeting Notes`, respecting the collection's `LOCAL_APPS_DATA_ROOT`/`dataRoot` override.

- `meetings.sqlite` with WAL and full synchronous commits: meeting/project/task data.
- `Recordings/<UUID>/mic.caf` and optional `system.caf`: original audio.
- `meeting.json`: independent meeting recovery metadata.
- `transcript.json` and `transcript.txt`: independently saved timestamped transcription. Retries retain older results in `Transcript versions/`; each AI draft keeps the transcript snapshot supporting its citations.
- `my-notes.txt`, and after saving, `meeting-note.md`: portable note copies.
- `Backups/<date>.sqlite`: daily database snapshots made using SQLite's backup API, not a raw copy of a live WAL database.

Meeting deletion offers keeping its tasks or moving them to Trash together. Restore meetings and tasks from Recently deleted. Audio/transcripts are never automatically erased. Use Export for Markdown and Show files for the originals. PCM audio uses significant disk space (roughly 1 GB/hour for a 48 kHz mono mic plus stereo system track). Local copies cannot protect against losing the laptop/disk; include the data folder in your normal Mac backup.

## Build

Requires macOS 15+, a recent Swift/macOS SDK toolchain and the collection's `Shared` package. Ad-hoc signing is the default; an optional stable local identity helps permissions persist across updates. No network package dependencies are added.

```sh
./build.sh                         # build signed bundle in Library/Caches/LocalApps/Builds
INSTALL=1 NO_LAUNCH=0 ./build.sh    # install and open
swift run --disable-sandbox MeetingNotes --self-test
```

Use `SIGNING_IDENTITY`, `APP_BUILD_ROOT`, `INSTALL_DIR`, `MEETING_BUILD_PATH`, and `SWIFT_JOBS` to override build configuration. Stable signing preserves macOS permission identity across updates. The installer will not kill an active recording; quit the app before replacing it.

See [TASKS.md](TASKS.md) for tested areas and remaining hardware/provider checks. Tests use synthetic fixtures and isolated temporary data. Passing them does not establish compatibility with every microphone, call app or AI account.

### Meeting and task editing

The Project picker beneath a meeting's title remains available after summarization. Choose **New project…** there to create and file a project in one action. Filing an unfiled meeting also files its unfiled tasks; tasks already assigned to another project keep that assignment and can be changed individually. Projects list their meetings as well as tasks.

Use **Add task** in a meeting, project or the global Tasks view. Click a saved task's title to edit its action, owner, project, optional due date and optional local time. Tasks retain their source meeting, added/edited timestamps and change history. Completion is manual. AI task proposals still require review and saving; their dates/times must be supported by the transcript.

**My notes** supports Markdown: select text and use bold/italic, or insert headings, bullets and checklists. **Preview** renders the formatting; **Edit** returns to writing. Notes save as you type and retain Markdown in exports. Decided contains agreements/conclusions; Still open contains unresolved questions. Empty sections are hidden, with Add section available if you want to write one yourself.

New summaries request a concise topic title. Automatically named meetings adopt it, with the recording date and time below. A title you edit yourself is preserved, including if you edit while summarization is in progress. Existing saved meetings are not automatically sent back to AI.

### Task overview, references and project context

**Tasks** in the sidebar is the central list across projects and meetings. Search title/owner, filter by project, meeting, status and deadline (today, overdue, undated), sort by due date/newest/title, and group by project, meeting or due date. The default shows open tasks with dated work first. Completed tasks remain under the Status filter.

**Attach files…** copies PDFs, text notes and other regular files into that meeting's Attachments folder. Click a filename to open it with its macOS application. The original can move without breaking the saved copy. Removing the reference keeps its file in the saved folder. Attachment contents are not automatically included in AI requests.

Summarization uses the current transcript and notes, current open project tasks, and prior project meetings' saved summaries, decisions, open questions and personal notes. The old three-meeting cutoff is removed. A bounded 80 KB history budget prioritizes recent entries; Project context discloses included meetings and excluded counts. Full older transcripts and attachment contents are not read. Historical context guides continuity, but each task proposal still needs evidence in the current meeting and your approval before updating tasks. This is context-assisted drafting, not guaranteed exhaustive project reasoning.

The bear app icon appears in the window header and Dock while the notebook is open. Closing/hiding the window leaves the recorder running in the menu bar. Control–Option–R toggles recording, Control–Option–Command–S stops, and Control–Option–M switches the next recording's mode. Summarization remains an explicit button press; automatic transcription follows recording when enabled. Quitting the app stops its shortcuts. Enable **Open Meeting Notes at login** in Settings if desired.


### Deleting meetings and tasks

Choose **Delete task** from a task's three-dot menu or editor. It disappears from all active task views and remains recoverable under the window menu → **Recently deleted…**.

Deleting a meeting now asks whether to delete its source tasks with it or keep them. Kept tasks show **Source meeting in Trash** and cannot reopen it. Restore the meeting explicitly from Recently deleted to read it again. Restoring a meeting also restores tasks deleted together with it; tasks independently deleted before or afterward remain in Trash. Project tasks whose source is another meeting are left alone. Meetings deleted in older versions are not retroactively cascaded; their remaining tasks can now be deleted individually.

Before summarizing an unassigned meeting, choose **Standalone meeting**, an existing project, or **New project**. The choice is remembered and can be changed using the meeting’s Project menu. A standalone meeting does not need a project and only uses its own existing tasks. Project pages include editable **Project notes** for purpose, goals, and background; these notes inform future summaries, but do not count as evidence for new commitments.

If the AI proposes a missing or repeated task update, the detailed summary and valid task suggestions remain available. The affected suggestions appear under **Task suggestions need checking**, with their reason and available source passages. They cannot modify tasks; review the transcript and add a task manually if appropriate. Full AI responses are retained locally in the meeting’s `Summary progress/Responses` folder before validation. Long-summary retries retain completed sections. These private files are application data, not repository content.

### Discuss a meeting

**Discuss** beside the meeting title opens an optional right-hand panel. The existing summary, transcript and **My notes** remain available. The left sidebar uses the same toggle and layout whether Discuss is open or closed. The window widens if needed to keep all three columns readable; you can collapse the sidebar yourself. Opening the transcript uses the reading area beside the discussion. Close the transcript to return to the summary.

Choose a provider/model and **reasoning effort** at the top of Discuss. These choices belong to that conversation and apply to its next answer; previous answers retain their original selection label. Claude, Codex and Antigravity use your installed, signed-in CLIs. Antigravity's Refresh button queries its model catalog; Codex choices come from its local model cache. You can also enter an exact model ID. `CLI default` means no exact model was selected, not a claim about which model the provider resolved. Custom servers use the endpoint/key configured in AI settings and their own default reasoning behavior.

**This meeting** uses the meeting's transcript, notes, summary and tasks. **Whole project** also considers project notes and other active project meetings/tasks. Long contexts select relevant passages within a bounded budget; each answer's **Context used** discloses the coverage. Attachments and raw audio are not read directly. Changing scope starts a fresh discussion and keeps the previous conversation and its unsent draft in **History**. If an old conversation refers to a removed meeting or a changed project, start a fresh one instead of silently reusing that old context.

**Send** (Return or Command–Return; Option–Return adds a new line) saves your question before requesting an answer. **Stop** cancels that request; **Retry answer** retries a stopped/failed question without duplicating it. Closing Discuss does not cancel a request. Completed answers and unsent drafts are stored locally in the existing SQLite database and survive relaunch; interrupted requests are marked stopped on reopening. Replies currently appear when complete rather than streaming token by token. No background AI requests run while idle.

Click a numbered citation or an item under **Sources** to jump directly to its meeting, transcript passage, or project. Grouped references become separate numbered links. If an original passage has changed or was deleted, the saved excerpt opens instead, so the evidence remains readable. Reference validation checks that the cited passage exists, not that the AI's interpretation is correct. Unknown references are explicitly marked unverified.

**Save to My notes…** opens an editable Markdown preview. Saving appends your reviewed text to the originating meeting's personal notes and prevents accidental repeat saving of the same answer. It never automatically rewrites the summary or updates tasks.

Developer checks: `MeetingNotes --discussion-check` runs isolated persistence, context, cancellation, retry and note-saving tests. `MeetingNotes --discussion-ai-check claude` (or `codex` / `gemini`) sends a small synthetic two-turn meeting to that provider and verifies returned source IDs. Live checks require login and consume a small amount of account usage; they do not load personal meetings.

AI settings and Discuss use the same model dropdown for Claude, Codex and Antigravity. Manual model IDs are available under a disclosure rather than being the main control. A saved ID absent from the list is labeled custom; choosing a listed model replaces it. Summary settings and each discussion retain independent selections.

### Add a meeting or task to a calendar

Choose **Add to calendar…** from a meeting's or task's **…** menu (or right-click a meeting in the sidebar). Review the title and dates, choose Apple Calendar or Google Calendar, and add the event. Google opens a draft for you to save; Apple may import immediately into its default calendar or ask you to choose a calendar. A task without a valid due date asks you to choose one first. Date-only tasks start as all-day events; timed tasks start with an editable 30-minute block. Meetings use their recorded start and end times, which you can change to schedule a follow-up.

This creates a calendar copy, not a live sync or a Google Task. Changing or completing the task in Meeting Notes does not update that copy. Event details include only the project name by default; you can edit them before opening the calendar. Recordings, transcripts and meeting notes are not attached. **Export .ics…** is available for other calendars or if opening an app fails. Google uses its [documented prefilled-event link](https://developers.google.com/workspace/calendar/api/concepts/inviting-attendees-to-events); Apple uses [calendar-file import](https://support.apple.com/guide/calendar/icl1023/mac). Meeting Notes does not need access to read your calendar or run a background calendar service.

Task and project lists use compact search and filter controls. **View** contains sorting and grouping; **Clear filters** resets search, project, meeting, status and due-date filters while retaining your view arrangement.

To quit completely, right-click (or Control-click) the bear/chicken menu-bar icon and choose **Quit Meeting Notes**, or open the notebook and press **⌘Q**. Closing the window with the red button hides it while recording and global shortcuts remain available. Quit prompts before stopping an active recording, unfinished processing or unsaved work.

UI test bundles with identifiers under `local.meetingnotes.*` always open an isolated synthetic notebook, even when launched without test arguments. They do not register global shortcuts or add recording icons to the menu bar. Retire test bundles after checking them; the everyday app is `/Applications/Meeting Notes.app`.
