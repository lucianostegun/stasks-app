#!/bin/bash
# Wipes every trace of Stasks on this Mac to simulate a first launch: tasks, preferences, Keychain tokens,
# the hook copy in Application Support, the hooks in ~/.claude/settings.json (backed up first) and the
# Automation grants. Launch-at-login registration is left alone (no CLI for it); turn it off in Settings first.
set -u
BUNDLE=com.volkker.stasks.app
SETTINGS="$HOME/.claude/settings.json"

if [ "${1:-}" != "-y" ]; then
  printf 'This removes all Stasks state on this Mac (tasks, prefs, tokens, hooks, permissions). Continue? [y/N] '
  read -r answer
  [ "$answer" = "y" ] || { echo "Aborted."; exit 1; }
fi

pkill -x Stasks 2>/dev/null && sleep 1
rm -rf "$HOME/Library/Application Support/Stasks"
defaults delete "$BUNDLE" >/dev/null 2>&1
for account in slack.userToken anthropic.apiKey openai.apiKey; do
  security delete-generic-password -s "$BUNDLE" -a "$account" >/dev/null 2>&1
done

if [ -f "$SETTINGS" ] && grep -q "stasks-hook.sh" "$SETTINGS"; then
  cp "$SETTINGS" "$SETTINGS.stasks-backup-$(date +%s)"
  jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(.hooks |= map(select((.command // "") | test("stasks-hook.sh") | not)) | select(.hooks | length > 0))
        | select(.value | length > 0))
      | if .hooks == {} then del(.hooks) else . end
    else . end' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
fi

tccutil reset AppleEvents "$BUNDLE" >/dev/null 2>&1
echo "Stasks state removed. Open the app to see the first-run setup assistant."
