---
name: focus
description: Manage the user's focus goals in ~/.claude/focus/goals.md (stop starting, start finishing). Use when the user runs /focus, asks what they are working on or what is waiting on them, wants to add, park, unpark or finish a goal, or says a goal is blocked or done.
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

Only when a `stop-starting:` hook message is in your context (the hook already limits this to once per repo per day):

- Start your reply with exactly **one** short line naming the most important open commitment (oldest `blocks-someone` issue first, otherwise the top Active goal). Example: `⏳ Reminder: "IDoc import" has been waiting on you for 12 days (alice).`
- Then do what the user asked, normally. Do not ask questions about it, do not repeat it later in the session.
- Never nudge for questions or lookups, and never for subagent reports, scheduled tasks or messages from other sessions.

## Opting out

Automated sessions (e.g. `/loop`, headless runs) should set `FOCUS_DISABLE=1`; the hooks are then silent.
