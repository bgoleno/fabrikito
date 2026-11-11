# fabrikito

A launcher that starts a team of Claude Code sessions for a software project: one persistent tmux
session per seat, each told its role, each in its own git worktree, able to message each other, shown
together in one iTerm tab. Read `README.md` for use and `teams/example.yaml` for every config key.

## Layout
- `fabrikito`: the launcher (bash). Commands: check, up, view, titles, status, say, flush, attach, migrate, down,
  run-exclusive.
- `factory.sh`: the deprecated old name of the launcher (#261), a shim that prints a notice and execs `fabrikito`. Remove it after one release.
- `lib/team_config.rb`: parses and validates a team YAML file for the script (system ruby, no gems).
- `lib/run_exclusive.rb`: `fabrikito run-exclusive`, one heavy command at a time on the host (#214).
- `lib/screen_bounds.js`: usable area of the screen a point is on, for sizing the iTerm window.
- `roles/`: generic prompts. `teams/example.yaml`: documented example team file.
- `test/e2e.sh`: end-to-end test with a stand-in `claude`, a private tmux server and a throwaway repo: the entry point,
  with the shared setup, count and cleanup.
- `test/e2e/`: the e2e cases by area, sourced by `test/e2e.sh` in the order of its `AREAS`; `lib.sh` (helpers
  more than one area uses) and `fake-claude.c` (the stand-in). A new case goes in its area's file, with a
  name no other assertion prints (the run fails on a repeat); a new area file goes in `AREAS` and ends with
  `e2e_end=<its name>`.
- `test/e2e-exit-trap.sh`: checks that the exit trap and the cleanup of `test/e2e.sh` reach no tmux server but
  the run's own (#306). Stand-in tmux only, so it starts no server and can run alone; one e2e case runs it.
- `test/live-env.sh`: a private tmux server and state folder for a live test (README: Tests).
- Git-ignored, local to each project: `teams/*` other than the example, `projects/`, `.state/`.

## Rules for this repo
- Nothing tracked may name a specific project, person, drive or path of the user's. A project's own team
  file and prompts live in the git-ignored `teams/` and `projects/`. Scan before committing:
  `git grep -n -i -E "<project name>|<owner name>"` must print nothing.
- Issues first: every change to this repository starts as a GitHub issue, filed before work begins. Its PR
  links it with `Closes #<n>` when the PR completes the issue (`Refs #<n>` when it does not) and fills in
  `.github/pull_request_template.md`.
- Gates: `bash -n fabrikito factory.sh test/e2e.sh lib/stop_gate.sh lib/session_start.sh lib/log_message.sh`, `ruby -c lib/team_config.rb`, and
  `TEST_VOLUME=/Volumes/<a mounted, writable volume> test/e2e.sh` (all assertions must pass).
- Do not run the e2e test, or any experiment, against the user's real tmux server: unset `TMUX` and use
  `TMUX_TMPDIR`, as the test does. Never kill or restart seats of a running team without being asked.
- Commit or push only when asked. The remote is a private repository.

## Things that cost time
- tmux: a session target written `=name` needs a trailing colon (`=name:`) for pane and option commands,
  and zsh expands an unquoted `=name`, so quote it.
- tmux falls back to `/tmp`, the default server, when `TMUX_TMPDIR` names a folder that is not there. A test
  that stops a server names its socket (`tmux -S`), after checking the socket is there (#306).
- bash 3.2 runs the EXIT trap in the child forked for a pipeline or `&` when an unset variable ends a simple
  command there under `set -u`, and `BASH_SUBSHELL` is 0 in it. A trap that cleans up checks it is the top
  shell by pid (`e2e_top` in `test/e2e.sh`).
- `pane_current_command` says `bash` while claude runs under a bash launcher; detect claude from the
  processes on the pane's tty.
- `say` pastes into a pane. It must refuse a pane at a shell (the text would run) or at a startup dialog
  (Enter picks "No, exit").
- macOS: seats started from tmux have no responsible app, so `~/Downloads` and removable volumes give
  EPERM; claude is run through the wrapper configured in the team file. A shell function in `~/.zshrc`
  never applies to a bash launcher.
- iTerm: Finder's desktop bounds span all displays, so window sizing uses NSScreen. Scripting iTerm needs a
  macOS Automation grant, and a pending prompt blocks osascript forever: run it with a time limit.
- System ruby is 2.6: no endless method definitions. YAML flow mappings need quoted URLs.
- Under heavy load, an e2e run can fail one assertion with `echo: write error: Interrupted system call`
  from fabrikito: macOS bash 3.2 does not restart a pipe write interrupted by SIGCHLD (#101). Rerun
  only for that exact message; for any other failure a green rerun is not evidence.
- Durable knowledge about this project lives in the Obsidian vault under `projects/software-factory/`,
  not in Claude Code's own memory files.
