# Tests for hooks/session-start.sh. Sourced by tests/run.sh.

sample_goals() {
  goals <<'EOF'
wip-limit: 2

## Active
### IDoc import fixed
- repos: Example/Work-Repo

## Waiting
### EDM skill released
- repos: example/other
- waiting-for: review by alice
- follow-up: 2026-11-25
EOF
}

test_ss_disabled() {
  sample_goals
  export FOCUS_DISABLE=1
  assert_eq "no output" "$(run_hook session-start)" ""
  assert_eq "no marker" "$(ls "$(STATE)" 2>/dev/null)" ""
}
test_ss_nothing_to_show() {
  assert_eq "no output" "$(run_hook session-start)" ""
  assert_eq "marker kept" "$([ -d "$(STATE)/banner-2026-11-25" ] && echo yes)" "yes"
}
test_ss_goals_only() {
  sample_goals
  assert_eq "banner json" "$(run_hook session-start)" \
    '{"systemMessage":"🎯 Active: IDoc import fixed · Waiting: EDM skill released (follow-up due)"}'
  assert_eq "fine file" "$(cat "$(STATE)/fine-2026-11-25")" "$(printf 'example/other\nexample/work-repo')"
  assert_eq "summary file" "$(cat "$(STATE)/summary-2026-11-25")" 'Top active goal: "IDoc import fixed"'
}
test_ss_issues_and_goals() {
  sample_goals
  GH_STUB_OUTPUT="$(printf 'example/a\talice\t12 days ago\tSay "hi" \\ now\turl1\n')"
  local out
  out="$(run_hook session-start)"
  assert_contains "issue line escaped" "$out" '⏳ Waiting on you: \"Say \"hi\" \\ now\" (alice, 12 days ago)\n🎯 Active:'
  assert_contains "json start" "$out" '{"systemMessage":"'
}
test_ss_once_per_day() {
  sample_goals
  run_hook session-start > /dev/null
  assert_eq "second run silent" "$(run_hook session-start)" ""
}
test_ss_gh_fails_still_shows_goals() {
  sample_goals
  GH_STUB_OUTPUT="garbage"
  GH_STUB_EXIT=1
  assert_contains "goals shown" "$(run_hook session-start)" "🎯 Active: IDoc import fixed"
}
test_ss_gh_hangs_still_shows_goals() {
  sample_goals
  GH_STUB_SLEEP=3
  SSF_GH_TIMEOUT=1
  assert_contains "goals shown" "$(run_hook session-start)" "🎯 Active: IDoc import fixed"
}
test_ss_concurrent_runs_print_once() {
  sample_goals
  run_hook session-start > "$TMP/out1" &
  run_hook session-start > "$TMP/out2" &
  wait
  assert_eq "exactly one banner" "$(cat "$TMP/out1" "$TMP/out2" | grep -c systemMessage)" "1"
}
test_ss_cleans_old_state() {
  sample_goals
  mkdir -p "$(STATE)/banner-2026-11-20"
  run_hook session-start > /dev/null
  assert_eq "old marker gone" "$([ -e "$(STATE)/banner-2026-11-20" ] && echo still-there)" ""
}
test_ss_cache_write_failure_is_silent_and_retries() {
  sample_goals
  mkdir -p "$(STATE)/fine-2026-11-25"
  local out
  out="$(run_hook session-start 2>&1)"
  assert_eq "no output, no stderr" "$out" ""
  assert_eq "claim released" "$([ -e "$(STATE)/banner-2026-11-25" ] && echo kept)" ""
}
