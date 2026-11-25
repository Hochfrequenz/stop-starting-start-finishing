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
