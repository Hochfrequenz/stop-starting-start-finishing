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
