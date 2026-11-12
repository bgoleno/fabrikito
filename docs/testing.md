# Testing

How to run a live test without touching the team you work with, and how the end-to-end test is built
and judged.

## Live tests

A live test (a throwaway team with a real `claude`, or anything else that starts tmux sessions) runs on a
private tmux server through `test/live-env.sh`, never on the server you work in:

```
d=$(test/live-env.sh new)                                  a private folder: tmux/, state/
test/live-env.sh run "$d" ./fabrikito -c /path/to/throwaway.yaml up
test/live-env.sh run "$d" tmux ls                          any command, with TMUX_TMPDIR=$d/tmux and
                                                           TEAM_STATE_DIR=$d/state (absolute), TEAM_VIEW=0,
                                                           TEAM_ROLE=live-test (the driver label), and TMUX
                                                           and a seat's TEAM_CONFIG and TEAM_SCRIPT unset (so
                                                           fabrikito without -c never finds the seat's real
                                                           team)
test/live-env.sh down "$d"                                 stop its tmux server, remove the folder
```

Each call checks the folder on its own (made by `new`, its tmux folder not `/tmp`), so it works from a fresh
shell each time. Setting `TMUX_TMPDIR` by hand is easy to get wrong: tmux 3.7 follows `$TMUX` when it is set,
and falls back to the default server, silently, when `TMUX_TMPDIR` is empty or names a folder that does not
exist. A throwaway team's worktrees on the volume are not removed by `down`; remove them by their paths.

`run` also puts the [tmux guard](#the-tmux-guard) first on `PATH`, for that folder: a tmux call the command
makes, or a command it runs makes, gets through only to a socket inside `$d`, whatever `TMUX`,
`TMUX_TMPDIR`, `-L` or `-S` it comes with. Any other call fails with a message that names it
(`tmux-guard: refused: tmux kill-server: ...`). Not held: a command that runs tmux by its full path or
changes `PATH`, and the seats of a team started in the environment, whose panes run a login shell that
builds `PATH` again.

## The end-to-end test

`TEST_VOLUME=/Volumes/YourDrive test/e2e.sh` runs the launcher against a throwaway repo with a stand-in
`claude` on a private tmux server. From a seat, or with other teams on the machine, run it through
`./fabrikito run-exclusive -- env -u TMUX TEST_VOLUME=/Volumes/YourDrive test/e2e.sh`, so that only one
heavy run loads the machine at a time ([One heavy run at a time](gate.md#one-heavy-run-at-a-time)).
The run uses a lock of its own for its run-exclusive cases, never the real one.

### Its temp folder

The run works in a scratch folder under `TMPDIR`, and removes it at the end. `TMPDIR` can be directly on a
volume, or the default temp folder. It needs no symlink: the run makes its own, `<scratch>/l -> r`, because
the launcher's rules cover a path both as configured and as its real path, and the cases that check both
need two spellings to differ wherever the run is ([#249](../../../issues/249)). A case that removes the
scratch folder by hand removes `$T_TOP`, since `$T` is the link.

A `TMPDIR` can be at most 65 characters, in the spelling you give and as its real path, with a user id of
three digits: tmux refuses a socket path over 103 characters, and the run adds 38. A longer one is refused
at once, with the limit for your user id, and makes nothing. Folders outside `TMPDIR` are `TEST_VOLUME`'s
throwaway folder, and `test/live-env.sh`'s own under `/tmp`; the run removes both.

### Where the cases live

The cases live in `test/e2e/`, one file per area, and `test/e2e.sh` sources them in the order of its
`AREAS` list, in one shell, after one shared setup ([#70](../../../issues/70)). A new case goes in its
area's file. A new file must be added to `AREAS`, or the run stops: it never skips a file it was not told
about. Each file's last line is `e2e_end=<its name>`, and the run stops when a file does not get there (a
heredoc that never ends, a top-level `return`, `continue` or `break`), so no part of an area is skipped
in silence. Every assertion prints a name of its own: a name printed twice fails the run
([#163](../../../issues/163)), because a diff of two runs' PASS lines could not tell the two apart.

### What it covers

Each area file says what it covers in the comment at its top, under the line that says it is sourced
by `test/e2e.sh`. Those comments are the list, kept next to the cases they describe. To read them all,
each file's whole leading comment, however many lines it has:

```
awk 'FNR == 1 { print "==> " FILENAME } /^#/ { print; next } { nextfile }' test/e2e/*.sh
```

`test/e2e/lib.sh` holds the helpers more than one area uses, and `test/e2e/fake-claude.c` is the
stand-in `claude`.

### Its result

The exit code is authoritative: `test/e2e.sh` exits 0 only when it reaches the end with every
assertion passed (`RESULT pass=<n> fail=0`), and non-zero when any assertion fails or the run stops
early (a setup error, a signal). A run that stops early still removes what it made and says
`ABORTED` on stderr. That makes it safe as a `repo.gate` command, which is judged by its exit code.

### Its own tmux server, and no other

The run stops its tmux server by its socket (`tmux -S <scratch>/tmux/tmux-<uid>/default kill-server`), only
when that socket is there, and before it removes the scratch folder ([#306](../../../issues/306)). It never
runs a bare `tmux kill-server`: that finds its server through `TMUX_TMPDIR`, and once the folder is gone
tmux falls back to the default server. Only the shell that started the run cleans up. bash 3.2 runs the
exit trap in a child too, when an unset variable ends a command in a pipeline
(`echo "$out" | grep -q "$unset"`), and such a child now removes nothing and stops nothing.

`test/e2e-exit-trap.sh` checks this, and the run includes it as one case. It runs `test/e2e.sh` from a
scratch tree where the areas are stubs, with a stand-in `tmux` that records each call and runs nothing. It
starts no tmux server, so it can run alone, and against another copy of the file:
`test/e2e-exit-trap.sh /path/to/an/older/e2e.sh`.

### The tmux guard

Exporting `TMUX_TMPDIR` keeps a run's tmux calls private only while nothing goes wrong: one bare `tmux`
call after the folder is gone, or with `TMUX` set, reaches the default server. So the `tmux` first on the
`PATH` of a run is a guard, `test/guard/tmux` ([#307](../../../issues/307)). It is the tmux of the test's
own shell, of every area file and of the launcher under test, which inherit that `PATH`. A stand-in seat
does not: its pane runs a login shell, whose profile builds `PATH` again with the system's folders first.
So the stand-in `claude` puts the guard first on its own `PATH` when it starts, and everything a stand-in
seat runs has it. A new area file gets all of this without doing anything.

- It works out the socket a call would use as tmux does (`-S`, else `-L`, else the one `TMUX` names, else
  `tmux-<uid>/default` under `TMUX_TMPDIR`), without tmux's fallback to `/tmp`.
- The call is passed on to the real tmux only when that socket is inside one of the run's own folders
  (`TMUX_GUARD_ROOTS`: the scratch folder for `test/e2e.sh`, the environment's folder for
  `test/live-env.sh run`), every link resolved, and always with `-S` and that socket. The folder of the
  user's own servers, `/tmp/tmux-<uid>`, is never accepted, whatever the roots.
- Any other call fails, with a message that names it and the reason, and is recorded
  (`TMUX_GUARD_LOG`). A run fails at its end if the guard refused a call that no case asked for.
- With no root that exists, every call is refused. The guard is in the tree and not in the scratch folder,
  so it is still the tmux on `PATH` after the scratch folder is removed, for a job the run left behind too.
- A stand-in `tmux` that an area puts first on `PATH` and that passes calls on is built on
  `command -v tmux`, which is the guard, so its calls are judged too.
- A call that goes to another server on purpose says so where it is made: through `test/live-env.sh run`,
  or with `TMUX_GUARD_ROOTS` naming the other folder beside the `TMUX_TMPDIR` that sends it there.
- A command run with `env -i` loses the guard's variables and is refused, so it passes
  `TMUX_GUARD_ROOTS` on, as it passes `TMUX_TMPDIR`.

It guards against mistakes, not against a process that means to get out: a call to the real tmux by its
full path is not held. Two more callers are not held, for the reason above (a pane's login shell builds
`PATH` again, and the real tmux is then the first one on it):

- a command typed at the bare shell of a pane, outside the stand-in `claude`;
- the seats of a team with the real `claude`, started through `test/live-env.sh run`: the guard is the
  tmux of the command `run` starts and of what that command runs directly, not of what runs in the panes.

In a pane `TMUX` names the pane's own server, so a bare tmux call there stays on it; the call that can get
out is one that unsets `TMUX` or names another socket.

A case that makes a call the guard must refuse first checks that its `tmux` is the guard
(`command -v tmux`), and fails without making the call if it is not; where it can, it makes a call that
only reads. Otherwise a guard that is missing sends the very call that proves it to the user's own server.

`test/e2e-tmux-guard.sh` checks the guard call by call, for `tmux ls` and `tmux kill-server`: what it
refuses and what it passes on, and the same through `test/live-env.sh run` and `down`. The real tmux
behind the guard is a stand-in that records and runs nothing, so it starts no server and can run alone, on
another copy of the guard too: `test/e2e-tmux-guard.sh /path/to/a/guard`. `test/e2e-exit-trap.sh` has the
cases with the run's folders removed mid-run and with a job left behind after the exit trap. The run
includes both scripts, and its `guard` area checks the guard with the real tmux behind it, with calls that
only read.

The launcher's own refusal of the default server (`up`, `down`, `say` and the others, for a team file
outside `teams/`) is tested without the guard in the way: those cases put a stand-in tmux of their own
before it on `PATH`, one that records and runs nothing or passes on to the run's socket, and they look for
the launcher's message, which the guard never prints.

### The one failure to rerun

One failure is not ours to fix ([#101](../../../issues/101)). Under heavy load (a load average of about
40, many seats gating at once), a run can fail one assertion, and its output then shows
`fabrikito: line <n>: echo: write error: Interrupted system call`. macOS's own bash (3.2) does not
restart a write into a pipe that a child's exit (SIGCHLD) interrupts, and its `echo` does not retry.
Under `set -e` the failed write then ends the command with exit 1. The same can happen to any
fabrikito output into a pipe, such as a seat's Bash tool. Rerun when that exact message is in the
output. It is the only failure where a green rerun is the right answer. For any other failure, a
green rerun is not evidence.
