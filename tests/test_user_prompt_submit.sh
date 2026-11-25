# Tests for hooks/user-prompt-submit.sh. Sourced by tests/run.sh.

# Today's fine list and summary as the SessionStart hook would write them.
prepare_state() {
  mkdir -p "$(STATE)"
  printf '%s\n' "$@" > "$(STATE)/fine-2026-11-25"
  printf 'Top active goal: "IDoc import fixed"\n' > "$(STATE)/summary-2026-11-25"
}

test_ups_no_fine_file() {
  assert_eq "silent" "$(run_hook user-prompt-submit)" ""
}
test_ups_repo_is_fine() {
  prepare_state example/work-repo
  assert_eq "silent in goal repo" "$(run_hook user-prompt-submit)" ""
}
test_ups_fine_file_crlf_and_case() {
  mkdir -p "$(STATE)"
  printf 'Example/Work-Repo\r\n' > "$(STATE)/fine-2026-11-25"
  assert_eq "crlf + case tolerated" "$(run_hook user-prompt-submit)" ""
}
test_ups_nudges_once() {
  prepare_state example/other
  local out
  out="$(run_hook user-prompt-submit)"
  assert_contains "instruction" "$out" "stop-starting: This repo (example/work-repo) is not part of the user's active goals"
  assert_contains "summary included" "$out" 'Top active goal: "IDoc import fixed"'
  assert_eq "second prompt silent" "$(run_hook user-prompt-submit)" ""
}
test_ups_empty_summary() {
  prepare_state example/other
  : > "$(STATE)/summary-2026-11-25"
  assert_eq "silent without anything to point to" "$(run_hook user-prompt-submit)" ""
}
test_ups_disabled() {
  prepare_state example/other
  export FOCUS_DISABLE=1
  assert_eq "silent" "$(run_hook user-prompt-submit)" ""
}
test_ups_no_remote() {
  prepare_state example/other
  git -C "$REPO" remote remove origin
  assert_eq "silent without remote" "$(run_hook user-prompt-submit)" ""
}
