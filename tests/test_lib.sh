# Unit tests for hooks/lib.sh. Sourced by tests/run.sh.

test_normalize_https() {
  assert_eq "https with .git" "$(ssf_normalize_remote https://github.com/Hochfrequenz/Foo.git)" "hochfrequenz/foo"
}
test_normalize_scp_ssh() {
  assert_eq "scp-style ssh" "$(ssf_normalize_remote git@github.com:Hochfrequenz/foo.git)" "hochfrequenz/foo"
}
test_normalize_ssh_url_with_port() {
  assert_eq "ssh url with port" "$(ssf_normalize_remote ssh://git@github.com:22/owner/repo.git)" "owner/repo"
}
test_normalize_strips_credentials() {
  assert_eq "credentials" "$(ssf_normalize_remote https://x-access-token:ghp_secret@github.com/Owner/Repo)" "owner/repo"
}
test_normalize_trailing_slash() {
  assert_eq "trailing slash" "$(ssf_normalize_remote https://github.com/o/r/)" "o/r"
}
test_normalize_garbage() {
  assert_eq "single segment" "$(ssf_normalize_remote nonsense)" ""
}
test_current_repo_from_pwd() {
  assert_eq "repo from cwd" "$(cd "$REPO" && ssf_current_repo)" "example/work-repo"
}
test_current_repo_prefers_project_dir() {
  local other="$TMP/other"
  git init -q "$other"
  git -C "$other" remote add origin git@github.com:Example/Other.git
  assert_eq "CLAUDE_PROJECT_DIR wins" "$(cd "$REPO" && CLAUDE_PROJECT_DIR="$other" ssf_current_repo)" "example/other"
}
test_current_repo_without_remote() {
  local bare="$TMP/noremote"
  git init -q "$bare"
  assert_eq "no remote" "$(cd "$bare" && ssf_current_repo)" ""
}

test_read_goals_missing_file() {
  assert_eq "no goals.md" "$(ssf_read_goals)" ""
}
test_read_goals_sections() {
  goals <<'EOF'
wip-limit: 2

## Active
### IDoc import fixed
- repos: Example/Work-Repo, example/second
- done-when: customer imports without errors
- resume: mapping for E1EDP01

## Waiting
### EDM skill released
- repos: example/other
- waiting-for: review by alice
- follow-up: 2026-11-28

## Notes
### Not a goal
- repos: example/ignored
EOF
  assert_eq "parsed goals" "$(ssf_read_goals)" \
    "$(printf 'active\tIDoc import fixed\texample/work-repo,example/second\t\nwaiting\tEDM skill released\texample/other\t2026-11-28')"
}
test_read_goals_crlf_and_bom() {
  printf '\357\273\277wip-limit: 2\r\n\r\n## Active\r\n### A goal\r\n- repos: O/R1\r\n' > "$HOME/.claude/focus/goals.md"
  assert_eq "crlf + bom" "$(ssf_read_goals)" "$(printf 'active\tA goal\to/r1\t')"
}

test_json_escape() {
  local input expected
  input="$(printf 'a "b" \\c\tx\r\nzweite Zeile ä')"
  expected='a \"b\" \\c x\nzweite Zeile ä'
  assert_eq "json escape" "$(printf '%s' "$input" | ssf_json_escape)" "$expected"
}
test_fetch_issues_passthrough() {
  GH_STUB_OUTPUT="$(printf 'example/a\talice\t12 days ago\tIDoc import\thttps://github.com/example/a/issues/1\n')"
  assert_eq "stub output" "$(ssf_fetch_issues)" \
    "$(printf 'example/a\talice\t12 days ago\tIDoc import\thttps://github.com/example/a/issues/1')"
}
test_fetch_issues_without_gh() {
  SSF_GH="$TMP/does-not-exist"
  assert_eq "no gh" "$(ssf_fetch_issues)" ""
}
test_fetch_issues_gh_fails() {
  GH_STUB_OUTPUT="partial"
  GH_STUB_EXIT=1
  assert_eq "gh error" "$(ssf_fetch_issues)" ""
}
test_fetch_issues_timeout() {
  GH_STUB_OUTPUT="late"
  GH_STUB_SLEEP=3
  SSF_GH_TIMEOUT=1
  assert_eq "gh too slow" "$(ssf_fetch_issues)" ""
}
test_fetch_issues_timeout_fallback() {
  export SSF_FORCE_FALLBACK=1
  GH_STUB_OUTPUT="late"
  GH_STUB_SLEEP=3
  SSF_GH_TIMEOUT=1
  assert_eq "gh too slow without timeout(1)" "$(ssf_fetch_issues)" ""
  unset SSF_FORCE_FALLBACK
}
test_with_timeout_fallback_passes_output() {
  export SSF_FORCE_FALLBACK=1
  assert_eq "fast command output kept" "$(ssf_with_timeout 2 printf 'ok')" "ok"
  unset SSF_FORCE_FALLBACK
}
