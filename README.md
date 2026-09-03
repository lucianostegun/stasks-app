# Stasks

Stasks is a macOS menu bar app that surfaces Claude Code session tasks and focuses the matching iTerm2 tab when you click one.

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
2. Right click the menu bar icon, "Instalar hooks do Claude" (or Settings, Claude tab). This edits ~/.claude/settings.json with a backup.
3. Settings, Slack tab: paste the user token, Testar, Salvar. Anthropic tab: paste the API key, Testar, Salvar.

## Manual smoke checklist

Claude
- [ ] `cd ~/Projetos/Stasks && claude` in iTerm2: a task "Stasks" appears within 1s, status Open.
- [ ] First prompt "teste de titulo" becomes the title. Second prompt does not change it.
- [ ] `/rename Renomeado pelo rename` updates the title within 2s.
- [ ] Typing "task done" marks Done and moves it to Concluídas. `/exit` on another session also marks Done.
- [ ] `claude --resume` on a Done session reopens it.
- [ ] Left click on the task focuses the exact iTerm2 tab. Close the tab, click again: Finder opens the folder.

Slack
- [ ] Settings → Slack: paste token, Testar shows "OK: SOCi como @…", Salvar.
- [ ] React 👀 on a message: task appears within 15s with provisional title, then the LLM title replaces it (Anthropic key set).
- [ ] Subtitle is "#canal · Autor"; for a DM it is "DM · Autor".
- [ ] Left click opens the message in Slack.
- [ ] React ✅ or :verify: on it: task goes Done within 15s. Removing 👀 does nothing.
- [ ] Revoke/typo the token: red dot on the icon and banner "Slack desconectado (invalid_auth)"; fixing the token and Salvar recovers.

Panel
- [ ] Toggle LIFO/FIFO moves the new-task field and reverses order.
- [ ] 📌 keeps the panel open when clicking other apps, survives switching Spaces, is draggable, position persists after relaunch.
- [ ] Unpinned: click outside or Esc hides it. ⌥⌘S toggles it from anywhere.
- [ ] Right click on a row: status menu works; Editar título and double click edit inline; Remover removes.
- [ ] Concluídas collapses/expands; items older than the configured hours disappear from it.
- [ ] Light and dark system appearance both look right.
