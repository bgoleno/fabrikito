# How work is tracked

Two rules every seat follows, and what the launcher does to support them: every change starts as an
issue, and every seat keeps a progress note. Then how a security point found in a review is held on a
pull request until `sec` clears it.

## Issues first

Every change starts as an issue. The shared prompt (`roles/common.md`) makes this a hard rule for every
seat: no change starts without an issue, and the engineering manager files one when it is missing. A
pull request that completes its issue says `Closes #<n>`, and one that does not says `Refs #<n>` (see
`.github/pull_request_template.md`), so the issue closes exactly when its change lands and the board
stays honest.

## Progress notes

Each seat keeps a short progress note, `.state/<team>/notes/<role>.md`: its current task, branch,
state, next step and what it is waiting for. The shared prompt tells it to rewrite the note whenever
a task changes state and to work on one task at a time. The note is outside the worktree, so it
survives `down` and `up` and a recreated worktree; `up` only makes the folder, and nothing removes a
note.

Every seat's generated settings have a `SessionStart` hook (`lib/session_start.sh`, no matcher, so
it runs at startup, on resume, after `/clear` and after a compaction). It prints the note (cut at 80
lines or 6000 bytes), the branch, uncommitted files and the last 10 commits of the seat's working
directory, and Claude Code adds that to the seat's context. After the note it prints what to do with
it, on every path (no note, an unreadable note, a missing or non-git folder): name the task and next
step in the first reply, follow the kickoff, and trust the repository over the note. That text moved
here from the shared prompt ([#117](../../../issues/117)), so a seat whose hooks are all off goes without
it, as it goes without the note. The note is the seat's own writing, so treat it as a reminder, not
a record: when it and the repository disagree, the repository wins.

- Control characters other than tab and newline (and DEL) are dropped from everything the hook
  prints, so a terminal escape in a note or a commit subject arrives as plain text.
- `git status` and `git log` each have their own time limit (4s and 3s), well inside the hook's 10s,
  and a repository's fsmonitor program is not run. Claude Code drops all of a hook's output when the
  hook runs past its timeout, so a slow status on a cold volume costs the seat its file list, not its
  note.
- Each seat may edit only its own note: the others are denied (see [Safety](../README.md#safety)).
- The hook is a convenience, not a control, so it does not override a user who switched every hook
  off: with `disableAllHooks: true` in `~/.claude/settings.json`, a seat without a gate gets no note,
  and `check` prints a `hooks` line naming those seats.

## Held security points

A reviewer or QA seat that finds a security point does not write it on the pull request: only `sec`
rates a finding, and anyone who can read the repository can read a PR comment. The point goes to `sec`
and the engineering manager, and the PR gets a marker that holds its merge until `sec` clears it
([#184](../../../issues/184), [#203](../../../issues/203)). The skills hold the exact steps; this is
the shape of it:

- **The marker.** For each point, once, its reporter posts a PR comment whose whole text is one line,
  `<role id>: one point sent to sec and the EM`, and sends `sec` and the EM the point with the
  marker's URL. When `sec` sends a PR's author a change to make, its marker is
  `sec: one change sent to the author and the EM`. The same words inside a longer comment are not a
  marker.
- **The reference.** The reporter's verdict or QA report names the point only by a line of its own,
  `held point: <marker URL>`, with nothing about the point itself. A later verdict that still has the
  point repeats that line and posts no new marker.
- **The clearance.** Once a point is fixed and reviewed at a head, rated low, ruled out or (for code
  already on the base) tracked where its triage record says, `sec` posts
  `sec: held points for #<n> cleared at <short sha>: <comment id>, <comment id>`, naming each marker
  it clears by its comment id (the number after `issuecomment-` in its URL). It counts only at that
  head: a new commit needs a new clearance. Nothing else clears a hold, not a message and not a
  `READY` alone.
- **Markers stay.** No seat deletes or edits a marker, even one posted by mistake: `sec` checks that
  it is a mistake and clears it with the same line. Deleting a marker clears nothing. The merge train
  stops when a marker it saw earlier in the same run, or one that a verdict, QA report or clearance
  refers to, is gone or changed. It does not yet remember markers from one run to the next
  ([#207](../../../issues/207)).
- **Order is by id, never by time.** Where the merge train decides which comment is the latest, it
  compares comment ids or review ids, because GitHub can give a later comment an earlier time.

Where each part lives:

| Skill | What it holds |
|---|---|
| [`factory:review-pr`](../plugin/skills/review-pr/SKILL.md), step 7 | A reviewer's marker, its `held point:` line and a marker posted by mistake. |
| [`factory:verify-behavior`](../plugin/skills/verify-behavior/SKILL.md), step 8 | The same for QA's report. |
| [`factory:security-triage`](../plugin/skills/security-triage/SKILL.md), step 6 | `sec`'s own marker, and the clearance line. |
| [`factory:merge-train`](../plugin/skills/merge-train/SKILL.md), step 5 | What holds a merge and what clears it, and the order by id. |
