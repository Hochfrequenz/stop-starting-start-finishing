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
