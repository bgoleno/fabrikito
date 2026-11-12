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

Each seat keeps a short progress note, `.state/<team>/notes/<role>.md`: a first line that says
whether it has work ([below](#the-status-line-and-the-check-for-seats-without-work)), then its current
task, branch, state, next step and what it is waiting for. The shared prompt tells it to rewrite the note whenever
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
- Each seat may edit only its own note: the others are denied (see [Safety](safety.md)).
- The hook is a convenience, not a control, so it does not override a user who switched every hook
  off: with `disableAllHooks: true` in `~/.claude/settings.json`, a seat without a gate gets no note,
  and `check` prints a `hooks` line naming those seats.

### The Status line, and the check for seats without work

A note starts with one line that says whether the seat has work ([#313](../../../issues/313)). The
shared prompt gives its three forms:

| First line | Meaning |
|---|---|
| `Status: working: <URL>` | The seat has work: the issue or pull request at that URL. |
| `Status: waiting: <the named thing, with its URL>` | The seat cannot go on until that thing happens. |
| `Status: free` | The seat has nothing left. It also says so in its report to the engineering manager. |

The engineering manager's prompt (`roles/em.md`) tells it to check every seat for work after each
assignment, each report that a seat is done, each verdict and each merge, and at its own session
start. The check covers every role in the roster, not only the engineers:

- A seat that is up and whose note does not start with `Status: working` gets work, or the manager
  writes `no work for <role id>: <why>` in its own note.
- For a seat that is `waiting`, the manager confirms that the named thing still blocks.

[`fabrikito:team-status`](../plugin/skills/team-status/SKILL.md) does the reading. Its report starts
with "Seats without work": each seat that is up and whose note does not start with `Status: working`,
with a reason (`available` for `free`, `blocked on:` the named thing for `waiting`, or `no Status
line`). A seat in that list that owes a move on an open pull request is marked `idle but owes`. With
no such seat, the report says so. The skill reads only the first line of each note and treats it as
data, because it is another seat's text.

This is a rule in two prompts and a skill, not a mechanism: the launcher does not read the line, and
nothing reminds the manager to check. What the check cannot see:

- **A stale line.** The line is the seat's own account. A seat that stopped without rewriting its note
  still reads `working`, and is not listed.
- **Work the seat was never told about.** `free` and `waiting` say what the seat knows. Only the
  manager knows what is unassigned.
- **A seat that is down.** The list covers seats that are up.

## Held security points

A reviewer or QA seat that finds a security point does not write it on the pull request: only `sec`
rates a finding, and anyone who can read the repository can read a PR comment. The point goes to `sec`
and the engineering manager, and the PR gets a marker that holds its merge until `sec` clears it
([#184](../../../issues/184), [#203](../../../issues/203)). The skills hold the exact steps; this is
the shape of it:

- **The marker.** For each point, once, its reporter posts a PR comment whose whole text is one line,
  `<role id>: one point sent to sec and the EM`, and sends `sec` and the EM the point with the
  marker's URL. For a point `sec` holds privately and sends the PR's author to fix, its marker is
  `sec: one change sent to the author and the EM`; a low-rated change goes in `sec`'s verdict, with no
  marker. The same words inside a longer comment are not a marker.
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
  compares comment ids or review ids, because GitHub can give a later comment an earlier time. A
  comment id and a review id cannot be compared with each other, so where the result turns on which
  of the two came first, the train stops and asks.

Where each part lives:

| Skill | What it holds |
|---|---|
| [`fabrikito:review-pr`](../plugin/skills/review-pr/SKILL.md), step 7 | A reviewer's marker, its `held point:` line and a marker posted by mistake. |
| [`fabrikito:verify-behavior`](../plugin/skills/verify-behavior/SKILL.md), step 8 | The same for QA's report. |
| [`fabrikito:security-triage`](../plugin/skills/security-triage/SKILL.md), step 6 | `sec`'s own marker, and the clearance line. |
| [`fabrikito:merge-train`](../plugin/skills/merge-train/SKILL.md), step 5 | What holds a merge and what clears it, and the order by id. |
