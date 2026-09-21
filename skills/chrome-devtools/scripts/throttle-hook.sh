#!/usr/bin/env bash
# Claude Code PreToolUse hook for navigate_page and new_page. Runs throttle.sh
# on the target URL before the page loads, so pacing does not depend on the
# model remembering it. Reload, back and forward reuse the previous host.
# Over the session budget it asks the human to confirm the load. Needs jq.

set -u

input="$(cat)"
url="$(printf '%s' "$input" | jq -r '.tool_input.url // empty')"
type="$(printf '%s' "$input" | jq -r '.tool_input.type // "url"')"
[ "$type" = url ] || url=''

out="$(bash "$(dirname "$0")/throttle.sh" "$url" 2>&1)"
status=$?

if [ "$status" -eq 3 ]; then
  jq -n --arg reason "$out" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
elif [ "$status" -ne 0 ]; then
  printf '%s\n' "$out" >&2
fi
exit 0
