# Stasks

Stasks is a macOS menu bar app that keeps one stack of tasks from three sources: Claude Code sessions (via hooks), Slack messages you react to with 👀, and tasks you type by hand in the panel. Clicking a Claude task focuses the matching iTerm2 tab; clicking a Slack task opens the message in Slack.

## Requirements

- macOS with iTerm2 for Claude task focusing.
- `jq` on `PATH`: the Claude hook parses its payload with `jq` and exits silently when it is missing, so no Claude tasks appear.
- The first click on a Claude task triggers a macOS Automation (Apple Events) prompt for iTerm2. It must be allowed, otherwise focusing silently falls back to opening the project folder in Finder.
- The app is signed ad hoc, so Keychain and Automation prompts can reappear after every rebuild.

## Make targets

- `make gen`: run xcodegen to (re)generate `Stasks.xcodeproj` from `project.yml`.
- `make build`: generate the project and build the `Stasks` scheme in Release configuration.
- `make test-core`: run the `StasksCore` package test suite.
- `make test-hooks`: run the hooks test suite.
- `make test`: run `test-core` and `test-hooks`.
- `make run`: build, then launch `Stasks.app`.
- `make install`: build, then copy `Stasks.app` into `/Applications` and launch it.
- `make clean`: remove build artifacts and the package's `.build` directory.

## Install

1. `make install` (builds Release, copies to /Applications, launches).
2. Right click the menu bar icon, "Install Claude hooks" (or Settings, Claude tab). This edits ~/.claude/settings.json with a backup.
3. Settings, Slack tab: paste the user token, Test, Save.
4. Settings, Titles tab: pick a provider for Slack task titles and Test. Three options:
   - **Anthropic API**: paste an `sk-ant-…` key, Save. Model fixed to Haiku.
   - **OpenAI-compatible**: base URL, model and key. Defaults to `https://api.openai.com/v1` and `gpt-5-mini`. Also works with Ollama (`http://localhost:11434/v1`, key empty), Groq, OpenRouter.
   - **Claude Code CLI**: no key. Runs `claude -p --model haiku` with `--setting-sources ""` so your hooks (including Stasks' own) stay off. Needs `claude` in `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`, or a path set in the field. About 3s per title.

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
- [ ] React ✅ or :verify: on it: task goes Done within 15s. Removing 👀 does nothing.
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
