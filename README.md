# Stasks

Stasks is a macOS menu bar app that keeps one stack of tasks from three sources: Claude Code sessions (via hooks), Slack messages you react to with 👀, and tasks you type by hand in the panel. Clicking a Claude task focuses the matching iTerm2 tab; clicking a Slack task opens the message in Slack.

## Requirements

- macOS with iTerm2 for Claude task focusing.
- `jq` on `PATH`: the Claude hook parses its payload with `jq` and exits silently when it is missing, so no Claude tasks appear.
- The first click on a Claude task triggers a macOS Automation (Apple Events) prompt for iTerm2. It must be allowed, otherwise focusing silently falls back to opening the project folder in Finder.
- Release builds are signed with the Volkker Developer ID certificate (team MJGJ2M2MK9) and notarized, so Keychain and Automation grants survive updates. Building on a machine without that certificate needs `CODE_SIGN_IDENTITY: "-"` in `project.yml`, and then those prompts return after every rebuild.

## Make targets

- `make gen`: run xcodegen to (re)generate `Stasks.xcodeproj` from `project.yml`.
- `make build`: generate the project and build the `Stasks` scheme in Release configuration.
- `make test-core`: run the `StasksCore` package test suite.
- `make test-hooks`: run the hooks test suite.
- `make test`: run `test-core` and `test-hooks`.
- `make run`: build, then launch `Stasks.app`.
- `make install`: build, then copy `Stasks.app` into `/Applications` and launch it.
- `make clean`: remove build artifacts and the package's `.build` directory.
- `make reset-state`: wipe all local Stasks state (tasks, prefs, tokens, hooks, Automation grants) to test a first launch. Asks before deleting.
- `make release`: archive, export signed with Developer ID, build `build/Stasks-<version>.dmg`, notarize and staple it. See Releasing.

## Install

1. Download the latest `.dmg` from GitHub Releases and drag Stasks to Applications, or `make install` to build from source (Release, copies to /Applications, launches).
2. On first launch the setup assistant opens and checks Claude Code, `jq`, the hooks, the Automation permission per terminal, launch at login and Slack, each with a button that fixes it. It is also in the menu bar menu ("Setup assistant…") and opens from the panel banner whenever the hooks stop matching.
3. Hooks: the app keeps a copy of `stasks-hook.sh` in `~/Library/Application Support/Stasks/` and points `~/.claude/settings.json` at it (with a backup of the file), so moving or reinstalling the app does not break them. "Install Claude hooks" in the menu or Settings, Claude tab does the same.
3. Settings, Slack tab: paste the user token, Test, Save.
4. Settings, Titles tab: pick a provider for Slack task titles and Test. Three options:
   - **Anthropic API**: paste an `sk-ant-…` key, Save. Model fixed to Haiku.
   - **OpenAI-compatible**: base URL, model and key. Defaults to `https://api.openai.com/v1` and `gpt-5-mini`. Also works with Ollama (`http://localhost:11434/v1`, key empty), Groq, OpenRouter.
   - **Claude Code CLI**: no key. Runs `claude -p --model haiku` with `--setting-sources ""` so your hooks (including Stasks' own) stay off. Needs `claude` in `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`, or a path set in the field. About 3s per title.

## Releasing

Downloads live on GitHub Releases as a notarized `.dmg`. Version comes from `MARKETING_VERSION` in `project.yml`.

Locally, once: install the Developer ID Application certificate, then store App Store Connect API credentials for `notarytool`:

```
xcrun notarytool store-credentials notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
```

Then `make release` and `gh release create vX.Y.Z build/Stasks-X.Y.Z.dmg --generate-notes`.

CI does the same on every `v*` tag (`.github/workflows/release.yml`). It needs these repository secrets: `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` (the certificate plus private key exported from Keychain Access as .p12), `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contents of the .p8). The workflow fails if the tag does not match `MARKETING_VERSION`.

## Language

The UI follows the macOS language when it is English or Portuguese, and falls back to English otherwise. Settings, General tab, "Language" overrides it (System, English, Português) and applies immediately, no relaunch.

Strings live in `Stasks/Resources/<code>.lproj/Localizable.strings`, looked up through `L("key")` (`Stasks/Localization/L10n.swift`). `es.lproj` and `fr.lproj` exist with English placeholder values: translate them, then add `.es` / `.fr` to `AppLanguage.selectable` to expose them in the picker. Missing keys fall back to English.

## Manual smoke checklist

Claude
- [ ] `cd ~/Projetos/Stasks && claude` in iTerm2: nothing appears yet. Send "teste de titulo": a task with that title appears within 1s, status Open, subtitle "Stasks".
- [ ] When Claude answers, the subtitle becomes the start of the answer and the row shows a soft green glow. Send a second prompt: the title does not change and the glow clears. When Claude asks for permission, the row pulses amber.
- [ ] Slash commands alone (`/clear`, `/help`) never create a task.
- [ ] `/rename Renomeado pelo rename` updates the title within 2s.
- [ ] Typing "task done" marks Done and moves it to Completed. `/exit` on another session also marks Done.
- [ ] `claude --resume` on a Done session reopens it.
- [ ] Left click on the task focuses the exact iTerm2 tab. Close the tab, click again: Finder opens the folder.

Slack
- [ ] Settings → Slack: paste token, Test shows "OK: SOCi as @…", Save.
- [ ] Settings → Titles: each provider's Test returns "OK (…)". With Claude Code CLI selected, generating a title must not create a Claude task in the panel.
- [ ] React 👀 on a message: task appears within 15s with provisional title, then the LLM title replaces it (Anthropic key set).
- [ ] Subtitle is "#channel · Author"; for a DM it is "DM · Author".
- [ ] Left click opens the message in Slack.
- [ ] React ✅, ✔️, ☑️, :verify:, :done: or :done-check: on it: task goes Done within 15s. Removing 👀 does nothing.
- [ ] Revoke/typo the token: red dot on the icon and banner "Slack disconnected (invalid_auth)"; fixing the token and Save recovers.

Panel
- [ ] Toggle LIFO/FIFO moves the new-task field and reverses order.
- [ ] Drag the bottom edge: the panel keeps that height (also after relaunch) and the list scrolls inside it. Double click the "Stasks" title: height goes back to automatic.
- [ ] 📌 keeps the panel open when clicking other apps, survives switching Spaces, is draggable, position persists after relaunch.
- [ ] Unpinned: click outside or Esc hides it. ⌥⌘S toggles it from anywhere.
- [ ] Right click on a row: status menu works; Edit title and double click edit inline; Remove removes.
- [ ] Completed collapses/expands; items older than the configured hours disappear from it.
- [ ] Light and dark system appearance both look right.
- [ ] Settings → General → Language: switching to Português relabels the panel, the Settings window and the status item menu without relaunch; System follows macOS; a value persists after relaunch.
