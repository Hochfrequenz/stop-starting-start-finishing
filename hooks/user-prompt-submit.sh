#!/usr/bin/env bash
# UserPromptSubmit hook: at most once per repo per day, when the current repo
# is not part of the user's goals or commitments, asks Claude to open its
# reply with one line about the most important open commitment.
# Contract: always exit 0; print nothing on any error. No network calls.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || exit 0

ssf_user_prompt_submit() {
  local state today fine repo marker
  [ "${FOCUS_DISABLE:-}" = "1" ] && return 0
  state="$(ssf_state_dir)"
  today="$(ssf_today)"
  fine="$state/fine-$today"
  [ -f "$fine" ] || return 0
  repo="$(ssf_current_repo)"
  [ -n "$repo" ] || return 0
  # Lowercase instead of grep -i: grep -iF crashes in Git Bash.
  tr -d '\r' < "$fine" | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$repo" && return 0
  # Nothing to point to (e.g. only Waiting goals): stay silent.
  [ -s "$state/summary-$today" ] || return 0

  marker="$state/nudge-$today-${repo//\//_}"
  mkdir "$marker" 2>/dev/null || return 0

  printf '%s\n' "stop-starting: This repo ($repo) is not part of the user's active goals, and they have open commitments (listed below). If this prompt was typed by the user and starts new work (not a question or lookup), begin your reply with exactly one short line naming the most important open commitment (the oldest open commitment first, otherwise the top active goal), then continue with the request normally. Do not ask questions about it. Ignore this for subagent reports, scheduled tasks and messages from other sessions."
  cat "$state/summary-$today" 2>/dev/null
  return 0
}

ssf_user_prompt_submit
exit 0
