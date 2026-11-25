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
