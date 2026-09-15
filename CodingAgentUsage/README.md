# Coding Agent Usage

An icon in the macOS menu bar opens usage and reset times for Claude and Codex accounts. Names and percentages appear inside the dropdown only.

Build with `./build.sh CodingAgentUsage` from the repository root. Install and open with `./install.sh --launch CodingAgentUsage`.

## Current accounts

The default rows are **Claude · Local login** and **Codex · Local login**. They automatically read the corresponding local CLI login; you do not need to add those accounts manually. Switching the local CLI login changes the account that row follows on the next refresh. A saved email is shown when available to help distinguish the login from your custom label.

Use the account's **… → Rename** menu to change its label. Renaming preserves its credential source and automatic detection. Current-login rows cannot be removed. If you use the same account in a current-login row and a saved profile, both show the same quota; the app does not add percentages together.

## Ordering and subscription dates

Drag an account title up or down and release at the blue insertion line. Hold near the top or bottom edge to scroll during the drag. Release outside the account list to cancel. There are no drag icons. Its **…** menu also has **Move up**, **Move down**, **Move to top**, and **Move to bottom**. All rows, including local logins, can move; the order is saved.

Use **… → Set subscription date** after an account's identity is detected. Choose **Renews on** or **Ends on**, enter the date, then **Save date**. Edit or clear it from the same menu. Dates marked **saved** are local reminders; they do not automatically advance or change your subscription. They follow the detected account identity, so switching the local login hides the previous account's date and switching back restores it. Only an opaque hash of that identity is saved alongside the date.

When Codex's cached login metadata supplies an explicit subscription active-until date, it appears as **Active through … · from login**. This can be stale and is not a verified billing renewal or cancellation date. A date you save takes precedence. Claude's current login metadata has no renewal/end date; unknown dates remain blank. Usage reset times and token expiration are never treated as subscription dates. No additional provider requests are made for this feature.

## Add accounts

1. Click **+ Add account** and choose **Claude** or **Codex**.
2. Enter a name such as Personal or Work and click **Create & sign in**.
3. Terminal opens the provider's official login command. Complete the browser login with the intended account.
4. Return to the usage bar and press Refresh. Repeat for your other accounts.

Each saved account has an independent local profile, usage bars, reset times, last-update time, and errors. Open its **…** menu to rename it, sign in again, or open its provider CLI. Saved profiles remain separate from the ordinary local login you switch with sign-out/sign-in.

If you already use profiles, enter a name and select **Use an existing profile folder**. For Claude, select the local `CLAUDE_CONFIG_DIR`; for Codex, select the local `CODEX_HOME` containing its `auth.json`. The app never falls back from a named profile to a different account.

Usage comes from the provider's account-wide endpoint. Claude subscription usage therefore includes activity on other computers and SSH servers using that same account. Accounts used only on another machine need a local sign-in here; the bar does not connect over SSH or read remote logs. API billing is separate from these subscription meters.

Removing a saved account removes its row only. Its profile, credentials, and sessions are preserved so it can be added again using the existing-folder option.

## Credentials and configuration

Claude credentials are read from the corresponding macOS Keychain item or Claude's own `.credentials.json` fallback. Current Codex credentials come from `~/.codex/auth.json`, `$CODEX_HOME/auth.json`, or the configurable `codexAuthFile`. Additional Codex accounts read `<profile>/auth.json`. The Codex launchers explicitly select CLI file credential storage for consistent login and use; this version does not read Codex Keychain-only credentials.

The app does not copy or independently refresh tokens. If an account expires, use its **Open Claude/Open Codex** action to let the CLI refresh it, or **Sign in** again. Signing out or revoking a session may require reconnecting it here. A Claude Keychain prompt may appear on first use.

Labels, account order, saved subscription dates, and profile locations are saved in `<dataRoot>/CodingAgentUsage/claude-accounts.json`; the legacy filename is retained for compatibility, and version 1 and 2 settings migrate automatically to version 3, preserving custom labels and profile locations. This file contains no tokens. New profiles live under `ClaudeProfiles/<id>` or `CodexProfiles/<id>` in that app data folder. Existing profiles stay where you selected them.

Launchers discover `claude` and `codex` on PATH or common installation paths. Override them using `claudePath` / `LOCAL_APPS_CLAUDE` or `codexPath` / `LOCAL_APPS_CODEX`. Generated Terminal launchers contain paths and commands, never credentials. GUI apps normally use the JSON configuration rather than your interactive shell environment.

The app polls every five minutes and maintains an independent retry schedule for each account. Opening the panel refreshes stale data without skipping active backoff; manual refresh has a 15-second cooldown. Transient errors retain the last successful values for the same credentials and mark them stale. Changed credentials clear old values if the next fetch fails.

The usage endpoints and Claude Keychain service naming are undocumented interfaces and may change. Claude's service naming was checked against installed Claude Code 2.1.270. See [Claude credential management](https://code.claude.com/docs/en/authentication#credential-management), [Claude usage limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work), and [Codex authentication](https://learn.chatgpt.com/docs/auth).

## Validation

```sh
"$HOME/Library/Caches/LocalApps/Builds/Coding Agent Usage.app/Contents/MacOS/CodingAgentUsage" --selftest
```

Checks use synthetic credentials, mocked requests, and temporary account settings. They do not read real credentials or contact providers. They cover profile isolation, settings migrations, renaming, reordering, subscription date persistence and account switching, credential parsing, backoff, shell quoting, and overlapping/removing in-flight requests. `--preview /tmp/usage-preview.png` renders synthetic rows for layout review; add `--preview-add` to show the provider picker and add form or `--preview-date` to show the subscription editor. Use `--preview-intrinsic` to validate the dropdown’s natural size. `--preview-drag` dispatches mouse events only inside the synthetic preview window to verify title dragging, edge scrolling, bottom insertion, and saved order. Live additional-account authentication requires user sign-in.

The local `runtime.json` beside the account settings reports provider names, detected identities as booleans, usage-window counts, errors, and the rendered account-list height after the dropdown opens. It contains no emails, tokens, or usage values. This helps distinguish login failures from dropdown layout problems.
