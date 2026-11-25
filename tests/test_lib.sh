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

ISSUES_FIXTURE="$(printf 'Example/A\talice\t12 days ago\tIDoc import\thttps://github.com/example/a/issues/1\nexample/b\tbob\t3 days ago\tBP-Mapping\thttps://github.com/example/b/issues/2')"
GOALS_FIXTURE="$(printf 'active\tIDoc import fixed\texample/work-repo,example/second\t\nwaiting\tEDM skill released\texample/other\t2026-11-25\nwaiting\tLater thing\texample/later\t2026-12-01')"

test_write_fine() {
  ssf_write_fine "$TMP/fine" "$ISSUES_FIXTURE" "$GOALS_FIXTURE"
  assert_eq "fine list" "$(cat "$TMP/fine")" \
    "$(printf 'example/a\nexample/b\nexample/later\nexample/other\nexample/second\nexample/work-repo')"
}
test_write_summary() {
  ssf_write_summary "$TMP/summary" "$ISSUES_FIXTURE" "$GOALS_FIXTURE"
  assert_eq "summary" "$(cat "$TMP/summary")" \
    "$(printf 'Oldest open commitment: "IDoc import" requested by alice (12 days ago) in Example/A, https://github.com/example/a/issues/1\nTop active goal: "IDoc import fixed"')"
}
test_banner_full() {
  assert_eq "banner" "$(ssf_banner "$ISSUES_FIXTURE" "$GOALS_FIXTURE" 2026-11-25)" \
    "$(printf '⏳ Waiting on you: "IDoc import" (alice, 12 days ago), "BP-Mapping" (bob, 3 days ago)\n🎯 Active: IDoc import fixed · Waiting: EDM skill released (follow-up due), Later thing')"
}
test_banner_more_than_three_issues() {
  local many
  many="$(printf 'o/a\tu\t1 day ago\tT1\turl\no/b\tu\t1 day ago\tT2\turl\no/c\tu\t1 day ago\tT3\turl\no/d\tu\t1 day ago\tT4\turl\no/e\tu\t1 day ago\tT5\turl')"
  assert_contains "+N more" "$(ssf_banner "$many" "" 2026-11-25)" ', +2 more'
}
test_banner_no_active_goal() {
  assert_eq "no active" "$(ssf_banner "" "$(printf 'waiting\tW\to/r\t2026-12-01')" 2026-11-25)" \
    "🎯 Active: none · Waiting: W"
}
test_cleanup_old() {
  local s="$TMP/state"
  mkdir -p "$s/banner-2026-11-20" "$s/banner-2026-11-25"
  : > "$s/fine-2026-11-20"
  : > "$s/fine-2026-11-25"
  ssf_cleanup_old "$s" 2026-11-25
  assert_eq "only today's files remain" "$(ls "$s" | tr '\n' ' ')" "banner-2026-11-25 fine-2026-11-25 "
}

test_read_goals_lenient_hand_edits() {
  goals <<'EOF2'
##Active
### Hand edited
* Repos: https://github.com/Foo/Bar.git, git@github.com:Baz/Qux.git, plain/one

## Waiting (parked)
### Parked
-  Follow-up: 2026-11-30
EOF2
  assert_eq "lenient parsing" "$(ssf_read_goals)" \
    "$(printf 'active\tHand edited\tfoo/bar,baz/qux,plain/one\t\nwaiting\tParked\t\t2026-11-30')"
}
test_with_timeout_fallback_kills_promptly() {
  export SSF_FORCE_FALLBACK=1
  local start=$SECONDS
  local out; out="$(ssf_with_timeout 1 bash -c 'sleep 5; echo late')"
  assert_eq "fallback returns within ~2s" "$(( SECONDS - start <= 2 ))" "1"
  unset SSF_FORCE_FALLBACK
}
