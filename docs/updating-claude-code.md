# Updating Claude Code

Why a Claude Code update needs care on a running team, what fabrikito does about it, how to update, and
how to remove the old copies of claude it leaves behind.

Claude Code's updater replaces its shared executable (the npm package's `bin/claude.exe`), even with
the same version, and every Claude Code session on the machine runs it, not only this team's seats.
macOS then can no longer identify a seat still running the old file, and the privacy grants it runs
under (a removable volume holding the worktrees, for example) stop working until the seat restarts
([#50](../../../issues/50)). So:

- **Each seat runs the team's own copy of claude**, `.state/<team>/bin/claude-<version>/claude` (in the
  team file's `state:` folder, if it sets one: see [The team file](team-file.md)). `up`
  makes it from the shared executable when it is missing: an APFS clone where the state folder is on
  the same file system (it takes no space while the shared file exists), else a plain copy. It is
  checked (size, `--version`) before use, and if it cannot be made, `up` stops instead of running the
  shared file. A copy that is already there is used only if it is the shared executable byte for byte;
  one that differs is refused, not replaced, and `up` starts no seat ([#208](../../../issues/208)).
  Nothing but `up` writes there, and seats cannot edit it.
- **The seats' own updater is off** (`DISABLE_AUTOUPDATER=1`, in the launch script and the generated
  settings), so the seats do not add reinstalls of their own.
- `check` names the shared executable, its version and the copy seats will run, and lists every copy
  with the running seats that use it. `status` shows each running seat's executable, or `REPLACED`
  when the file it runs has been swapped under it; `up` prints an ATTENTION line for such a seat.
  Restart it (`down --yes <role>`, then `up <role>`).

## To update

Run `claude update` in your own shell (a manual update works with the variable set), then
`./fabrikito down --yes` and `./fabrikito up`. The next `up` copies the new version, and every seat
starts on it.

## Old copies

Old copies are never removed automatically. Once the shared file has moved on, each one holds about
310 MB. When `check` lists a copy with no running seat, remove that folder by its exact path, for
example `rm -r .state/<team>/bin/claude-2.1.314`.

For a team run from a pinned release, the copies live in the shared state folder, so every release
uses them: see [Running a team from a pinned release](pinned-release.md). If `up` stops with "... is
not a copy of ...", see [Troubleshooting](troubleshooting.md).
