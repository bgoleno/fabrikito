# software-factory

A launcher that starts a team of Claude Code sessions for a software project: one persistent tmux
session per seat, each told its role, each in its own git worktree, able to message each other, shown
together in one iTerm tab. Read `README.md` for use and `teams/example.yaml` for every config key.

## Layout
- `factory.sh`: the launcher (bash). Commands: check, up, view, titles, status, say, attach, migrate, down.
- `lib/team_config.rb`: parses and validates a team YAML file for the script (system ruby, no gems).
- `lib/screen_bounds.js`: usable area of the screen a point is on, for sizing the iTerm window.
- `roles/`: generic prompts. `teams/example.yaml`: documented example team file.
- `test/e2e.sh`: end-to-end test with a stand-in `claude`, a private tmux server and a throwaway repo.
- Git-ignored, local to each project: `teams/*` other than the example, `projects/`, `.state/`.

## Rules for this repo
- Nothing tracked may name a specific project, person, drive or path of the user's. A project's own team
  file and prompts live in the git-ignored `teams/` and `projects/`. Scan before committing:
  `git grep -n -i -E "<project name>|<owner name>"` must print nothing.
- Issues first: every change to this repository starts as a GitHub issue, filed before work begins. Its PR
  links it with `Closes #<n>` when the PR completes the issue (`Refs #<n>` when it does not) and fills in
  `.github/pull_request_template.md`.
- Gates: `bash -n factory.sh test/e2e.sh lib/stop_gate.sh lib/session_start.sh lib/log_message.sh`, `ruby -c lib/team_config.rb`, and
  `TEST_VOLUME=/Volumes/<a mounted, writable volume> test/e2e.sh` (all assertions must pass).
- Do not run the e2e test, or any experiment, against the user's real tmux server: unset `TMUX` and use
  `TMUX_TMPDIR`, as the test does. Never kill or restart seats of a running team without being asked.
- Commit or push only when asked. The remote is a private repository.

## Things that cost time
- tmux: a session target written `=name` needs a trailing colon (`=name:`) for pane and option commands,
  and zsh expands an unquoted `=name`, so quote it.
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
- Durable knowledge about this project lives in the Obsidian vault under `projects/software-factory/`,
  not in Claude Code's own memory files.
