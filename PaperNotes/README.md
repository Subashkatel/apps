# Paper Notes

PDF reading notes with a citation graph, reading queue, metadata, recommendations, AI appraisal and note grading.

Build: `./build.sh PaperNotes` from the repository root. Install: `./install.sh PaperNotes`.

Add a PDF through Finder's Open With menu, the app's add dialog, or drag and drop. The original PDF opens in your reader; notes remain editable markdown. The app extracts references locally and retrieves metadata from arXiv, OpenAlex and Semantic Scholar. AI features use the provider selected in **AI settings**.

## Reviewing a paper

The app opens in dark mode with **Preview** selected. Choose **Write** to edit Markdown, or **Split** to see writing and formatted text together. The menu's **Dark appearance** toggle also allows light mode. Your verdict and star stay separate from the AI's appraisal.

**Prompts & review tools** holds optional headings for claims, evidence, assumptions, understanding, gaps and connections, plus the AI appraisal and note grading controls. Adding a prompt appends a missing heading; it never replaces your writing.

Expand **Connections** to see citation and topic links, or choose **Add connection** to select another paper and write your own reason. These explicit links are stored in the note's frontmatter and appear in the graph. Command-click sidebar rows to select several papers for queue actions. Search includes note text.

Frontier's **Use in Paper Notes** action appends a selected annotation to the corresponding review, preserves existing text and verdicts, and adopts a copy of the original PDF. **Return to source** opens the exact page/annotation in Frontier. Sending a passage does not invoke AI. Repeating the same handoff does not duplicate the passage; later annotation edits do not automatically overwrite the review.

Drafts save before switching papers and on quitting. The Save button also marks the paper as read. Failed saves keep the draft and prevent switching. PDF annotation editing lives in Frontier; **Open PDF** here uses your normal PDF app. Both apps remain usable independently. Zotero is not required.

## Storage and sync

The default library is `~/Library/Application Support/Paper Notes`, configurable through `dataRoot`:

- `papers/`: Markdown notes, including personal connection reasons in the `connections` JSON frontmatter field.
- `pdfs/`: adopted PDF copies, excluded from Git.
- `trusted-authors.txt`: your followed authors, initially empty.
- `arxiv-categories.txt`: categories you want fresh-paper recommendations from, initially empty.
- `not-interested.txt`: dismissed recommendations.

Local Git history is initialized automatically. No remote is assigned by default. Set `paperNotesRemote` to your own Git repository URL, or configure `origin` manually in the library. An existing remote is preserved. Git commit identity and authentication must be configured on your Mac. Turn on pushing in the app when ready to sync.

Saved notes are written atomically before an old filename is removed. A failed save reports an error and keeps the current editor draft; resolve the storage issue and retry before switching papers. Adopted PDFs are validated before replacing a stored copy.

## Checks and limitations

`--selftest` tests parsing, ordering, recommendations and graph logic. Tests use synthetic inputs and do not call live AI or metadata services. Set `PAPER_NOTES_TEST_PDFS` to explicitly opt into observing a local PDF corpus when invoking `--selftest` directly. The test runner isolates storage.

The native review window and the actual application window were checked with isolated sample notes, including dark styling and LaTeX. Run `--review-preview <output.png>` with `LOCAL_APPS_TESTING=1` and a temporary `LOCAL_APPS_DATA_ROOT` for the interactive layout check. See [HANDOFF.md](../HANDOFF.md).

Local handoff packets live in `<dataRoot>/Reading Bridge/inbox`; they contain only the explicitly selected passage, note, source metadata and local original path. URL events carry an inbox identifier. Back up both app data directories to retain cross-app source links.

## AI discussions and original PDFs

The bottom bar's **AI settings** chooses Claude, Codex, Gemini or a custom Chat Completions server. Paper Notes initially uses Frontier's existing configuration, then saves an independent provider choice when you press Save. Gemini uses an existing Google login through the supported Antigravity CLI (`agy`); **Sign in in Terminal** starts Google setup. The older Gemini CLI personal login is retired; old executable overrides resolve to `agy`. [Google setup guide](https://antigravity.google/docs/cli/install/). AI Pro/student subscription eligibility depends on the signed-in Google account, and is separate from Gemini API billing.

**Discuss** opens an optional panel beside your review. It includes your current draft, an extracted excerpt of up to 20 PDF pages / 60,000 characters, and the conversation's earlier turns. Excerpts may omit later pages, figures and mathematical structure; verify against the original. Conversation history saves locally and never edits your review automatically. **Add to my review** explicitly inserts a labeled AI excerpt into your draft.

**Open PDF** opens an attached original in your PDF app. If no readable original is attached, the header instead offers **Attach PDF**. This is also available for local, non-arXiv papers received from Frontier.

The AI control shows the selected provider and model; click it to configure them. A blank CLI model is labeled **CLI default**, because the executable chooses the actual model. New discussion replies retain the requested model label from that turn, while older replies say **model not recorded**. The discussion indicator keeps the in-flight selection when settings change. Sign-in opens in its own temporary folder, not your home directory.

Discussion question drafts survive restarting. Questions are saved before contacting the provider; retrying a failed request does not duplicate them. Incoming replies preserve any follow-up already being typed. A conversation save failure retains the answer with **Retry save**; normal quitting waits for unsaved writing to be saved.
