# stop-starting-start-finishing — Design (v1)

"Stop starting, start finishing": a Claude Code plugin that reminds people to finish committed work before starting new things elsewhere.

## Problem

With several Claude Code sessions open at once and frequent interruptions, it is easy to start new work whenever an opportunity or a request comes up, and to lose track of work that was already started. Unfinished work then stalls, often while someone else is waiting for it.

Because the people waiting are often the ones who notice the delay first, v1 lets them record the commitment from outside (a GitHub issue), and keeps upkeep for the person doing the work near zero.

## Scope

**In v1**

1. Inbound commitments via GitHub issues labelled `blocks-someone`.
2. Personal goals in `~/.claude/focus/goals.md` (Active, max N; Waiting).
3. `SessionStart` hook: one banner per day.
4. `UserPromptSubmit` hook: at most one nudge line per repo per day.
5. Skill `focus` (invoked as `/focus`): add, park, done, list.

**Not in v1:** session-ID links, path-based repo matching, inferred blocks, done detection from plan files or GitHub queries, temporary N+1 handling, exception log, bootstrapping goals from old sessions, team dashboard, PowerShell hooks, success metrics.

## Distribution and requirements

- Repo `Hochfrequenz/stop-starting-start-finishing`, plugin name `stop-starting-start-finishing`, added to `.claude-plugin/marketplace.json` in hf-skills and documented in the README.
- Requires bash: Git for Windows on Windows (hooks run in Git Bash), system shell on macOS/Linux. Hooks use `"shell": "bash"` and quote `"${CLAUDE_PLUGIN_ROOT}"`.
- No Python, Node or jq.
- `gh` (authenticated) is optional. Without it, everything related to `blocks-someone` is skipped silently.

## 1. Inbound commitments (`blocks-someone`)

- A requester creates a GitHub issue, assigns it to the person who will do the work and adds the label `blocks-someone`. The issue *is* the commitment; the assignee does not need to record it anywhere.
- Fetch: `gh search issues --assignee=@me --label=blocks-someone --state=open --json title,url,createdAt,author,repository` formatted with `gh`'s built-in `--template` (no jq).
- Waiting age is rendered by `gh` itself with `{{timeago .createdAt}}` (e.g. "12 days ago"), so no date arithmetic in bash (BSD `date` on macOS has no `-d`). Requester = issue `author`.
- Sorted oldest first server-side: `--sort created --order asc`.

## 2. Personal goals file

Path: `~/.claude/focus/goals.md`. Written by the skill, editable by hand. The format is strict so that the hooks can read it with `sed`/`grep`.

```markdown
wip-limit: 2

## Active
### IDoc import fixed
- repos: Hochfrequenz/edm-foo
- done-when: customer imports without errors
- resume: next step is the mapping for segment E1EDP01

## Waiting
### EDM skill released
- repos: Hochfrequenz/hf-skills
- waiting-for: review by alice
- follow-up: 2026-11-28
- resume: address review comments, then release
```

Rules:

- Only `## Active` and `## Waiting` sections exist. Order within a section is rank. No numbering.
- `wip-limit` defaults to 2 if missing.
- `repos` is a comma-separated list of `owner/repo` (normalized, see §5).
- A goal may only move to Waiting with both `waiting-for` (named person or event) and `follow-up` (ISO date). "Stuck" without a named dependency stays Active.
- Waiting goals do not count toward `wip-limit`.
- When a goal moves back to Active, its `waiting-for` and `follow-up` lines are removed.
- Done goals are removed from the file (no archive in v1).
- Hooks must tolerate CRLF line endings and a UTF-8 BOM.

## 3. Hook: SessionStart (daily banner)

Steps:

1. Exit 0 silently if `FOCUS_DISABLE=1` (for automated sessions such as `/loop` and headless runs).
2. Exit 0 silently if the marker `~/.claude/focus/.state/banner-<YYYY-MM-DD>` exists. Claim it atomically with `mkdir` (several sessions may start at the same moment); if `mkdir` fails, exit 0 silently.
3. Fetch `blocks-someone` issues (if `gh` is available). The hook has an explicit `"timeout": 20` in `hooks.json`; if `gh` fails or is slow, continue without issues. If the hook fails before printing the banner, it removes the marker so the next session can retry.
4. Read Active and Waiting goals from `goals.md` (if present).
5. If both are empty: exit 0 silently.
6. Write two state files for the day:
   - `~/.claude/focus/.state/fine-<YYYY-MM-DD>`: one normalized `owner/repo` per line, repos of Active goals, Waiting goals and `blocks-someone` issues. (Working on a Waiting goal, e.g. answering its review, is not new work.)
   - `~/.claude/focus/.state/summary-<YYYY-MM-DD>`: the top `blocks-someone` issue (title, requester, age, URL) and the top Active goal (title), used by the nudge.
   Both are refreshed once per day, when the banner runs. Goals added later that day only take effect the next day, unless the skill rewrites the fine file after editing `goals.md` (see §6).
7. Print JSON `{"systemMessage": "<banner>"}` so the user sees it immediately. Escape `\`, `"` and newlines with `sed`.

Banner (at most 2 lines; each line is omitted when empty; issue titles are cut to 40 characters by `gh`, goal titles are limited to 40 characters by the skill when it writes them):

```
⏳ Waiting on you: "IDoc import" (alice, 12 days ago), "BP-Mapping" (bob, 3 days ago)
🎯 Active: IDoc import fixed · Waiting: EDM skill (follow-up today)
```

- The `blocks-someone` line comes first and lists at most 3 issues, then "+N more".
- Waiting goals whose `follow-up` date is today or earlier are marked "follow-up due".
- Old marker and cache files (not today's) are deleted.

Note: hook stdout and `systemMessage` are capped at 10,000 characters. The banner lists at most 3 issues and the goals (bounded by `wip-limit` plus Waiting goals), so it stays far below that.

## 4. Hook: UserPromptSubmit (daily nudge)

Steps (only file tests, no `gh`, so it stays fast):

1. Exit 0 silently if `FOCUS_DISABLE=1`.
2. Determine the current repo from the git remote of the working directory (§5). If none: exit 0 silently.
3. Exit 0 silently if the repo appears in today's `fine-<date>` file, or if that file doesn't exist (no banner ran, so nothing to nudge about).
4. Exit 0 silently if the marker `~/.claude/focus/.state/nudge-<date>-<owner_repo>` exists. Otherwise create it.
5. Print plain text context for Claude:

   > stop-starting: This repo is not part of the user's active goals, and they have open commitments (listed below). If this prompt was typed by the user and starts new work (not a question or lookup), begin your reply with exactly one short line naming the most important open commitment (oldest `blocks-someone` issue first, otherwise the top Active goal), then continue with the request normally. Do not ask questions about it. Ignore this for subagent reports, scheduled tasks and messages from other sessions.

   The context includes the top `blocks-someone` issue and the top Active goal, read from a small summary file written by the SessionStart hook.

When reading the fine file, the hook strips `\r` and ignores empty lines.

Known limitation: the marker is set at the first prompt of the day in that repo. A quick question, a subagent report, a scheduled task or a message from another session as the first prompt uses up the day's nudge.

## 5. Shared hook rules

- **stdin:** read only `session_id` if needed, via an anchored UUID regex. Never parse `prompt` or `cwd` from the JSON. Take the working directory from the process cwd or `CLAUDE_PROJECT_DIR`.
- **Repo normalization:** `git remote get-url origin` → strip credentials (`https://user:token@…`), protocol, `git@host:`, `.git` suffix; take the last two path segments as `owner/repo`; lowercase. Never print raw remote URLs.
- **Errors:** every failure path exits 0 with no output. The hooks must never block a session.
- **State directory:** `~/.claude/focus/.state/`, created by the hooks as needed. The hooks write the marker files, so the nudge never triggers a permission prompt. The only write by Claude inside `.state/` is the `fine-<date>` append during user-initiated `/focus` actions (§6).

## 6. Skill: `focus`

Location: `skills/focus/SKILL.md`. Plugin skills are namespaced, so the full command is `/stop-starting-start-finishing:focus`; the README documents both that and the short `/focus` where Claude Code accepts it (verify during implementation). The skill also triggers on natural language ("park this goal", "what am I working on?").

One entry point, natural language for everything else.

- **Add a goal:** ask for the outcome (not a task), the done criterion (`done-when`) and the repos. If Active is full (≥ `wip-limit`), ask which Active goal to park or put the new goal in Waiting.
- **Park a goal:** move it to Waiting. Requires `waiting-for` and `follow-up`. Asks for a one-line `resume` note.
- **Unpark:** move it back to Active (if Active is full, ask which goal to park).
- **Done:** confirm with the user and remove the goal. Leftovers can be added as a new goal.
- **List:** show the `blocks-someone` issues (via `gh`), Active and Waiting goals, and due follow-ups.
- **Nudge behaviour:** documents the one-line nudge from §4 so the behaviour is the same with or without the hook context.

After adding a goal, the skill appends its repos to today's `fine-<date>` file (if it exists) via Bash with `printf '%s\n' … >>`, so a freshly added goal stops the nudge the same day.

The skill edits `goals.md` with the normal file tools. Since the file is outside the project, Claude Code may ask for permission; that is acceptable for user-initiated `/focus` actions.

## 7. Testing

- `tests/run.sh`: plain bash, no framework. Feeds fixture stdin JSON and fixture `goals.md` files to each hook with a temporary `HOME` and a stub `gh` on `PATH`, and compares stdout and created state files with expected output.
- Cases: no `goals.md`; no `gh`; empty results; CRLF and BOM in `goals.md`; no remote; ssh, https and credential-bearing remotes; `FOCUS_DISABLE=1`; second call on the same day (banner and nudge markers); repo in fine list vs not; special characters (`"`, `\`, umlauts) in issue titles for JSON escaping; follow-up date due vs not; concurrent banner runs (only one prints); `gh` failing or hanging (banner still shows goals).
- Manual checklist for a real Windows session: banner appears at start, appears once per day, nudge appears once per repo per day, `/focus` add/park/done works, nothing appears with `FOCUS_DISABLE=1`.
