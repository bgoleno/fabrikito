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

A seat cannot type `tmux kill-server` or `tmux kill-session` itself: a permission rule denies both, with or
without `-S`, `-L` and `-t` ([Safety](safety.md)). `test/live-env.sh down` is how a test server is stopped,
and `test/live-env.sh run "$d" tmux kill-session -t <name>` ends one session on it.

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

### The one failure to rerun

One failure is not ours to fix ([#101](../../../issues/101)). Under heavy load (a load average of about
40, many seats gating at once), a run can fail one assertion, and its output then shows
`fabrikito: line <n>: echo: write error: Interrupted system call`. macOS's own bash (3.2) does not
restart a write into a pipe that a child's exit (SIGCHLD) interrupts, and its `echo` does not retry.
Under `set -e` the failed write then ends the command with exit 1. The same can happen to any
fabrikito output into a pipe, such as a seat's Bash tool. Rerun when that exact message is in the
output. It is the only failure where a green rerun is the right answer. For any other failure, a
green rerun is not evidence.
