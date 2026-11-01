# The gate

The repository's pass/fail command, and how a seat is held to it when it stops with uncommitted work.

`repo.gate` is the repository's pass/fail command. A role with `gate_on_stop: true` gets a Stop hook in
its generated settings (`lib/stop_gate.sh`): whenever the seat ends a turn with uncommitted changes in
its working tree, the hook runs the gate there, and if it fails the seat is sent back to work with the
command, the last 60 lines of its output and the path of the full log (`.state/<team>/gate/<role>.log`).
Roles without the switch never run it. The example gives it to the engineers and qa.

## How it behaves

- Only uncommitted work is gated at a stop: a clean tree, including committed but unpushed work, ends
  the turn normally. Committed work is gated again when the reviewer runs the gate on the PR. A
  `git status` that fails (a corrupt index, say) counts as uncommitted work: the gate runs, and a
  send-back says status failed. The hook's git calls do not run a repository's fsmonitor program;
  clean filters stay on, because status needs them for a correct answer ([#104](../../../issues/104)).
- Only the seat's configured working tree is checked. Work left in another tree, such as a worktree
  Claude Code made for a subagent or for `EnterWorktree` under `<repo>/.claude/worktrees/`, is not
  gated.
- The gate catches mistakes, not a seat that edits the gate. It runs the scripts in the seat's own tree
  (a Makefile, test scripts), at the stop and outside Claude Code's permission rules: no prompt, no
  deny or ask rule, no auto-mode classifier. A seat that changes those files decides whether its gate
  passes and what runs at its next stop, so for a seat that is not in bypass mode, permission to edit
  its tree becomes commands that run unprompted at the stop. The reviewer's own run of the gate on the
  PR stays the real check.
- A seat also stops on purpose: to wait for an answer or a review, or with a test red before the fix.
  After `repo.gate_max_blocks` (default 3) failed gates in a row in one turn, the next stop in that turn
  goes through without running the gate again, with a note that the gate is still failing. Every
  send-back tells the seat that, if it is stopping on purpose, it should say so in its report, and
  gives the limit (this moved here from the shared prompt, [#117](../../../issues/117); the let-through's
  note is shown to the user, not to the seat). Each new turn starts from zero, so a seat that lives
  for days is never gated off for good. The count is in the state folder, which seats cannot edit through Claude
  Code's tools; a passing gate or a clean tree resets it. A script can still write it, or run the hook
  with made-up input, like every other "a script can do it" limit under [Safety](../README.md#safety). Run by hand
  with no hook input, `lib/stop_gate.sh` runs the gate and reports but leaves the count alone. Claude
  Code also ends such a loop itself after 8 continuations with no tool call in between (raise it with
  `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).
- The gate runs with a time limit (`repo.gate_timeout`, default 600 s) in a process group of its own,
  which is killed whole when the time is up. A program that detaches from that group (a daemon, a tmux
  server) is not killed.
- The hook inherits the seat's environment, which runs inside tmux: a gate that must not touch the
  team's tmux server unsets `TMUX` itself, as this repository's does.
- The gate runs at every such stop, so a slow gate (this repository's e2e takes over a minute) makes
  those stops slow.
- A gated seat's settings set `disableAllHooks: false`, so a `.claude/settings.json` in the project
  cannot switch the gate off. That also turns the user's own hooks back on for that seat if
  `~/.claude/settings.json` had switched them all off.
