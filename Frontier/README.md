# Frontier

A reading library and learning graph for books, papers, notes and web pages. The Library is the home screen, with cover thumbnails, search, categories, compact or comfortable cover spacing, and recently opened material. Read presents the material or an AI-generated lesson; Graph shows the prerequisite relationships between concepts.

## Getting started

Install from the repository root with `./install.sh --launch Frontier`. To build without installing, run `./build.sh Frontier`.

1. Choose **Add material**, select a file or paste a web URL, then **Preview import** to check the extracted text.
2. Choose **Add to library** to read it immediately, or **Add & generate** to also create lessons with your selected AI.
3. Open a cover to read, edit its title/category, write notes, read the original document, or generate a learning path. Choose **Done** to save title/category/notes edits.
4. Use **Read** for a calm reading view and **Graph** for the learning map. Reading resumes at the saved section. Existing lessons appear as course collections without changing their Markdown files.

Papers default to a designed cover, with **Cover → Original page** available in material details. PDF books use their first page; EPUB files use an embedded cover when available. Other materials receive a typography-based cover. Covers are scaled thumbnails: original images retain their proportions, while generated covers use portrait book or paper proportions. The category can be changed independently of the file format. Thumbnails stay small as the library grows; new material adds rows. Both generated covers and real cover artwork stay in color in dark and light modes.

## Appearance

The sidebar button at the upper left collapses or reopens the course sidebar in Read and Graph. Its shortcut is Control–Command–S, and visibility is remembered. Graph focus starts empty, follows the node under the pointer, and clears when the pointer leaves; it is independent of the lesson selected in Read.

Dark is the default appearance across the window, reader, graph, import dialogs and settings. The sliders button opens Settings, where Appearance offers Dark, Light and System.

## AI choices

Open **AI settings** in the top bar (or macOS Settings) to select **Claude**, **Codex**, **Gemini (Antigravity)**, or **Custom server**. Claude and Codex use their installed CLI and existing login; optional executable and model fields override automatic detection and the provider default. Sign in using the provider's Terminal command if necessary.

A custom server must provide an OpenAI-compatible **Chat Completions** endpoint. Enter its base URL (for example `http://localhost:1234/v1`), model name and optional API key. Keys are stored in macOS Keychain, separately from settings. **Test connection** sends a short prompt without saving the draft settings. **Save** makes the choice active.

Adding a local document to the library does not call AI. Generating lessons, explanations or walkthroughs sends the relevant text and learning context to the chosen provider. Web imports download their source pages; course discovery and source verification also use the network. CLI generation disables tools and runs in a temporary working directory.

## Formats and reading

Supported imports: PDF, EPUB, LaTeX (`.tex`, `.latex`), Markdown, plain text, HTML/XHTML, DOCX, RTF, and web pages. Previewing an import shows the extracted sections and estimated generation requests.

The **Read** view opens the material itself. **Walkthrough** retains the original lessons, step-by-step explanations and reference view. arXiv papers use locally cached structured HTML with native MathML equations, figures, tables, section links and saved reading position. The attached PDF’s arXiv version is respected, including PDFs imported from disk when their first page identifies the paper. If no structured version is available, Read opens the original PDF directly, preserving equations and figures. Walkthrough remains an optional separate choice. Other text formats retain their existing reader. **Original PDF** displays an attached PDF with its original page layout, figures and colors. **Reading options (…) → Walkthrough beside original** keeps the teaching text beside the PDF. Other original formats open in their associated app; Frontier is not a full EPUB layout engine or TeX compiler. Scanned PDFs need OCR; encrypted/DRM books and image-only EPUBs are unsupported. LaTeX imports expand local `input`/`include` files within the selected file's directory; they never execute TeX. Macro packages and arbitrary TeX commands are not rendered. The reader bundles KaTeX and Markdown rendering resources and shows a native text fallback if formatted rendering fails.

Local source files are copied into the library. For LaTeX projects, the selected source file and expanded reading text are retained, not the entire project folder. Remote PDF/EPUB/document imports retain the downloaded original as well as extracted sections. arXiv abstract, HTML and PDF links resolve to the downloadable PDF. Ordinary web pages retain extracted sections and their URL, rather than a complete website archive. Import limits are 100 MB per local file and 20 MB of extracted archive text.

## Source reading and Paper Notes

In **Original PDF**, select text and choose **Highlight**, or **Add note** to annotate the current page. The **Notes** toggle opens the shared margin editor: italic quoted passages, your notes, and small **Show passage**, **Edit**, and **Use in review** actions. Write and edit directly in the sidebar with **Keep note**; the selected passage and page stay attached while you navigate. The **…** menu on an entry contains **Remove**. **Undo** reverses changes from the current session. Changes save automatically into a separate PDF copy; **Export PDF** saves a portable annotated document. Reading resumes at the last page. Password-protected PDFs must be unlocked before attachment; annotation restrictions in the PDF are respected.

**Explain** asks your selected AI about the current selection and opens its answer beside the source. This sends the selected passage, document title, and nearby text to that provider. In Original PDF and Side by side, discussion follows the current PDF page; Read uses the visible formatted article context or current original page, and Walkthrough uses the selected lesson. PDF text extraction can omit mathematical structure and figures, so the AI is instructed not to claim it has seen them. The explanation and follow-up conversation are saved separately from lessons.

Choose **Use in review** on an annotation to append the passage to its matching review (or create one). Existing writing and judgments remain intact. The review includes a **Return to source** link to the page and annotation. Repeating a handoff does not duplicate the same annotation. Later annotation edits do not automatically rewrite review text.

For an existing course without a PDF, choose **Attach original** in its library details or Source view. This preserves the course's concepts and notes. Zotero integration is not included.

## Storage and configuration

Data is stored under `<dataRoot>/Frontier` (configure `dataRoot` in the shared local-apps configuration):

- `concepts/`: existing Markdown lesson files and learning status.
- `library/<id>/material.json`: title, category, notes, sections, reading position and lesson references.
- `library/<id>/original-<token>.*` and `cover-<token>.png`: retained source and color cover. Earlier filenames remain supported.
- `library/<id>/original-<token>.annotated.pdf`: PDF copy containing standard highlights and notes; the original stays unchanged. Its `.position.json` sidecar stores the last page.
- `library/<id>/formatted-article.json` and its position sidecar: cached arXiv article, embedded images and reading position. Replacing the original invalidates this cache.
- `ai-settings.json`: provider, model, endpoint and executable overrides; no API keys.

Back up the complete Frontier data directory. Each library record is written atomically. Course collections are derived from existing concepts until their own metadata or reading position is saved. Imported originals and lesson files are not modified when a cover title or category changes.

`Resources/courses.json` contains the reference course list. Set `frontierCoursesFile` to your own JSON array of objects with `name` and `url` fields. Set `frontierReaderProfile` to a text file describing your background; the default makes no assumption about your profession or research specialty.

## Command line and checks

Library maintenance commands: `--list-library`, `--add-library <document-or-url>` (no AI), and `--attach-original <material-id> <file>` (preserves existing lessons).

The bundled executable supports `--seed <file>`, `--syllabus`, `--import <document-or-url> [--plan]`, `--grow`, `--write <id>`, `--walk <id>`, `--verify`, and `--status`. CLI imports generate concept files; use the graphical Add material flow to preserve a source in the library. AI commands use the saved provider selection.

`--check-resource <URL>` verifies an import without adding it to the library or calling AI. `--selftest-headless` checks curriculum logic, file formats, library persistence, CLI process handling and AI request construction without contacting providers. `--selftest` additionally checks the bundled WebKit/KaTeX renderer and needs a desktop session. `--preview <output.png>` exercises the native reader's bounds, resizing, fallback and recovery with synthetic content. Add `--preview-library`, `--preview-detail`, `--preview-ai`, or `--preview-import` for UI snapshots; `--dark` selects dark appearance for any preview. `--preview-unwritten` checks italic introductions, rendered math, content-following action spacing, scrolling to the final equation and width-dependent reflow (add `--short` for a short introduction); `--preview-graph` uses a synthetic 197-concept graph and verifies math in its hover card. `--preview-navigation` exercises course disclosure, repeated lesson selection and rapid consecutive clicks in a synthetic 197-lesson course. The reader preview also checks that Library/Read switching preserves the same WebKit instance and scroll position. `--test-ai claude` or `--test-ai codex` sends a small live connection test.

Spaced revisit scheduling is not implemented; concepts marked Still learning remain prioritized. See [HANDOFF.md](../HANDOFF.md) for repository-wide maintenance notes.

Native source checks: use an isolated `LOCAL_APPS_DATA_ROOT` and run `--preview <output.png> --preview-source --source-file <pdf> --dark` (or `--preview-compare`). These exercise native page/highlight buttons, search, persistence, deep links and layout.

`--preview-article` (with `--source-file <PDF>`) checks structured math, figures, sidebar controls and side-by-side reading; it downloads public arXiv HTML unless `FRONTIER_ARTICLE_FIXTURE` supplies a saved article cache. `--preview-graph-focus` checks independent graph focus and preview updates. Use isolated data roots for these checks.

## Discussions and provider choice

**AI settings** is visible in the main bar. Claude, Codex, Gemini and a custom Chat Completions server are supported. Gemini uses the supported Antigravity CLI (`agy`) and its cached Google login; choose **Sign in in Terminal** and use the personal Google account that holds your AI Pro/student subscription. Subscription eligibility and remaining quota are determined by Google. Google retired personal-account access through the older `gemini` client; its saved executable override is automatically replaced by `agy` detection. The Gemini API has separate billing. Antigravity runs in planning mode with sandbox restrictions and slash-command expansion disabled, in a temporary working directory. It also keeps its own CLI conversation history. No provider is contacted merely by opening settings. [Google setup guide](https://antigravity.google/docs/cli/install/).

**Discuss** opens a collapsible conversation beside the reader. **Explain** starts a discussion about the selected PDF passage; follow-ups retain the previous exchange. Conversations save locally per material, separately from lessons and personal notes. Only the displayed context scope, question and conversation are sent when you ask. Text extraction can lose equations and figures: compare claims with the original PDF, and do not treat AI replies as verified citations.

Click a margin bubble to open its annotation. Multiline highlights created in this version are grouped for editing/removal. Routine annotation saves run in the background; pending edits flush before quitting. An error stays visible if saving fails.

In a material's detail view, use **Rename** to edit its title, or **Remove** to remove the material and its exclusive lessons. Shared lessons remain. Removal preserves files and annotations for recovery; the library's sort menu includes **Restore removed material**.

Paper covers default to a colored typographic design. In material details, **Cover → Original page** restores the PDF thumbnail; book covers keep their original artwork. This preference saves per material.

If a PDF has no formatted reading version, **Read** opens its original layout. **Walkthrough** offers optional lesson generation and questions. No quiz sequence is required before reading.

Generated covers use the reviewed publishing-series layout: complete Georgia titles above a reserved artwork area, restrained colors, and fitted abstract artwork. Cover assignments stay in `cover-designs.json`. Different motifs are allocated first, followed by ordered combinations; adding, reordering or restoring material preserves earlier assignments. Original cover images remain fitted and uncropped.

Use the colored circle beside **Highlight** to choose Yellow, Red, Green, Blue or Purple. Frontier remembers the choice. Change an existing annotation through its **… → Change color** menu; Undo restores its previous color, and exported PDFs preserve colors. Meanings are yours to assign. After highlighting, **Add note** attaches your thought to that highlighted passage; a fresh text selection takes priority.

The AI control shows the selected provider and model; click it to configure them. A blank CLI model is labeled **CLI default**, because the executable chooses the actual model. New discussion replies retain the requested model label from that turn, while older replies say **model not recorded**. The discussion indicator keeps the in-flight selection when settings change. Sign-in opens in its own temporary folder, not your home directory.

Unfinished margin notes are saved separately with their quotation and page anchor. Switching materials or restarting returns the draft to its own document. **Keep note** shows **Saving…** until its PDF write succeeds; a failed save retains the draft for retry. Leaving Source and sending a passage to Paper Notes save in the background. Originals remain unchanged.

Discussion question drafts survive restarting. Submitted questions are saved before the provider starts; retrying a failed request does not duplicate the question. A reply does not erase a newer follow-up typed while waiting. A conversation save failure keeps the reply visible with **Retry save**, and normal quitting is prevented until unsaved writing is saved.


## Reading and notes in 1.4

Read is the default for imported material. Walkthrough retains existing concept explanations and their reference view. Lesson progress and rewriting are under **Lesson options**. No six-step learning cycle, spaced review or Anki dependency is added.

In formatted papers, select a passage to reveal **Highlight**, **Add note**, and **Explain**. Notes use the same annotated PDF, draft recovery, colors, editor, and Paper Notes handoff as Original PDF. Click the numbered margin marker to open a note. Notes and discussion share the available side space: opening one closes the other without deleting text.

Passage matching runs off the main thread and requires a unique match in the retained PDF, ignoring whitespace differences. Short, repeated, cross-page or incompatible passages may not match; Frontier asks you to locate them in Original PDF instead of guessing. Mathematical markup and figures are never rewritten by annotation overlays. Existing PDF annotations remain usable even when their quotations cannot be located in formatted text; Show passage opens the original in that case.

This does not add in-text annotations to non-PDF formats. Their existing material notes remain available. Data stays in the existing library structure; no duplicate annotation database is created.
