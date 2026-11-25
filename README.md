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
