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
