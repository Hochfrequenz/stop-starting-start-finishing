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
