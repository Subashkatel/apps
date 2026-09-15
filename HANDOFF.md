# Development notes

This file describes the source and its current limitations. Machine-specific handoffs, recordings, account settings and private testing notes do not belong in this repository.

## Structure

Each app is an independent Swift executable package. `Shared/` supplies configuration, atomic file operations, AI adapters and the explicit Frontier → Paper Notes handoff. Keep sibling directories together when building. Root scripts build selected apps and optionally install them; normal builds do not launch apps or initialize user libraries.

## Validation

Run `python3 tools/test.py` after building. Tests use synthetic fixtures and temporary data. `--gui` includes Jot/Frontier checks that need a logged-in desktop. Meeting Notes also has an isolated `--ui-check <directory>` harness. Do not run tests against real app libraries or use a live provider unless explicitly intending to send the supplied test prompt.

## Known limits

- Jot undo may group a typing burst rather than individual characters.
- Usage meters depend on undocumented provider endpoints and credential formats; synthetic checks do not prove live login compatibility.
- Frontier is a reading/learning aid, not an EPUB layout engine, OCR service or arbitrary TeX compiler. Original PDFs retain their source formatting; generated teaching content needs verification.
- Paper Notes can explicitly push its personal notes library to a user-configured remote. That library is separate from this application source repository.
- Meeting Notes distinguishes microphone/system tracks, not verified speakers. Live microphone, device switching, echo and long-session behavior need testing on the intended hardware. Synthetic two-hour conversion tests do not substitute for a two-hour real meeting.
- AI models can misinterpret claims and commitments even when their source IDs validate. Review drafts before applying task updates.
- Stable local signing helps macOS retain permissions across rebuilds. A public build does not require or include a developer's signing key.

See each app's README for configuration, data locations, permissions and commands. See [PRIVACY.md](PRIVACY.md) before publishing changes or logs.
