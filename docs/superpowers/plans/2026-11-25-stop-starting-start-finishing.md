# stop-starting-start-finishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v1 Claude Code plugin from `docs/superpowers/specs/2026-11-25-stop-starting-start-finishing-design.md`: a daily focus banner, a once-per-repo-per-day nudge, and a `focus` skill for managing goals.

**Architecture:** Two bash hooks (`SessionStart`, `UserPromptSubmit`) share helper functions in `hooks/lib.sh`. The SessionStart hook reads `~/.claude/focus/goals.md` and the user's `blocks-someone` GitHub issues (via `gh`), shows a banner as `systemMessage`, and writes daily cache files to `~/.claude/focus/.state/`. The UserPromptSubmit hook only reads those cache files (no network) and injects a one-line-nudge instruction. All goal editing is done by Claude through the `focus` skill.

**Tech Stack:** bash (Git Bash on Windows), git, awk, sed, tr, grep, `gh` CLI (optional). No Python, Node or jq. Tests are plain bash.

**Spec:** `docs/superpowers/specs/2026-11-25-stop-starting-start-finishing-design.md` — read it before starting.

---

## Verified facts (do not re-research)

- Hooks run via Git Bash on Windows when `"shell": "bash"`; `${CLAUDE_PLUGIN_ROOT}` is expanded in hook commands.
- Plain stdout of `UserPromptSubmit` is added to Claude's context. JSON `{"systemMessage": "..."}` on stdout is shown to the user. Output cap: 10,000 characters.
- `SessionStart` fires on startup, resume, clear and compact. Default `UserPromptSubmit` timeout is 30 s; set explicit timeouts.
- `gh search issues ... --json title,url,createdAt,author,repository --template '...'` works without jq. The template functions `timeago` and `truncate` exist; `{{"\t"}}` emits a tab. Verified output line:
  `Hochfrequenz/prozessorBackend<TAB>hf-kklein<TAB>9 years ago<TAB>Bedingungen: Referenz auf vorausgegan...<TAB>https://github.com/Hochfrequenz/prozessorBackend/issues/11`
- In Git Bash, `${var:0:n}` slices **bytes**, not characters, so never truncate user text in bash. Issue titles are truncated by `gh` (`truncate 40`); goal titles are limited to 40 characters by the skill when it writes them.
- `timeout` exists in Git Bash and Linux but not on stock macOS; code must work without it.
- **Never combine `grep -i` with `-F`**: GNU grep 3.0 in Git Bash aborts (exit 134) and writes a `grep.exe.stackdump` into the current directory. Lowercase the input with `tr` instead.
- `claude --plugin-dir <path>` loads a plugin from a directory for manual testing.

## File structure

| File | Responsibility |
|---|---|
| `.gitattributes` | Force LF line endings (bash breaks on CRLF scripts). |
| `.claude-plugin/plugin.json` | Plugin manifest. |
| `hooks/hooks.json` | Registers both hooks with `shell: bash` and timeouts. |
| `hooks/lib.sh` | All logic as small functions: paths, remote normalization, goals parsing, issue fetch, JSON escaping, cache writing, banner text, cleanup. Sourced by hooks and tests. |
| `hooks/session-start.sh` | Orchestrates the daily banner (thin; calls lib.sh). |
| `hooks/user-prompt-submit.sh` | Orchestrates the nudge (thin; calls lib.sh). |
| `skills/focus/SKILL.md` | The `focus` skill: goal management dialogues, file format, nudge behaviour. |
| `tests/run.sh` | Test runner: discovers `test_*` functions, fresh temp `HOME` per test. |
| `tests/stub/gh` | Fake `gh` controlled by env vars. |
| `tests/test_lib.sh` | Unit tests for lib.sh. |
| `tests/test_session_start.sh` | Tests for the SessionStart hook. |
| `tests/test_user_prompt_submit.sh` | Tests for the UserPromptSubmit hook. |
| `README.md` | Install, usage, requirements, manual test checklist. |

Test hooks inject these environment variables (never set by Claude Code): `SSF_TODAY` (fixed date), `SSF_GH` (path to gh), `SSF_GH_TIMEOUT` (seconds).

All commands below are run from the repo root `C:\github\stop-starting-start-finishing` in Git Bash.

---

### Task 1: Scaffold, manifest and test runner

**Files:**
- Create: `.gitattributes`, `.claude-plugin/plugin.json`, `hooks/hooks.json`, `tests/run.sh`, `tests/stub/gh`

- [ ] **Step 1: Create `.gitattributes`**

```
* text=auto eol=lf
```

- [ ] **Step 2: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "stop-starting-start-finishing",
  "description": "Stop starting, start finishing: a daily banner with the work people are waiting on you for, and a gentle nudge when you start something new elsewhere.",
  "version": "0.1.0",
  "author": {
    "name": "Hochfrequenz"
  },
  "homepage": "https://github.com/Hochfrequenz/stop-starting-start-finishing",
  "repository": "https://github.com/Hochfrequenz/stop-starting-start-finishing",
  "keywords": ["focus", "wip-limit", "kanban", "productivity"]
}
```

- [ ] **Step 3: Create `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/session-start.sh",
            "shell": "bash",
            "timeout": 20
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/user-prompt-submit.sh",
            "shell": "bash",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

No `matcher` on SessionStart: it should run for every source; the once-per-day marker prevents repeats.

- [ ] **Step 4: Create `tests/stub/gh`**

```bash
#!/usr/bin/env bash
# Fake gh for tests. Behaviour is controlled by environment variables:
#   GH_STUB_SLEEP  seconds to sleep before answering (default 0)
#   GH_STUB_OUTPUT text printed on stdout (default empty)
#   GH_STUB_EXIT   exit code (default 0)
if [ "${GH_STUB_SLEEP:-0}" != "0" ]; then sleep "$GH_STUB_SLEEP"; fi
printf '%s' "${GH_STUB_OUTPUT:-}"
exit "${GH_STUB_EXIT:-0}"
```

- [ ] **Step 5: Create `tests/run.sh`**

```bash
#!/usr/bin/env bash
# Plain-bash test runner. Usage: bash tests/run.sh
# Each tests/test_*.sh file defines functions named test_*. Every test runs
# with a fresh temporary HOME and a git repo in $REPO.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
CURRENT=""

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/focus"
  export SSF_TODAY="2026-11-25"
  export SSF_GH="$ROOT/tests/stub/gh"
  export SSF_GH_TIMEOUT=15
  export GH_STUB_OUTPUT="" GH_STUB_EXIT=0 GH_STUB_SLEEP=0
  unset FOCUS_DISABLE CLAUDE_PROJECT_DIR
  REPO="$TMP/repo"
  git init -q "$REPO"
  git -C "$REPO" remote add origin "https://github.com/Example/Work-Repo.git"
}

teardown() { rm -rf "$TMP"; }

# assert_eq <description> <actual> <expected>
assert_eq() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL [%s] %s\n  expected: %q\n  actual:   %q\n' "$CURRENT" "$1" "$3" "$2"
  fi
}

# assert_contains <description> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      printf 'FAIL [%s] %s\n  missing: %s\n  in:      %s\n' "$CURRENT" "$1" "$3" "$2"
      ;;
  esac
}

# Write ~/.claude/focus/goals.md from stdin.
goals() { cat > "$HOME/.claude/focus/goals.md"; }

# Run hook <name> (session-start | user-prompt-submit) from inside $REPO.
run_hook() { (cd "$REPO" && printf '{"session_id":"x"}' | bash "$ROOT/hooks/$1.sh"); }

STATE() { printf '%s\n' "$HOME/.claude/focus/.state"; }

if [ -f "$ROOT/hooks/lib.sh" ]; then . "$ROOT/hooks/lib.sh"; fi
for f in "$ROOT"/tests/test_*.sh; do
  [ -e "$f" ] && . "$f"
done

for t in $(declare -F | awk '{ print $3 }' | grep '^test_'); do
  CURRENT="$t"
  setup
  "$t"
  teardown
done

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 6: Run the runner**

Run: `bash tests/run.sh`
Expected: `0 passed, 0 failed`, exit code 0.

- [ ] **Step 7: Commit (with executable bits for non-Windows users)**

```bash
chmod +x tests/run.sh tests/stub/gh
git add .gitattributes .claude-plugin/plugin.json hooks/hooks.json tests/run.sh tests/stub/gh
git update-index --chmod=+x tests/run.sh tests/stub/gh
git commit -m "chore: scaffold plugin manifest, hooks config and test runner"
```

---

### Task 2: Remote normalization and current repo

**Files:**
- Create: `hooks/lib.sh`
- Test: `tests/test_lib.sh`

- [ ] **Step 1: Write the failing tests** in `tests/test_lib.sh`

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL lines (`ssf_normalize_remote: command not found`), non-zero exit.

- [ ] **Step 3: Create `hooks/lib.sh` with the path helpers and normalization**

```bash
#!/usr/bin/env bash
# Shared helpers for the stop-starting-start-finishing hooks.
# Sourced by hooks/*.sh and tests/run.sh. Uses only bash, git, awk, sed, tr, grep.
# Test-only overrides: SSF_TODAY, SSF_GH, SSF_GH_TIMEOUT.

# Directory holding goals.md.
ssf_dir() { printf '%s\n' "$HOME/.claude/focus"; }

# Directory for markers and daily cache files. Only hooks write here,
# except the skill appending to fine-<date>.
ssf_state_dir() { printf '%s\n' "$HOME/.claude/focus/.state"; }

# Today's date as YYYY-MM-DD.
ssf_today() { printf '%s\n' "${SSF_TODAY:-$(date +%Y-%m-%d)}"; }

# Turn a git remote URL into lowercase "owner/repo" (its last two path
# segments). Strips protocol, credentials, scp-style "host:" and ".git".
# Prints nothing if the URL has fewer than two path segments.
ssf_normalize_remote() {
  local url="$1" rest owner repo slash="/"
  url="${url%%$'\r'}"
  url="${url%/}"
  url="${url%.git}"
  url="${url#*://}"
  url="${url#*@}"
  url="${url/:/$slash}"
  repo="${url##*/}"
  rest="${url%/*}"
  [ "$rest" = "$url" ] && return 0
  owner="${rest##*/}"
  [ -n "$owner" ] && [ -n "$repo" ] || return 0
  printf '%s/%s\n' "$owner" "$repo" | tr '[:upper:]' '[:lower:]'
}

# Normalized "owner/repo" of the origin remote of the project directory
# (CLAUDE_PROJECT_DIR, else the current directory). Empty if none.
ssf_current_repo() {
  local url
  url="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null)" || return 0
  ssf_normalize_remote "$url"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib.sh tests/test_lib.sh
git commit -m "feat: normalize git remotes to owner/repo"
```

---

### Task 3: Goals parsing

**Files:**
- Modify: `hooks/lib.sh` (append)
- Test: `tests/test_lib.sh` (append)

`ssf_read_goals` prints one line per goal in `## Active` or `## Waiting`: `section<TAB>title<TAB>repos<TAB>follow-up`, where `section` is `active` or `waiting`, `repos` is lowercase and comma-separated without spaces, and `follow-up` may be empty.

- [ ] **Step 1: Append failing tests to `tests/test_lib.sh`**

```bash
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
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/run.sh`
Expected: FAIL lines for `test_read_goals_sections` and `test_read_goals_crlf_and_bom` (`ssf_read_goals: command not found`). `test_read_goals_missing_file` passes vacuously at this point; that is expected.

- [ ] **Step 3: Append to `hooks/lib.sh`**

```bash
# Print the goals from goals.md, one per line:
#   section<TAB>title<TAB>repos<TAB>follow-up
# section is "active" or "waiting"; other sections are ignored. repos is
# lowercase, comma-separated, without spaces. Tolerates CRLF and a UTF-8 BOM.
ssf_read_goals() {
  local f bom
  f="$(ssf_dir)/goals.md"
  [ -f "$f" ] || return 0
  bom="$(printf '\357\273\277')"
  LC_ALL=C awk -v bom="$bom" '
    function flush() {
      if (title != "" && (sec == "active" || sec == "waiting"))
        printf "%s\t%s\t%s\t%s\n", sec, title, repos, fu
      title = ""; repos = ""; fu = ""
    }
    { sub(/\r$/, "") }
    NR == 1 && index($0, bom) == 1 { $0 = substr($0, 4) }
    /^## / { flush(); sec = tolower($0); sub(/^## */, "", sec); sub(/ *$/, "", sec); next }
    /^### / { flush(); title = $0; sub(/^### */, "", title); sub(/ *$/, "", title); next }
    title != "" && /^- repos:/ { repos = substr($0, index($0, ":") + 1); gsub(/[ \t]/, "", repos); repos = tolower(repos); next }
    title != "" && /^- follow-up:/ { fu = substr($0, index($0, ":") + 1); gsub(/[ \t]/, "", fu); next }
    END { flush() }
  ' "$f"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `12 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib.sh tests/test_lib.sh
git commit -m "feat: parse active and waiting goals from goals.md"
```

---

### Task 4: JSON escaping and issue fetch

**Files:**
- Modify: `hooks/lib.sh` (append)
- Test: `tests/test_lib.sh` (append)

`ssf_fetch_issues` prints `repo<TAB>author<TAB>age<TAB>title<TAB>url` per issue, oldest first, or nothing if `gh` is missing, fails, or exceeds the timeout.

- [ ] **Step 1: Append failing tests to `tests/test_lib.sh`**

```bash
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
```

Notes:
- When `gh` fails, partial output must be discarded, so `ssf_fetch_issues` buffers the output and prints it only on success.
- The timeout tests take about 3 seconds each: the stub's `sleep` keeps the pipe open after the stub is killed.

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/run.sh`
Expected: FAIL lines for `test_json_escape`, `test_fetch_issues_passthrough` and `test_with_timeout_fallback_passes_output`. The tests expecting empty output pass vacuously while the functions are missing; that is expected.

- [ ] **Step 3: Append to `hooks/lib.sh`**

```bash
# Escape stdin for use inside a JSON string (without surrounding quotes).
# Drops CR, turns tabs into spaces and newlines into \n.
ssf_json_escape() {
  tr -d '\r' | tr '\t' ' ' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

# Run "$@" with a time limit in seconds. Uses `timeout` where it exists;
# otherwise (stock macOS) runs the command in the background and kills it
# after the limit. Returns 124 on timeout. SSF_FORCE_FALLBACK=1 forces the
# fallback (tests).
ssf_with_timeout() {
  local secs="$1" pid ticks=0
  shift
  if [ -z "${SSF_FORCE_FALLBACK:-}" ] && command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return
  fi
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge $((secs * 5)) ]; then
      kill "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.2
    ticks=$((ticks + 1))
  done
  wait "$pid"
}

# Print open issues assigned to the user with label blocks-someone, oldest
# first, one per line: repo<TAB>author<TAB>age<TAB>title<TAB>url.
# Titles are cut to 40 characters by gh. Prints nothing if gh is missing,
# fails or is too slow.
ssf_fetch_issues() {
  local gh="${SSF_GH:-gh}" out
  command -v "$gh" >/dev/null 2>&1 || return 0
  out="$(ssf_with_timeout "${SSF_GH_TIMEOUT:-15}" "$gh" search issues \
    --assignee=@me --label=blocks-someone --state=open \
    --sort created --order asc --limit 50 \
    --json title,url,createdAt,author,repository \
    --template '{{range .}}{{.repository.nameWithOwner}}{{"\t"}}{{.author.login}}{{"\t"}}{{timeago .createdAt}}{{"\t"}}{{truncate 40 .title}}{{"\t"}}{{.url}}{{"\n"}}{{end}}' \
    2>/dev/null)" || return 0
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `19 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib.sh tests/test_lib.sh
git commit -m "feat: fetch blocks-someone issues via gh and escape JSON"
```

---

### Task 5: Daily cache files, banner text and cleanup

**Files:**
- Modify: `hooks/lib.sh` (append)
- Test: `tests/test_lib.sh` (append)

- [ ] **Step 1: Append failing tests to `tests/test_lib.sh`**

```bash
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
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/run.sh`
Expected: FAIL lines for all six new tests.

- [ ] **Step 3: Append to `hooks/lib.sh`**

```bash
# Write the day's "fine" repos (no nudge there): repos of all goals and of
# all issues, lowercase, one per line, sorted, unique.
# Args: <out file> <issues> <goals>
ssf_write_fine() {
  local out="$1" issues="$2" goals="$3"
  {
    [ -n "$goals" ] && printf '%s\n' "$goals" | cut -f3 | tr ',' '\n'
    [ -n "$issues" ] && printf '%s\n' "$issues" | cut -f1 | tr '[:upper:]' '[:lower:]'
  } | grep -v '^$' | LC_ALL=C sort -u > "$out"
}

# Write the text the nudge shows Claude: the oldest issue and the top
# active goal. Args: <out file> <issues> <goals>
ssf_write_summary() {
  local out="$1" issues="$2" goals="$3" top_goal
  top_goal="$(printf '%s\n' "$goals" | awk -F '\t' '$1 == "active" { print $2; exit }')"
  {
    if [ -n "$issues" ]; then
      printf '%s\n' "$issues" | head -n 1 | awk -F '\t' \
        '{ printf "Oldest open commitment: \"%s\" requested by %s (%s) in %s, %s\n", $4, $2, $3, $1, $5 }'
    fi
    if [ -n "$top_goal" ]; then
      printf 'Top active goal: "%s"\n' "$top_goal"
    fi
  } > "$out"
}

# Print the banner (at most 2 lines; a line is left out when it has nothing
# to show). Args: <issues> <goals> <today>
ssf_banner() {
  local issues="$1" goals="$2" today="$3"
  if [ -n "$issues" ]; then
    printf '%s\n' "$issues" | awk -F '\t' '
      NR <= 3 { line = line (NR > 1 ? ", " : "") "\"" $4 "\" (" $2 ", " $3 ")" }
      END { if (NR > 3) line = line ", +" (NR - 3) " more"; print "⏳ Waiting on you: " line }'
  fi
  if [ -n "$goals" ]; then
    printf '%s\n' "$goals" | awk -F '\t' -v today="$today" '
      $1 == "active" { act = act (act != "" ? ", " : "") $2 }
      $1 == "waiting" {
        w = $2
        if ($4 != "" && $4 <= today) w = w " (follow-up due)"
        wait = wait (wait != "" ? ", " : "") w
      }
      END {
        line = "🎯 Active: " (act != "" ? act : "none")
        if (wait != "") line = line " · Waiting: " wait
        print line
      }'
  fi
}

# Delete markers and cache files that are not from today.
# Args: <state dir> <today>
ssf_cleanup_old() {
  local state="$1" today="$2" f
  for f in "$state"/*; do
    [ -e "$f" ] || continue
    case "$f" in
      *"$today"*) ;;
      *) rm -rf "$f" ;;
    esac
  done
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `25 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib.sh tests/test_lib.sh
git commit -m "feat: daily fine list, summary, banner text and cleanup"
```

---

### Task 6: SessionStart hook

**Files:**
- Create: `hooks/session-start.sh`
- Test: `tests/test_session_start.sh`

- [ ] **Step 1: Write the failing tests** in `tests/test_session_start.sh`

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL lines for the `test_ss_*` tests (`hooks/session-start.sh: No such file or directory`).

- [ ] **Step 3: Create `hooks/session-start.sh`**

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `39 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
chmod +x hooks/session-start.sh
git add hooks/session-start.sh tests/test_session_start.sh
git update-index --chmod=+x hooks/session-start.sh
git commit -m "feat: SessionStart hook with daily focus banner"
```

---

### Task 7: UserPromptSubmit hook

**Files:**
- Create: `hooks/user-prompt-submit.sh`
- Test: `tests/test_user_prompt_submit.sh`

- [ ] **Step 1: Write the failing tests** in `tests/test_user_prompt_submit.sh`

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL lines for `test_ups_nudges_once` (the others pass vacuously because the missing script prints nothing to stdout — that's acceptable, the key test fails).

- [ ] **Step 3: Create `hooks/user-prompt-submit.sh`**

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `48 passed, 0 failed`. Afterwards, check that no `grep.exe.stackdump` file was created anywhere in the repo (`git status --short` shows nothing untracked).

- [ ] **Step 5: Commit**

```bash
chmod +x hooks/user-prompt-submit.sh
git add hooks/user-prompt-submit.sh tests/test_user_prompt_submit.sh
git update-index --chmod=+x hooks/user-prompt-submit.sh
git commit -m "feat: UserPromptSubmit hook with once-per-repo-per-day nudge"
```

---

### Task 8: The `focus` skill

**Files:**
- Create: `skills/focus/SKILL.md`

- [ ] **Step 1: Create `skills/focus/SKILL.md`**

````markdown
---
name: focus
description: Manage the user's focus goals in ~/.claude/focus/goals.md (stop starting, start finishing). Use when the user runs /focus, asks what they are working on or what is waiting on them, wants to add, park, unpark or finish a goal, says a goal is blocked or done, or when a stop-starting hook message asks for a nudge.
---

# Focus: stop starting, start finishing

The user keeps a small set of goals in `~/.claude/focus/goals.md`. Other people can also put commitments on them: open GitHub issues assigned to the user with the label `blocks-someone`. Your job is to help them finish committed work before starting new things, without nagging.

## Goals file format

The hooks parse this file with simple tools, so keep the format exactly:

```markdown
wip-limit: 2

## Active
### IDoc import fixed
- repos: hochfrequenz/edm-foo
- done-when: customer imports without errors
- resume: next step is the mapping for segment E1EDP01

## Waiting
### EDM skill released
- repos: hochfrequenz/hf-skills
- waiting-for: review by alice
- follow-up: 2026-11-28
- resume: address review comments, then release
```

Rules:

- Only two sections: `## Active` and `## Waiting`. Order within a section is priority. No numbering.
- Titles (`### …`) are outcomes, not tasks, and at most 40 characters.
- `repos:` is a comma-separated list of lowercase `owner/repo`. Derive it from `git remote get-url origin`: drop protocol, credentials, host and `.git`, keep the last two path segments, lowercase.
- `wip-limit` defaults to 2. Waiting goals do not count toward it.
- A goal may only be in Waiting with both `waiting-for` (a named person or event) and `follow-up` (YYYY-MM-DD). "Stuck" without a named dependency stays Active.
- Create the file (and `~/.claude/focus/`) when the first goal is added.

## Actions

**List** (`/focus` without arguments, or "what am I working on?"):
1. If `gh` is available, run
   `gh search issues --assignee=@me --label=blocks-someone --state=open --sort created --order asc --json title,url,createdAt,author,repository`
   and show who is waiting on what, oldest first.
2. Show Active goals, then Waiting goals, marking follow-ups due today or earlier.
3. Keep it short. No advice unless asked.

**Add a goal:**
1. Ask for the outcome (not a task), what counts as done (`done-when`) and the repos (offer the current repo).
2. If Active has fewer goals than `wip-limit`, add it to Active (at the end, unless the user ranks it higher).
3. Otherwise ask: park an Active goal (see Park), or put the new goal in Waiting? Never exceed the limit silently.
4. After writing the file, if `~/.claude/focus/.state/fine-<today>` exists, append each new repo with Bash, e.g.
   `printf '%s\n' owner/repo >> ~/.claude/focus/.state/fine-2026-11-25`
   so the nudge stops for that repo today. Do not edit anything else in `.state/`.

**Park a goal** (move Active → Waiting): require `waiting-for` and `follow-up`; ask for a one-line `resume` note (where to pick up). If the user has no named dependency, say plainly that the goal stays Active.

**Unpark** (Waiting → Active): remove its `waiting-for` and `follow-up` lines. If Active is full, ask which goal to park.

**Done:** confirm with the user, then remove the goal from the file. If there are leftovers, offer to add them as a new goal.

## The nudge

When a `stop-starting:` hook message is in your context, or you notice the user starting new work in a repo that is not in their goals while something is waiting on them:

- Start your reply with exactly **one** short line naming the most important open commitment (oldest `blocks-someone` issue first, otherwise the top Active goal). Example: `⏳ Reminder: "IDoc import" has been waiting on you for 12 days (alice).`
- Then do what the user asked, normally. Do not ask questions about it, do not repeat it later in the session.
- Never nudge for questions or lookups, and never for subagent reports, scheduled tasks or messages from other sessions.

## Opting out

Automated sessions (e.g. `/loop`, headless runs) should set `FOCUS_DISABLE=1`; the hooks are then silent.
````

- [ ] **Step 2: Check the skill loads**

Run: `claude plugin validate .` (if the subcommand exists in the installed version; otherwise skip this step and rely on Task 10).
Expected: no errors for `skills/focus/SKILL.md`, `hooks/hooks.json`, `.claude-plugin/plugin.json`.

- [ ] **Step 3: Commit**

```bash
git add skills/focus/SKILL.md
git commit -m "feat: focus skill for managing goals and the nudge"
```

---

### Task 9: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

````markdown
# stop-starting-start-finishing

A Claude Code plugin for "stop starting, start finishing". It keeps the work you committed to in view and gently reminds you before you start something new elsewhere.

## What it does

- **Daily banner** (first session of the day): who is waiting on you, and your active goals.
  ```
  ⏳ Waiting on you: "IDoc import" (alice, 12 days ago), "BP-Mapping" (bob, 3 days ago)
  🎯 Active: IDoc import fixed · Waiting: EDM skill released (follow-up due)
  ```
- **Nudge** (at most once per repo per day): when you start new work in a repo that is not part of your goals, Claude opens its reply with one line about your most important open commitment, then does what you asked.
- **`focus` skill**: add, park, unpark, finish and list goals in plain language.

## Commitments from others

Anyone can put a commitment on you: create a GitHub issue, assign it to you and add the label **`blocks-someone`**. It shows up in your banner, oldest first. Close the issue when it's done.

## Install

```
/plugin marketplace add Hochfrequenz/hf-skills
/plugin install stop-starting-start-finishing@hf-skills
```

Requirements:
- **bash**: on Windows, Git for Windows (the hooks run in Git Bash). Without it, the plugin stays silent.
- **gh** (optional, logged in): needed for `blocks-someone` issues. Without it, only your own goals are shown.

## Usage

- `/stop-starting-start-finishing:focus` (or just ask: "what am I working on?", "add a goal", "park the IDoc goal until Friday, waiting for alice").
- Your goals live in `~/.claude/focus/goals.md`. You can edit it by hand; keep the format the skill uses.
- Set `FOCUS_DISABLE=1` for automated sessions (`/loop`, headless runs) to switch the hooks off.

## Development

Run the tests (Git Bash on Windows):

```
bash tests/run.sh
```

Manual check in a real session: `claude --plugin-dir .` then verify
1. the banner appears at the first session start of the day, and not again on the next session;
2. in a repo that is not in your goals, the first prompt that starts work gets a one-line reminder, the second one doesn't;
3. `/stop-starting-start-finishing:focus` can add, park, unpark and finish a goal;
4. with `FOCUS_DISABLE=1` nothing appears.

To reset the once-per-day state while testing, delete `~/.claude/focus/.state/`.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

### Task 10: Manual verification in a real session

**Files:** none (fix bugs in the files above if anything fails, with a test first where possible)

- [ ] **Step 1: Run the automated tests once more**

Run: `bash tests/run.sh`
Expected: `… passed, 0 failed`.

- [ ] **Step 2: Prepare a goals file and reset state**

```bash
mkdir -p ~/.claude/focus
rm -rf ~/.claude/focus/.state
```
If `~/.claude/focus/goals.md` does not exist yet, create one with a single Active goal whose `repos:` is `hochfrequenz/stop-starting-start-finishing`. Do not overwrite an existing file.

- [ ] **Step 3: Banner check**

Run `claude --plugin-dir .` from the repo root. Expected: the banner appears at the start. Exit, start again: no banner.

- [ ] **Step 4: Nudge check**

Start `claude --plugin-dir C:/github/stop-starting-start-finishing` from another repo that is not in the goals (e.g. `C:\github\hf-skills`). Type a prompt that starts work (e.g. "add a section to the README"; cancel before any edit is made). Expected: Claude's reply starts with one reminder line. Ask a second work prompt: no reminder.

- [ ] **Step 5: Skill check**

In a session: `/stop-starting-start-finishing:focus`, then add a goal, park it, unpark it, mark it done. Check `~/.claude/focus/goals.md` after each step against the format in the skill. Also try typing `/focus` and record whether the short form works; update README Usage accordingly.

- [ ] **Step 6: Opt-out check**

Run `FOCUS_DISABLE=1 claude --plugin-dir .` after deleting `~/.claude/focus/.state`. Expected: no banner, no nudge.

- [ ] **Step 7: Commit any fixes and push**

```bash
git push origin main
```
(If the org ruleset requires a pull request for `main`, push a branch `feat/v1` instead and open a PR with `gh pr create`.)

---

### Task 11: Register the plugin in hf-skills

**Files:**
- Modify: `C:\github\hf-skills\.claude-plugin\marketplace.json` (append to `plugins`)
- Modify: `C:\github\hf-skills\README.md` (Available skills section)

- [ ] **Step 1: Create a branch in hf-skills**

```bash
cd /c/github/hf-skills
git switch main && git pull
git switch -c feat/add-stop-starting-start-finishing
```

- [ ] **Step 2: Append the marketplace entry** after the last plugin object in `.claude-plugin/marketplace.json`

```json
    {
      "name": "stop-starting-start-finishing",
      "source": {
        "source": "url",
        "url": "https://github.com/Hochfrequenz/stop-starting-start-finishing.git"
      },
      "description": "Stop starting, start finishing: daily banner with work others are waiting on you for (GitHub label blocks-someone) and your focus goals, plus a one-line nudge when you start new work elsewhere",
      "version": "0.1.0",
      "strict": true
    }
```

- [ ] **Step 3: Add the plugin to the README's Available skills section**, following the format of the existing entries there (read the section first and copy its structure). The hf-skills CI check (`.github/workflows/pr-skill-checks.yml`) requires the README entry to contain both the plugin name `stop-starting-start-finishing` and the repository URL `https://github.com/Hochfrequenz/stop-starting-start-finishing`; read that workflow before writing the entry.

- [ ] **Step 4: Validate JSON**

Run: `git diff --stat && claude plugin validate .` (skip `validate` if unavailable; then at least check the file parses, e.g. by `/plugin marketplace add ./` in a test session).
Expected: no errors.

- [ ] **Step 5: Commit, push, open PR**

```bash
git add .claude-plugin/marketplace.json README.md
git commit -m "Add stop-starting-start-finishing to marketplace"
git push -u origin feat/add-stop-starting-start-finishing
gh pr create --title "Add stop-starting-start-finishing plugin" --body "Adds the stop-starting-start-finishing plugin (daily focus banner, blocks-someone commitments, once-per-day nudge, focus skill) to the marketplace."
```
