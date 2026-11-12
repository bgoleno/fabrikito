# Release notes: 0.3.0

For someone who runs a team on 0.2.0. This page says what changed between the tags `v0.2.0` and
`v0.3.0`, what to do when you upgrade, and what the release still does not do. 0.3.0 is the latest
release (see [Project facts](facts.md#status)).

## When you upgrade

Do these in order. The first two apply to every team; the rest apply if the line names something you
use.

1. **Run `check` with the new version before you stop or restart anything.** Two team files that 0.2.0
   accepted are refused by 0.3.0. The first: a role whose `tmpdir` is, holds or sits inside another role's
   `tmpdir`, the team's state folder, the repository or a seat's working directory, or that is or holds
   the worktree folder
   ([Temp files](team-file.md#temp-files), [#300](../../../issues/300)). The second: a team or a role
   with an `ask` or an `allow` rule that is one of the patterns for `tmux kill-server` or
   `tmux kill-session`, which every seat is now denied ([Safety](safety.md),
   [#308](../../../issues/308)); the error names the rule and says it has no effect. Every command
   that loads the team file refuses such a file, `say` and `down` included, so find out, and fix the
   file, before you depend on the new version to stop a running team.
2. **Restart every seat.** A seat's prompt, settings and hooks are written by `up` and read when the
   seat starts, so a running seat keeps the 0.2.0 rules until it is restarted: `down --yes <role>`,
   then `up <role>`, after the seat has written its handoff.
3. **A team on a pinned release: restart the whole team, not one seat at a time.** 0.3.0 keeps more
   in the state folder than 0.2.0 did: `say-refusals.log`, and under `say/` the records of a box that
   holds text and of a paste in progress ([`say`](messaging.md#say)). A seat that still runs 0.2.0
   uses the old `say` and the old logging hook on that same folder: it ignores those records, and it
   writes the text of a message to or from `sec` into the log. See
   [Upgrade to a newer release](pinned-release.md#upgrade-to-a-newer-release-rolling), "A full
   restart".
4. **If you add the writer role with `repo.docs_repos`:** protect the default branch of each listed
   repository with a ruleset on that repository. The ask on a push to the base branch does not see a
   push written `git -C <clone> push`, the form the writer prompt gives for a clone of such a
   repository ([Safety](safety.md)); [#346](../../../issues/346) tracks the fix.
5. **Progress notes get a first line.** From its restart on, each seat starts its note with a
   `Status:` line, and writes it the next time it rewrites the note. Until then the engineering
   manager's check lists the seat with "no Status line"
   ([The Status line](workflow.md#the-status-line-and-the-check-for-seats-without-work)). Nothing
   rewrites a note for you.
6. **The message log changes from the restart on.** The text of a message to or from `sec` is left
   out of new lines, which show `[body not logged: sec]` in its place, and a message to an address the
   logging hook could not resolve to a seat shows `[body not logged: unresolved address]`
   ([The message log](messaging.md#the-message-log)). Lines already in the log stay as they are.

Nothing in 0.3.0 renames a command or a team-file key. `factory.sh`, the old name of the launcher, is
still there as a shim that prints a notice.

## New

**Commands**

- `run-exclusive -- <command>` runs one heavy command at a time across every team on the host, in
  arrival order ([One heavy run at a time](gate.md#one-heavy-run-at-a-time)).
- `flush <role>` sends one Enter to a seat whose input box holds text that `say` itself left there,
  and nothing else ([`say`](messaging.md#say)).
- `fabrikito` can be run through a symlink to its file, for example from a folder on your `PATH`
  ([Commands](commands.md)).

**Team file**

- `state:` names the team's state folder, so a team run from a pinned release needs no link in each
  release checkout ([The team file](team-file.md#its-parts)).
- `repo.docs_repos` lists documentation repositories that a writer seat may also change
  ([The team file](team-file.md#its-parts)).

**Roles and skills**

- A Technical Writer prompt (`roles/writer.md`) and a writer seat, commented out, in
  `teams/example.yaml` ([Right-sizing a team](right-sizing.md)).
- The `security-audit` skill, for the security seat only
  ([The security-audit skill](plugin.md#the-security-audit-skill)).

**Seats**

- A seat in a permission mode that prompts may edit files under its own `tmpdir` without being asked:
  its settings carry an `Edit` allow on that folder and on no other role's
  ([Temp files](team-file.md#temp-files)).
- Every seat is denied a typed `tmux kill-server` and `tmux kill-session`, which can end other seats
  or every team on the machine. `test/live-env.sh down` stops a test server instead
  ([Safety](safety.md), [Live tests](testing.md#live-tests)).
- `repo.bootstrap` runs with the role's `tmpdir` as its `TMPDIR`
  ([New worktrees](team-file.md#new-worktrees)).
- Each progress note starts with a `Status:` line, and the engineering manager's prompt has it
  check every seat for work after each assignment, done report, verdict and merge; `team-status` lists
  the seats without work first
  ([The Status line](workflow.md#the-status-line-and-the-check-for-seats-without-work)).

## Changed

**Messaging**

- A message refused because the receiver's box holds text is no longer worth resending in a loop: the
  same text sent again within 300 seconds is refused as a repeat, the refusal is recorded in
  `say-refusals.log`, and `status` prints a `NOTICE` line for a seat after three such refusals
  ([`say`](messaging.md#say)).
- The log leaves out the text of a message to or from `sec`, and records a `SendMessage` that only
  asks to be told when a seat is idle as `NOTIFY-WHEN-IDLE`, not as an empty message
  ([The message log](messaging.md#the-message-log)).
- When `messages.log` or a gate log is a hard link, the message says to remove the other name and
  never to delete the file ([The message log](messaging.md#the-message-log), [The gate](gate.md)).

**Team file checks**

- A role's `tmpdir` that overlaps another role's, the state folder, the repository, a working
  directory or the worktree folder is refused ([Temp files](team-file.md#temp-files)).
- An `ask` or an `allow` rule on a `tmux kill-server` or `tmux kill-session` pattern is refused,
  because the new deny makes it useless ([Safety](safety.md)).
- A folder listed under `other_teams` that does not exist yet, or is still empty, is accepted, and a
  folder holding only a `.DS_Store` file counts as empty ([Safety](safety.md)).

**Starting a team**

- An interrupt while git is still adding a new worktree removes that worktree and starts no seat
  ([New worktrees](team-file.md#new-worktrees)).
- A state folder with a non-ASCII character in its path no longer stops every command under
  `LC_ALL=C` or with no locale set ([#360](../../../issues/360)).

**The shared rules and the skills**

- A pull request names at least one issue and may close several, each with its own closing keyword
  ([Issues first](workflow.md#issues-first)).
- A possible security finding goes to the security seat and the engineering manager first, whoever
  finds it ([Held security points](workflow.md#held-security-points)).
- No push to a head that a reviewer cleared, QA checked or the manager is merging, and a reviewer's
  follow-up comment takes one of two forms
  ([A pull request in review](workflow.md#a-pull-request-in-review)).
- A seat puts the rules that apply into the brief of a subagent it starts, and answers for what the
  subagent does ([Safety](safety.md), "What the rules cannot do").

**Hardening**

Six hardening fixes, in these areas:

- which tmux sessions a command treats as its team's: `up` stores the team's state folder and
  repository in each session it starts, and `up`, `down`, `say`, `flush`, `attach`, `view` and
  `titles` stop at a session whose stored values are not their own, and print the command that hands
  it over. Two teams on one tmux server need two prefixes ([Its parts](team-file.md#its-parts),
  `sessions`);
- the text `say` types into a seat;
- the permissions of the state folder: `up` takes group and other permission off the folder, the
  folders it makes in it and the message log;
- the tmux server named in the commands the launcher prints and in the iTerm view;
- pull requests from a fork: a new hard rule in the shared prompt, "Never run code from a fork's
  pull request", and the review and verification skills read such a pull request by its diff;
- which review comments count: only those posted from the team's own account.

A session that a 0.2.0 seat started holds neither stored value, and is taken for that seat until it
next starts, so the upgrade needs no step for it. A team that moves its state folder stops its seats
first, or hands each over with the command the refusal prints.

**Documentation**

- The README is now an introduction. The reference moved to `docs/`: [Messaging](messaging.md),
  [Safety](safety.md), [Updating Claude Code](updating-claude-code.md), and a page of checked
  statements for someone who describes the project elsewhere ([Project facts](facts.md)). Pointers in
  the code, the prompts and the example team file name those pages.

**For contributors**

- The gate's syntax step checks every script, one file at a time, with the two commands in
  `CLAUDE.md`. The end-to-end test and `test/live-env.sh run` put a tmux guard first on `PATH`, so a
  test's tmux call reaches only the run's own server ([The tmux guard](testing.md#the-tmux-guard)).
- `test/e2e.sh` takes the host's run lock itself and waits for its turn, whoever starts it, so it no
  longer needs `run-exclusive` in front of it. It stops before it makes anything if the tree changed
  while it waited, and `E2E_NO_LOCK=1` runs it without the lock
  ([One run at a time](testing.md#one-run-at-a-time)).

## Known limits

The standing list is [Known limits](facts.md#known-limits) on the facts page. These are the ones
that the changes in this release touch:

- **The push ask does not see a push written `git -C <dir> push`,** which is the form the writer
  prompt gives for a documentation repository. The writer prompt is the only guard the team provides
  there ([#346](../../../issues/346)).
- **The deny on `tmux kill-server` and `tmux kill-session` catches the typed command only.** A
  script that runs one, `sh -c`, tmux under another path, and a signal to the tmux process
  (`pkill tmux`) are not caught ([Safety](safety.md), "What the rules cannot do";
  [#358](../../../issues/358)).
- **The stop gate does not take the run lock,** and a gate command that takes it itself, as this
  repository's `test/e2e.sh` now does, waits inside the gate's time limit while another heavy run holds
  the lock ([How it behaves](gate.md#how-it-behaves), [#236](../../../issues/236)).
- **The writer prompt is long.** The example's writer seat renders 195 lines of the 199 that `check`
  warns above, so a team with more than a few lines of `prompts.project` gets that warning for the
  writer ([#347](../../../issues/347)).
- **Running seats do not know a seat added later** until each is restarted
  ([#231](../../../issues/231)).
- **Separate temp folders are not a boundary between seats.** The `Edit` allow is on a seat's own
  folder, and nothing denies a seat another seat's ([#337](../../../issues/337)).
- **The rules are an accident guard, not a security boundary,** as before
  ([Safety](safety.md), [#29](../../../issues/29)).
