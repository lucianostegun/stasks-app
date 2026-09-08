#!/bin/bash
# Tests for stasks-hook.sh. Run: bash hooks/test-hook.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/stasks-hook.sh"
TMP="$(mktemp -d)"
export STASKS_INBOX_DIR="$TMP"
FAILS=0

# Runs a command with a fresh pseudo-terminal as its controlling tty, and waits for it. Works even when this
# test has no tty itself (CI, editor tasks), unlike `script`, which needs a tty on stdin.
with_pty() {
  python3 - "$@" <<'PY'
import os, sys
pid, fd = os.forkpty()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
while True:
    try:
        if not os.read(fd, 4096): break
    except OSError:
        break
os.waitpid(pid, 0)
PY
}

assert_eq() { # actual expected label
  if [ "$1" != "$2" ]; then echo "FAIL $3: got '$1' expected '$2'"; FAILS=$((FAILS+1)); else echo "ok   $3"; fi
}

# 1. SessionStart carries cwd, transcript, source, iterm id
echo '{"hook_event_name":"SessionStart","session_id":"S1","cwd":"/tmp/proj","transcript_path":"/tmp/t.jsonl","source":"startup"}' \
  | ITERM_SESSION_ID="w0t1p0:ABC" TERM_PROGRAM="iTerm.app" bash "$HOOK"
LINE="$(tail -n1 "$TMP/inbox.jsonl")"
assert_eq "$(echo "$LINE" | jq -r .event)" "SessionStart" "event name"
assert_eq "$(echo "$LINE" | jq -r .session_id)" "S1" "session id"
assert_eq "$(echo "$LINE" | jq -r .cwd)" "/tmp/proj" "cwd"
assert_eq "$(echo "$LINE" | jq -r .transcript_path)" "/tmp/t.jsonl" "transcript"
assert_eq "$(echo "$LINE" | jq -r .source)" "startup" "source"
assert_eq "$(echo "$LINE" | jq -r .iterm_session_id)" "w0t1p0:ABC" "iterm id"
assert_eq "$(echo "$LINE" | jq -r '.ts | type')" "number" "ts is number"

# 2. UserPromptSubmit keeps prompt with quotes and newlines intact
printf '{"hook_event_name":"UserPromptSubmit","session_id":"S1","prompt":"say \\"hi\\"\\nline2"}' | bash "$HOOK"
LINE="$(tail -n1 "$TMP/inbox.jsonl")"
assert_eq "$(echo "$LINE" | jq -r .prompt)" "$(printf 'say "hi"\nline2')" "prompt preserved"
assert_eq "$(echo "$LINE" | jq -r .cwd)" "null" "missing cwd is null"

# 3. Appends, never overwrites
assert_eq "$(wc -l < "$TMP/inbox.jsonl" | tr -d ' ')" "2" "two lines appended"

# 4. Garbage input exits 0 and writes nothing
echo 'not json' | bash "$HOOK"; RC=$?
assert_eq "$RC" "0" "exit 0 on garbage"
assert_eq "$(wc -l < "$TMP/inbox.jsonl" | tr -d ' ')" "2" "garbage not appended"

# 5. Empty stdin exits 0
bash "$HOOK" < /dev/null; RC=$?
assert_eq "$RC" "0" "exit 0 on empty stdin"

# 6b. Notification carries message
echo '{"hook_event_name":"Notification","session_id":"S1","message":"Claude needs permission"}' | bash "$HOOK"
LINE="$(tail -n1 "$TMP/inbox.jsonl")"
assert_eq "$(echo "$LINE" | jq -r .event)" "Notification" "notification event"
assert_eq "$(echo "$LINE" | jq -r .message)" "Claude needs permission" "notification message"

# 6. No ITERM env -> null
echo '{"hook_event_name":"SessionEnd","session_id":"S1","reason":"exit"}' | env -u ITERM_SESSION_ID bash "$HOOK"
LINE="$(tail -n1 "$TMP/inbox.jsonl")"
assert_eq "$(echo "$LINE" | jq -r .iterm_session_id)" "null" "iterm null when unset"
assert_eq "$(echo "$LINE" | jq -r .reason)" "exit" "reason"

# 7. term_program is recorded, and tty comes from the controlling terminal (allocated here with with_pty)
: > "$TMP/inbox.jsonl"
with_pty bash -c "echo '{\"hook_event_name\":\"SessionStart\",\"session_id\":\"S2\"}' | STASKS_INBOX_DIR='$TMP' TERM_PROGRAM=Apple_Terminal bash '$HOOK'"
LINE="$(tail -n1 "$TMP/inbox.jsonl")"
assert_eq "$(echo "$LINE" | jq -r .term_program)" "Apple_Terminal" "term program"
case "$(echo "$LINE" | jq -r .tty)" in
  /dev/tty*) echo "ok   tty from controlling terminal" ;;
  *) echo "FAIL tty from controlling terminal: got '$(echo "$LINE" | jq -r .tty)'"; FAILS=$((FAILS+1)) ;;
esac

rm -rf "$TMP"
if [ $FAILS -gt 0 ]; then echo "$FAILS failure(s)"; exit 1; fi
echo "all hook tests passed"
