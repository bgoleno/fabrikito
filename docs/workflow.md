# How work is tracked

Two rules every seat follows, and what the launcher does to support them: every change starts as an
issue, and every seat keeps a progress note.

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
