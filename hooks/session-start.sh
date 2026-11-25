#!/usr/bin/env bash
# SessionStart hook: once per day, shows the focus banner (as systemMessage)
# and writes the day's fine list and summary for the UserPromptSubmit nudge.
# Contract: always exit 0; print nothing on any error.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || exit 0

ssf_session_start() {
  local state today marker issues goals
  [ "${FOCUS_DISABLE:-}" = "1" ] && return 0
  state="$(ssf_state_dir)"
  today="$(ssf_today)"
  mkdir -p "$state" 2>/dev/null || return 0

  # Claim today's banner atomically; several sessions may start at once.
  marker="$state/banner-$today"
  mkdir "$marker" 2>/dev/null || return 0
  # If we are killed or fail before printing, release the claim so the
  # next session can retry.
  trap 'rmdir "$marker" 2>/dev/null' EXIT
  trap 'exit 0' TERM INT

  ssf_cleanup_old "$state" "$today"
  issues="$(ssf_fetch_issues)"
  goals="$(ssf_read_goals)"

  if [ -n "$issues" ] || [ -n "$goals" ]; then
    ssf_write_fine "$state/fine-$today" "$issues" "$goals"
    ssf_write_summary "$state/summary-$today" "$issues" "$goals"
    printf '{"systemMessage":"%s"}\n' "$(ssf_banner "$issues" "$goals" "$today" | ssf_json_escape)"
  fi
  trap - EXIT
}

ssf_session_start
exit 0
