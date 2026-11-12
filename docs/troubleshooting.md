# Troubleshooting

Each entry gives what you see, why it happens in a line, and what to do. The page it links to explains
the mechanism and has the exact rules.

## Starting a team

### `up` stops: "storage volume ... is not mounted"

The launcher never puts a worktree on another disk. Mount the volume named in `storage.volume`, then
run `up` again. See [The team file](team-file.md).

### `up` stops: "refusing to start seats for ... on the default tmux server"

The team file is outside `teams/`, so the launcher takes it for a throwaway copy, and a copy would
reach the real team's seats. `down`, `say`, `flush`, `attach`, `view` and `titles` refuse it the same way. Run
a test team on a private server with `test/live-env.sh`, as the message shows. If the team is meant to
run on the default server, pass `--default-socket`. See [Throwaway teams](commands.md#throwaway-teams).

### `up` stops: "'<role>' already has a worktree elsewhere"

The repository has a worktree with this seat's folder name at another path, from an older layout for
example. Stop the seat, then run `./fabrikito migrate <role>`, which removes that worktree so that
`up` makes a new one in the right place. `migrate` refuses, and says why, a worktree with uncommitted
or untracked files, a branch checked out, or commits that are not in the base, and any worktree a
running process works in: move that work by hand first. See [The commands](commands.md#the-commands).

### `up` stops: "cannot list the worktrees ... (needs git 2.36 or later)"

The launcher reads worktree paths with `git worktree list -z`, which git 2.36 added. Update git. See
[Requirements](commands.md#requirements).

### `up` stops: "claude not found on PATH" or "could not read the version"

Claude Code is not installed, is not on the `PATH` of the shell you run `fabrikito` from, or `up`
caught it in the middle of a reinstall. Install Claude Code or add it to that `PATH`; after an update,
wait for it to finish. Then run `up` again.

### `check` or `up` says the team file "is not valid YAML: ... found unexpected ':'"

The system ruby (2.6) does not accept an unquoted URL inside a YAML flow mapping, such as
`project: { name: Board, url: https://... }`. Quote the URL, or write the mapping in block style, as
`teams/example.yaml` does.

### `up` prints "ATTENTION <role> is not at its input box (a startup dialog?)"

A seat started in a folder Claude Code has not seen stops at a trust dialog until a human answers it
once (and the first run in bypass mode shows a warning). Run `./fabrikito attach <role>`, answer the
dialog, and detach with ctrl-b d. See [Safety](safety.md).

### The iTerm view does not open: "osascript timed out after 30s"

The first run asks macOS for permission to control iTerm, and a permission prompt that nobody has
answered blocks AppleScript. Answer the prompt (or allow your terminal to control iTerm under
System Settings, Privacy & Security, Automation), then run `./fabrikito view`. The seats are running
either way. See [The iTerm view](commands.md#the-iterm-view).

### A seat gets "Operation not permitted" on `~/Downloads` or a removable volume

A seat started from tmux has no responsible app, so macOS does not give it the privacy grants your
terminal has. Set `sessions.claude.wrapper` to a program that holds the grants and runs claude. A
shell function in `~/.zshrc` does not help: the seat's launch script runs under bash. See
[The team file](team-file.md).

### Every worktree gets a full copy of its packages

Tools that hard-link from a shared store (pnpm, uv) can link only within one volume. With the store on
the internal disk and the worktrees on another volume, each worktree gets full copies. Point the store
at the worktree volume from `repo.bootstrap`. See [Package stores](team-file.md#package-stores).

## Running seats

### A seat is silent and does not answer

It may be waiting at a permission prompt: an ask rule still prompts in every mode, bypass
included, and a seat at a prompt waits for a human. `say` will not deliver to it there. Attach to the
seat and answer the prompt. See [Safety](safety.md).

### A prompt names a rule, but its reason is about parsing

A prompt such as `Permission rule ... requires confirmation`, with a reason like "expansion
obfuscation" or "shell operators that require approval", means the command's text matched an ask
rule. Claude Code could not parse the command, so it matched the rule against the whole text. Run
`git push origin <branch>:<branch>` as a command of its own, and avoid a subshell `( ... )`. See
[Safety](safety.md).

### `status` shows a worktree as "(missing)"

The seat's worktree folder is not there, for example because the storage volume is not mounted. Mount
the volume. A worktree seat should stop and tell the EM rather than work elsewhere. See
[The commands](commands.md#the-commands).

### A seat starts without its progress note

With `disableAllHooks: true` in `~/.claude/settings.json`, seats without a gate get no session-start
hook, so no note and no message logging. `check` prints a `hooks` line naming them. See
[Progress notes](workflow.md#progress-notes).

### A seat keeps being sent back by the gate

The gate fails at each stop while the seat has uncommitted changes. Read the full log,
`.state/<team>/gate/<role>.log`, and fix the cause; "gate timed out" means the gate ran past
`repo.gate_timeout`. If the seat is stopping on purpose (waiting for an answer, or with a test red
before the fix), it should say so in its report. See [The gate](gate.md) for the limit
on send-backs.

## Messages

### `check` warns: "seat-to-seat messages will be held"

Some seats run in `bypassPermissions` and others in a prompting mode. Messages between the two
classes wait at an approval dialog in the receiver's pane and are dropped when it expires, so in an
unattended team they are lost. Give every seat a `permission_mode` of the same
class, or set `crossSessionInbound`. See [Which messages are held](messaging.md#which-messages-are-held).

### `say` refuses to send

`say` types into a seat only when the seat's screen is Claude Code's input box, ready for input, and it
gives the reason when it refuses:

- "screen not recognised as ready": a permission prompt, a menu or a dialog, the held-message dialog
  included. Attach, deal with it, and send again.
- "the input box ... is not empty": someone is typing, or an earlier message was not sent. Wait and
  try once more later; do not loop (a repeat of the same text within 300 seconds is refused as a repeat,
  and `status` shows a notice for the seat after three refusals). If the text is a fragment `say` itself
  left, `./fabrikito flush <role>` submits it, deleting nothing; text someone typed is theirs, and the
  owner can attach and submit or clear it. See [`say`](messaging.md#say).
- "in copy mode": someone is scrolling. Leave copy mode with q.
- "shows Claude Code's diff panel notice": the pane is too short, even after `say` grew it for the
  check. Make it 110 columns wide or more, or 16 rows or more, or close the diff panel in the seat.
- "has no claude process running (its pane is at a shell)": the text would run as a shell command.
  Start the seat again (`down --yes <role>`, then `up <role>`).
- "is down": the seat is not running. Start it with `up <role>`.
- "the message is empty or only whitespace": the text given to `say` was empty, often an unset
  variable in a script. Nothing was typed. Check what the caller passes.
- "another say is typing into <role> and did not finish within 8 seconds": try again. "is not a
  regular file: remove it": something other than a plain file sits at the seat's lock path,
  `.state/<team>/say/<role>.lock`; remove it.
- "does not show the message after the paste ... text left in input box": no Enter was sent, and
  the text goes out with the next Enter in that seat. If it is `say`'s own text, `./fabrikito flush
  <role>` submits it (one Enter, nothing deleted); otherwise attach and send or clear it.
- "does not show just the message's label after its paste ... so the message was not pasted": after
  pasting `[from <role>]`, `say` found something else in the box (the label cleared or swallowed,
  other text, a dialog), so it did not paste the message. Attach, clear the box, and send again.
- "the message's label was pasted into <role> but the message was not": tmux failed between the
  label's paste and the message's (the seat's session ended, for example). Only `[from <role>]` is in
  the box, and no Enter was sent. Attach and clear it, then send again. "could not paste into the
  input box": tmux failed before anything reached the box. Send again.

A refused message is logged as `NOT-DELIVERED`. If `say` refuses every seat after a Claude Code update,
the update has changed how the input box is drawn, and `fabrikito` needs updating. See
[`say`](messaging.md#say).

## After a Claude Code update

### `status` shows `REPLACED`, or `up` prints "ATTENTION ... has been replaced"

The executable that seat runs was swapped under it, and macOS may stop its privacy grants (the
worktree volume, for example). Restart the seat: `./fabrikito down --yes <role>`, then
`./fabrikito up <role>`. To update every seat, run `claude update` in your own shell, then
`down --yes` and `up`. See [Updating Claude Code](updating-claude-code.md).

### `up` stops: "... is not a copy of ..."

The file at the team's copy of claude, `.state/<team>/bin/claude-<version>/claude`, is runnable but
differs from the shared executable of that version, or is a hard link (a file with a second name), so
`up` would have every seat run something that may not be that claude. Either it was put there (by a
seat or a person: find out which before going on), or the shared claude changed without a new version,
as a reinstall under way can: then retry `up` once it is done. `up` does not replace the file, because
a running seat may be using it. Once `status` shows no seat running it, remove that exact file and run
`up` again, which makes a fresh copy ([#208](../../../issues/208)). A symlink there is refused the same
way ([#194](../../../issues/194)).

### `.state/<team>/bin/` takes a lot of disk space

Each old copy of claude holds about 310 MB once the shared file has moved on, and nothing removes
them. When `check` lists a copy with no running seat, remove that folder by its exact path. See
[Updating Claude Code](updating-claude-code.md).

## Tests and live tests

### `test/e2e.sh` fails one assertion with "echo: write error: Interrupted system call"

Under heavy load, macOS's bash 3.2 does not restart a pipe write that a child's exit interrupts
([#101](../../../issues/101)). Rerun the test. This is the only failure where a green rerun is the
answer: for any other failure, a green rerun is not evidence. See [The one failure to rerun](testing.md#the-one-failure-to-rerun).

### A test command reached the real team's tmux server

tmux follows `$TMUX` when it is set, and falls back to the default server, without a word, when
`TMUX_TMPDIR` is empty or names a folder that does not exist. Run live tests through
`test/live-env.sh`, which unsets `TMUX`, points `TMUX_TMPDIR` at a folder of its own and checks that
folder on every call. It also puts a guard first on `PATH`, which fails any tmux call that would use a
socket outside that folder. See [Live tests](testing.md#live-tests).

## For contributors

These cost time when changing `fabrikito` or its tests.

- **A tmux target written `=name`** matches the session name exactly, but pane and option commands
  need a trailing colon (`=name:`). In zsh, quote it: zsh expands an unquoted `=name` to a command
  path and fails with "name not found".
- **`pane_current_command` says `bash`** while claude runs under a bash launcher. Tell whether claude
  runs from the processes on the pane's tty instead.
- **`say` must refuse a pane at a shell** (the text would run) **and one at a startup dialog** (the
  Enter would pick "No, exit").
- **System ruby is 2.6:** no endless method definitions.
- **A view window stretched across every display** comes from sizing it with Finder's desktop
  bounds, which span all displays. Window sizing uses NSScreen (`lib/screen_bounds.js`) instead.
- **Scripting iTerm needs a macOS Automation grant,** and a pending prompt blocks `osascript`
  forever, so run it with a time limit.
