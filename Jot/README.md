# Jot

Markdown sticky notes with formatting and bundled KaTeX math rendering.

Build: `./build.sh Jot` from the repository root. Install: `./install.sh Jot`.

- **Control–Option–Space:** new note.
- **Control–Option–S:** show or hide notes.
- **Command–B / Command–I:** bold / italic.
- **Command–R:** switch between editing and rendered markdown.
- **Command–Delete:** move a note to the app's `.trash` folder.

Notes are plain markdown in `<dataRoot>/Jot`, defaulting to `~/Library/Application Support/Jot`. The menu bar icon provides access to the notes folder. Existing data is preserved across rebuilds.

CLI examples, from the repository root:

```sh
"$HOME/Library/Caches/LocalApps/Builds/Jot.app/Contents/MacOS/Jot" --new "An idea"
"$HOME/Library/Caches/LocalApps/Builds/Jot.app/Contents/MacOS/Jot" --list
```

There is no automatically installed `jot` shell alias. Use the executable path or create your own alias.

Known limitation: undo can revert an entire typing burst. The self-test also exercises windows, keyboard commands, the clipboard and WebKit, so it needs a desktop session. See [verification](../README.md#verification-and-current-limitations).
