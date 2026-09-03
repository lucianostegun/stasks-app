#!/bin/bash
# Stasks hook for Claude Code. Reads the hook JSON from stdin and appends one
# line to the Stasks inbox. Must never fail or block Claude: always exit 0.
DIR="${STASKS_INBOX_DIR:-$HOME/Library/Application Support/Stasks}"
JQ="$(command -v jq 2>/dev/null || echo /usr/bin/jq)"
[ -x "$JQ" ] || exit 0
INPUT="$(cat 2>/dev/null)"
[ -n "$INPUT" ] || exit 0
mkdir -p "$DIR" 2>/dev/null || exit 0

LINE="$(printf '%s' "$INPUT" | "$JQ" -c \
  --arg iterm "${ITERM_SESSION_ID:-}" \
  --arg term "${TERM_PROGRAM:-}" \
  --argjson ts "$(date +%s)" '
  {
    event: .hook_event_name,
    session_id: .session_id,
    cwd: .cwd,
    transcript_path: .transcript_path,
    source: .source,
    prompt: .prompt,
    reason: .reason,
    message: .message,
    iterm_session_id: (if $iterm == "" then null else $iterm end),
    term_program: (if $term == "" then null else $term end),
    ts: $ts
  }' 2>/dev/null)"

[ -n "$LINE" ] && printf '%s\n' "$LINE" >> "$DIR/inbox.jsonl" 2>/dev/null
exit 0
