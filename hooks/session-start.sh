#!/usr/bin/env bash
# SessionStart hook: once per day, shows the focus banner (as systemMessage)
# and writes the day's fine list and summary for the UserPromptSubmit nudge.
# Contract: always exit 0; print nothing on any error.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || exit 0

ssf_session_start() {
  local state today issues goals
  [ "${FOCUS_DISABLE:-}" = "1" ] && return 0
  state="$(ssf_state_dir)"
  today="$(ssf_today)"
  mkdir -p "$state" 2>/dev/null || return 0

  # Claim today's banner atomically; several sessions may start at once.
  SSF_MARKER="$state/banner-$today"
  mkdir "$SSF_MARKER" 2>/dev/null || return 0
  # If we are killed or fail before printing, release the claim so the
  # next session can retry. SSF_MARKER is global: the EXIT trap runs after
  # this function has returned, when its locals are gone.
  trap 'rmdir "$SSF_MARKER" 2>/dev/null' EXIT
  trap 'exit 0' TERM INT

  ssf_cleanup_old "$state" "$today"
  issues="$(ssf_fetch_issues)"
  goals="$(ssf_read_goals)"

  if [ -n "$issues" ] || [ -n "$goals" ]; then
    # If the cache can't be written, stay silent and let the EXIT trap
    # release the claim so a later session retries.
    ssf_write_fine "$state/fine-$today" "$issues" "$goals" 2>/dev/null || return 0
    ssf_write_summary "$state/summary-$today" "$issues" "$goals" 2>/dev/null || return 0
    printf '{"systemMessage":"%s"}\n' "$(ssf_banner "$issues" "$goals" "$today" | ssf_json_escape)"
  fi
  trap - EXIT
}

ssf_session_start
exit 0
