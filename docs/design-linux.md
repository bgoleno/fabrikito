# Design: running fabrikito on a Linux host

Status: **proposed** ([#371](../../../issues/371)). Nothing on this page is built yet. The owner approves
the design, and the implementation issues at the end are filed only after that.

The goal: one checkout of fabrikito runs on macOS or on Linux (Ubuntu first), finds out which one it is
on by itself, and needs nothing in the team file beyond what a Linux team file naturally holds (a
storage volume that exists on that host).

## The decisions in short

| Question | Decision |
|---|---|
| Detection | `uname -s`, read once per process (bash) and through `Etc.uname` (Ruby). `Darwin` is macOS, `Linux` is Linux, and anything else is refused before any work is done. There is no setting and no override. |
| Where the differences live | In two files only: `lib/platform.sh` (bash) and `lib/platform.rb` (Ruby). A portability lint in the gate fails on a BSD-only or macOS-only form anywhere else, and a Linux CI job runs the whole gate. |
| Storage volume on Linux | Any mount point in the kernel's mount table (`/proc/self/mountinfo`): a second disk at `/mnt/<name>` or `/media/<user>/<label>`, or `/home` or `/` on a host with one disk. It is proven at the same moments as on macOS, with the same two checks: it is mounted, and the target folder is on it. |
| The iTerm view on Linux | None. `up` skips it and says so in one line, and `view` refuses with the attach commands to use instead. `view --print` still prints the layout on both. |
| macOS-only features | The view and its window sizing become no-ops. The privacy-grant wrapper stays a plain option. The team's own copy of `claude` stays on both platforms. `check` names each one on Linux. |
| Minimum versions | macOS as now. Linux: Ubuntu 24.04 LTS's packages, the only ones tested. Ubuntu 22.04 is not supported, because its git (2.34.1) is older than the 2.36 fabrikito needs. `check` prints the host's versions. A missing tool or a too-old git is refused, and a version older than the tested one gets a warning. |
| Testing | The same e2e suite on both platforms, with platform-only cases that print a counted skip. A GitHub Actions job on a pinned `ubuntu-24.04` runs the whole gate. It is not required at first, and becomes required once it is green. |
| Cross-session messaging | Claude Code's documentation says it works on Linux the same way it works on macOS: a Unix socket for each session, limited to the user. Nothing here has run it on a Linux host, so the last issue is a live check on one. |

## What was checked, and how

Each claim on this page is marked with how it is known:

- **[read]**: from reading the code at `66c43e7`.
- **[ran]**: run in a throwaway `debian:bookworm-slim` container: Debian 12, GNU coreutils 9.1, bash
  5.2.15, arm64. Debian is Ubuntu's base, but this is not Ubuntu. A container on a macOS host's VM is not
  a Linux host either: it has no login session, no terminal, no tmux, no Ruby and no Claude Code.
- **[docs]**: from Claude Code's documentation
  ([Message your other Claude Code sessions](https://code.claude.com/docs/en/cross-session-messaging)).
- **[archive]**: from the Ubuntu archive's published source versions for the `jammy` (22.04) and `noble`
  (24.04) releases, read from Launchpad's API.
- **[not checked yet]**: not run on Ubuntu, either because no Ubuntu host or image has been used
  for this design, or because the check needs a Claude Code login.

## 1. What breaks on Linux today

The issue's inventory was a starting point. The list below is longer. Most failures are loud, but four
checks fail **open** under GNU tools: they do not refuse what they exist to refuse. That is the reason
the design keeps every BSD form out of the shared code (section 2), instead of fixing each call where it
is found.

**GNU `stat -f` is the file-system form, not a format flag [ran].** BSD `stat -f %l f` prints the link
count. GNU `stat -f %l f` reads `%l` as a second file name. It exits 1 and prints the *file system's*
details for `f` on standard output (several lines: ID, name length, block counts). Every
`$(stat -f ...)` in fabrikito therefore gets several lines of other text on Linux:

| Where | What it guards | On Linux |
|---|---|---|
| `log_unsafe` in `fabrikito` (message log, box records) and the log and count checks in `lib/stop_gate.sh` | Refuses a hard link: `[ "$(stat -f %l "$p" 2>/dev/null \|\| echo 1)" -gt 1 ]` | **Fails open [ran]**: `[` gets text, prints "integer expression expected" and returns 2. The test is false for a file with two links, so the guard is off. |
| `copy_same_or_die` (the team's copy of `claude`, #208) | The copy has one name and the same size | Fails closed (inferred from the run above): the output is never `1`, so every `up` after the first refuses the copy. |
| `ensure_claude_copy` | The new copy has the source's size | Fails closed or passes by luck (inferred): each call prints free-block counts, which changed between two calls in the run. |
| `seat_exe` (status `EXE`, `REPLACED`) | The running file is still the one at its path | Wrong answer (read): with no `lsof` it is `?`, and with `lsof` it is `REPLACED`. |
| e2e cases (`stat -f %Lp`, `%i`, `'%N %Lp %z %m'`) | Modes, inodes, a tree snapshot | Case failures (read). |

**Other forms [ran unless marked]:**

- `date -r <epoch>` (status box notices, `flush` messages): GNU reads `-r` as a reference *file*, so it
  exits 1 and the time is left blank in the notice.
- `shasum -a 256` (say's repeat refusal, #212): not in `debian:bookworm-slim` (exit 127), so the hash is
  empty and the repeat refusal is **silently off**. On Ubuntu, `shasum` comes with the `perl` package,
  and whether a server install has that package [not checked yet]. `sha256sum` is in coreutils.
- `cp -c` (an APFS clone of `claude`): GNU 9.1 rejects `-c` (exit 1), so the code falls back to a
  plain copy. Safe.
- `mv -n` (never replace a copy a seat may run): GNU 9.1 exits 0 and leaves the source when the
  target exists, as macOS does. Whether coreutils 9.4 (Ubuntu 24.04) exits the same way
  [not checked yet]. The design stops depending on the exit status (issue B).
- `sed -i ''` (e2e cases): GNU reads `''` as the script and fails (exit 2).
- `mount | grep " on <vol> ("` (storage proofs in `fabrikito`, `volume_mounted?` in
  `lib/team_config.rb`): Linux prints `<dev> on <dir> type <fs> (...)`, so the pattern never matches.
  The volume reads as unmounted, `check` says so, and `up` refuses. This fails closed.
- `lsof` (`seat_exe`, `cwd_users` for `migrate`): not in the slim image. `migrate` then refuses
  every removal ("lsof gave no answer"), which fails closed [read]. Whether Ubuntu 24.04 server installs
  `lsof` by default [not checked yet].
- `osascript` in `cmd_view` [read]: on Linux `command -v osascript` fails and `die` *exits* the
  shell. `up` calls `cmd_view` at its end with `|| echo warning`, which does not catch an `exit`. So with
  `display.iterm: true` (the default), `up` would start every seat and then exit 1.
- Ruby is not in the slim image, and the issue says the same of Ubuntu by default [not checked yet]. The
  launcher's message says it "ships with macOS".
- `RUBY_PLATFORM.include?('darwin')` [read]: path folding (NFC, lower case) for the overlap checks of
  `state:` and `other_teams` is off on Linux. A case-insensitive file system mounted on Linux (exFAT,
  vfat) would then let two spellings of one folder pass as different. That refuses less, not more.
- `/Volumes/` [read]: `volume_mounted?`, the `state:` check and its messages assume removable volumes
  live there.
- `~/Library/Application Support/fabrikito/` [read]: the run lock's folder. On Linux it would be made
  under the home folder with that macOS name. It would work, but no Linux user would look for it there.
- `cc` (the e2e stand-in) needs a C compiler: `build-essential` on Ubuntu [not checked yet].

**Portable already [read]:** tmux, git, `df -P` (the field layout is POSIX), `ps -t <tty> -o pid=,comm=`
and `ps -o ppid=,tty=,comm=` (procps takes `pts/N`), `perl` for `flock`, `alarm` and `setpgrp` (in
`perl-base`, essential on Debian and Ubuntu [ran: present in the slim image]), `mktemp` with a template,
and `YAML.safe_load(..., permitted_classes: [], aliases: false)`, whose keyword form works in Psych 3 and
Psych 4. A grep of the `awk` programs found no gawk-only function or interval expression (Ubuntu's awk
is mawk), but a grep is not proof. Whether bash 5.2 and Ruby 3.2 change any behaviour the code relies
on (it is written for bash 3.2 and Ruby 2.6) is [not checked yet]: only the e2e on Linux will tell.

## 2. Detection, and where the differences live

**Detection.** `lib/platform.sh` sets `FAB_OS` from `uname -s`: `Darwin` gives `macos`, `Linux` gives
`linux`, and anything else stops with `error: unsupported platform: <name> (fabrikito runs on macOS and
Linux)` before the team file is read. `lib/platform.rb` does the same with `Etc.uname[:sysname]`
(Ruby 2.2 or later), never with `RUBY_PLATFORM`, so bash and Ruby read one source. There is no
environment variable or team-file key to force a platform. A forced value would only pick commands the
host does not have, and a test that forces one would be testing a path that never runs. WSL 2 reports
`Linux` and would take the Linux path. It is not a target and is not tested.

**One layer, not per call site.** Every operation that differs goes behind a named function in one of the
two files, and callers never write the platform form themselves:

| `lib/platform.sh` | macOS | Linux |
|---|---|---|
| `fs_links <file>` | `stat -f %l` | `stat -c %h` |
| `fs_size <file>` | `stat -f %z` | `stat -c %s` |
| `fs_mode <file>` | `stat -f %Lp` | `stat -c %a` |
| `fs_dev_ino <file>` | `stat -f '%d %i'` | `stat -c '%d %i'` |
| `epoch_time <seconds>` | `date -r N '+%Y-%m-%dT%H:%M:%S'` | `date -d @N '+%Y-%m-%dT%H:%M:%S'` |
| `sha256_hex` (stdin) | `shasum -a 256` | `sha256sum` |
| `clone_copy <src> <dst>` | `cp -c`, else `cp`; prints `clone` or `copy` | `cp --reflink=auto`; prints `copy` |
| `exe_of_pid <pid>` | `lsof -a -p PID -d txt -FDin` | `/proc/PID/exe`: `stat -L -c '%d %i'`, `readlink` |
| `cwd_pids <dir>` | `lsof -w -d cwd -F pn` | `readlink /proc/[0-9]*/cwd` (own processes) |
| `volume_mounted <vol>` | calls `lib/platform.rb` | calls `lib/platform.rb` |
| `run_osa ...` | `osascript` with a time limit (moved from `fabrikito`) | fails with "macOS only" |

| `lib/platform.rb` | macOS | Linux |
|---|---|---|
| `Platform.os` | `:macos` | `:linux` |
| `Platform.mount_points` | parsed from `mount` | parsed from `/proc/self/mountinfo` (field 5, octal escapes such as `\040` decoded) |
| `Platform.mounted?(path)` | as now: in the table, or `/Volumes/<x>` that links to the boot volume | in the table, as written or as its real path |
| `Platform.removable_root(path)` | `/Volumes/<name>` | `/media/<user>/<name>`, `/run/media/<user>/<name>`, `/mnt/<name>` |
| `Platform.fold(path)` | NFC, lower case | NFC, lower case (see below) |
| `Platform.lock_dir(home)` | `<home>/Library/Application Support/fabrikito` | `<home>/.local/state/fabrikito` |

The contract that makes a helper safe: **it prints only on success, and fails with nothing on standard
output otherwise.** `fs_links` prints a number or nothing, never a file system's details. A caller keeps
its own decision about a failure (the hard-link guards' "not there any more" case stays as it is today),
but it can no longer be handed text it never expected. Each helper is written for bash 3.2 and Ruby 2.6
and must also run under bash 5.2 and Ruby 3.2.

Why one layer: the GNU `stat -f` failure shows that a BSD form does not fail where it is written. It
fails quietly, several calls later, in a guard. Fixing each call where it is found leaves the next
change free to add a new one. With one layer, a reviewer has one file to read for platform behaviour, and
a lint can enforce the rule mechanically.

**What stops a BSD form coming back.** Two independent checks:

1. `test/lint-portable.sh`, run as part of the gate, fails on any of these outside `lib/platform.sh` and
   `lib/platform.rb`: `stat -f`, `stat -c`, `date -r`, `date -d`, `sed -i`, `mv -n`, `cp -c`,
   `--reflink`, `lsof`, `osascript`, `shasum`, `sha256sum`, `/proc/`, `/Volumes/` in code (comments and
   messages allowed), `Library/Application Support`, `RUBY_PLATFORM` and `uname`. It scans `fabrikito`,
   `lib/`, `test/` and `test/guard/tmux`. A line that must keep one (for example a test that proves a
   helper matches the raw form) ends with a marker comment, `# portable-ok: <reason>`, which a reviewer
   sees in the diff.
2. The Linux CI job (section 7) runs the whole gate, so a form the lint does not know still fails a run.

**Folding on both platforms.** `Platform.fold` folds paths (NFC, lower case) on Linux too. Today's code
folds only on macOS, because macOS disks are case-insensitive, and its comment notes that folding errs
toward refusing more. On Linux most file systems are case-sensitive, but an exFAT or vfat drive is not,
and that is exactly the kind of drive a storage volume can be. If Linux paths are not folded, an overlap
can pass unnoticed on such a drive. If they are folded, the worst case is a refusal of two folders whose
names differ only in case, which is rare and loud. Folding on both also removes a platform branch.

## 3. The storage volume on Linux

On macOS the storage volume is `/Volumes/<name>`, and the danger it guards against is `mkdir -p` under
an unmounted `/Volumes/<name>`, which quietly makes the folder on the internal disk. Linux has the same
danger, under other names. A drive meant for `/mnt/data` that is not mounted leaves `/mnt/data` as an
empty folder on the root file system, and `mkdir -p /mnt/data/worktrees` succeeds there.

**What it means on Linux.** `storage.volume` names a mount point: a path that is the target of an entry
in `/proc/self/mountinfo`. That covers a second disk mounted through `fstab` (`/mnt/<name>` is the
convention), a drive that udisks mounts at `/media/<user>/<label>` (or `/run/media/<user>/<label>`), and
on a host with one disk, `/home` when it is its own file system, or `/` itself. The team file keeps the
key it has now; only the example path in messages changes with the platform.

**How it is proven, at the dangerous moment, as on macOS.** The callers and the moments stay as they are
(`require_volume` before a worktree is made, `prepare_tmpdir` before a seat's temp folder is made, the
`state:` check in `validate`). Only the two proofs go through the layer:

1. `volume_mounted "$VOLUME"`: the path, as written or as its real path, is a mount point in
   `/proc/self/mountinfo`. That file is read directly, not through `mount` or `findmnt`. It is the
   kernel's own table, its escapes are defined, and it needs no tool that a minimal host might lack.
2. `mount_of "$WT_ROOT"` (`df -P`, unchanged): the folder about to be used is on that mount and not on
   another one mounted under it or reached through a link.

`validate_state_key` generalises its `/Volumes/<name>` test to `Platform.removable_root`. A `state:`
path under `/mnt/<name>` or `/media/<user>/<name>` must have that mount point mounted.

**A volume that is `/`.** When `storage.volume` is `/`, the proof can never fail: there is no second
disk that could be missing. That is a correct answer for a one-disk host, not a weakened check. `check`
says so in the volume line (`[volume /: mounted; the root file system, so a missing disk cannot be
detected]`), so nobody reads it as protection.

**What `check` adds on Linux.** It adds the volume's file-system type, from `mountinfo`, and two
warnings, neither a refusal:

- `noexec` among the mount options: the gate, the bootstrap and the e2e stand-in run programs from the
  worktrees and temp folders.
- vfat, exFAT or NTFS: these hold no Unix owners or modes, so the "owner-only" temp folders (`chmod
  700`) protect nothing. On vfat the `chmod` itself may fail, and `up` then stops, as it does today.
  macOS already accepts a volume mounted with "ignore ownership" and says what that costs, so Linux
  gets the same warning rather than a new refusal.

Not designed for: a udisks drive on a host with no desktop login is not mounted until someone logs in,
so `up` refuses until then. That is correct, and the docs should point a server host at an `fstab` mount
under `/mnt` [not checked yet].

## 4. What replaces the iTerm view

**Nothing, in this design.** On Linux, `up` skips the view and prints one line: `no view on Linux
(the iTerm view is macOS only): attach with ./fabrikito attach <role>`. `view` exits 1 with the same
text and the attach command for each running seat. `view --print` keeps printing the layout script on
both platforms, because it reaches no seat and the e2e cases use it. `display.iterm` keeps its default
and is ignored on Linux, so one team file works on either host, and `check` says it is ignored.

Why not a tmux layout instead: tmux shows the panes of one session's window, and every seat is a
session of its own. One window showing every seat means a "view" session whose panes each run a second
tmux client (`tmux attach` inside tmux). That nesting brings problems of its own. The prefix key reaches
the outer client first. `TMUX` must be unset in every pane, which is the variable the e2e guard and
#105's rule rely on. And a nested client resizes the seat's window, which is the short-pane problem of
#84 in a new form. A Linux host is often a server reached over SSH, where the user's own terminal (tmux
on their side, a tiling terminal, or several tabs) is the better place to arrange panes. If the owner
wants a built-in view on Linux later, it can be its own issue: the decision here does not block it.

Kept on both platforms: `titles` and the title each seat sets (`set-titles`). Any terminal shows them.

## 5. macOS-only features on Linux, and what `check` reports

| Feature | On Linux | `check` on Linux |
|---|---|---|
| iTerm view, window sizing (`lib/screen_bounds.js`) | No-op (section 4) | `view      : none on Linux (display.iterm is ignored); attach with ./fabrikito attach <role>` |
| Privacy-grant wrapper (`sessions.claude.wrapper`) | Unchanged: a wrapper that is set is still used. Linux has no privacy grants for it to hold, but it is only a program that runs `claude`, and some hosts may want one (a `nice`, a `systemd-run --user --scope`). | The line it prints now, with the macOS reason removed from the launch script's comment. |
| The team's own copy of `claude` (#50) | **Kept.** Its first reason (macOS loses a seat's privacy grants when the updater replaces the file) does not apply. The others do: it keeps seats on one known version, and `status` can tell when a seat runs a file that is no longer at its path. One code path is also cheaper than two. On Linux it is made with `cp --reflink=auto` (a clone on Btrfs or XFS, a copy elsewhere). | As now: path, version, and the copies with the seats that use each. |
| Auto-updater off (`DISABLE_AUTOUPDATER=1`) | Kept, for the same version reason. | As now. |
| The legacy lock path (`software-factory/run-exclusive.lock`) | Not on Linux: no Linux host ever had a lock there. | Nothing. |
| Unicode folding of paths | On both (section 2). | Nothing. |

`check` also gets a `host` block on both platforms (section 6).

## 6. Requirements and minimum versions

**Linux.** Ubuntu 24.04 LTS is the first and only tested target. Its archive versions [archive]:

| Tool | 24.04 (noble) | 22.04 (jammy) |
|---|---|---|
| git | 2.43.0 | **2.34.1**, older than the 2.36 needed for `git worktree list -z` |
| tmux | 3.4 | 3.2a |
| bash | 5.2.21 | 5.1 |
| ruby (`apt install ruby`) | 3.2.3 | 3.0.2 |
| coreutils | 9.4 | 8.32 |
| perl | 5.38.2 | 5.34.0 |
| procps | 4.0.4 | 3.3.17 |
| mawk | 1.3.4 (2024) | 1.3.4 (2020) |
| lsof (no longer needed on Linux) | 4.95.0 | 4.93.2 |

22.04 is not supported: its git is too old, and an older git from elsewhere would make it a different
host from the one tested. Other distributions are not supported. They may work, and the CI job would be
where support for one is proven. Packages to install on 24.04: `tmux git ruby` (plus `gh` and Claude
Code as on macOS, and `build-essential` for the e2e). Which of these a 24.04 server install already has
[not checked yet].

**macOS.** Unchanged: bash 3.2, the system Ruby 2.6, tmux as the e2e runs it today (3.7b), git 2.36 or
later. The code must keep running on bash 3.2 and Ruby 2.6, so nothing from bash 4 or later or Ruby 2.7
or later may be used, even though Linux has both. (The e2e on both platforms enforces this.)

**What "minimum" means.** The tested version, nothing older. This design does not claim that tmux 3.2
or Ruby 3.0 works, because nothing runs them. A minimum moves down only when CI runs the older version.

**How the requirements are checked.** `check` prints a `host` block: the platform, and the version of
bash, ruby, tmux, git, perl and claude, each with its tested minimum. Then:

- a missing tool is refused at startup, as `ruby` is now, with a message for the platform (`install it:
  sudo apt install ruby` on Linux, not "it ships with macOS");
- git older than 2.36 is refused, as it is today, where the worktree list is read;
- a version older than the tested one is a warning in `check` and nothing more. Refusing a version that
  is untested but probably fine would block a user for no proven reason, and the warning names what was
  tested.
- a locale that is not UTF-8 is a warning on Linux. `say` recognises Claude Code's input box by its
  U+2500 rules and the `❯` prompt, as captured from the pane. Whether Claude Code and tmux still draw and
  store those characters on a minimal server with `LANG` unset is [not checked yet]. If they do not,
  `say` refuses every send. That fails closed, but the reason would not be obvious.

## 7. How Linux support is tested

**The e2e suite on Linux.** One suite for both platforms. Each case uses the helpers through
`test/e2e/lib.sh`, which sources `lib/platform.sh`, instead of a raw `stat -f` or `sed -i ''` (`sed -i.bak
... && rm -f <file>.bak` works with both seds). Platform-only cases:

- **macOS only:** osascript and the generated AppleScript being run, the boot-volume link, APFS clones,
  the legacy lock path, and the stand-in `mount` table cases in `test/e2e/say.sh` (BSD format).
- **Linux only:** `mountinfo` parsing (escaped spaces, a name that is not valid UTF-8, a path that is
  in the table only through a link), `/proc/<pid>/exe` and `REPLACED`, `cwd_pids`, the view's refusal
  and `up` ending with status 0 when `display.iterm` is true, and `check`'s `noexec` and vfat warnings.

A case that does not run on this platform prints `skip: <name> (macOS only: <why>)` and is counted in
the summary (`pass=N fail=0 skip=M`). That way a run with every Linux case skipped cannot read as a pass.
The `mountinfo` parsing cases call a test entry, `ruby lib/platform.rb parse-mountinfo <file>`, on
fixture files. The decision path always reads `/proc/self/mountinfo` and has no override, so the test
entry cannot be used to fake a mount.

`TEST_VOLUME` on Linux names a real mount point the tester can write to, as on macOS. In CI that is a
tmpfs the job mounts with `sudo`. A tmpfs holds owners and modes and allows `exec`.

**CI.** `.github/workflows/linux.yml`:

- runs on `pull_request` and on `push` to `main`, on **`ubuntu-24.04`, pinned**, not `ubuntu-latest`,
  so the tested version is known and a runner image upgrade does not change it unannounced;
- `permissions: contents: read`, no secrets, no `pull_request_target`. A fork's PR then runs on
  GitHub's runner with nothing to steal, and never on a team's host (hard rule 9 is about this host, and
  the job does not change it);
- installs `tmux git ruby build-essential`, mounts a tmpfs at `/mnt/fab-e2e`, and runs the three gate
  commands plus `test/lint-portable.sh` with `TMUX` unset and `TEST_VOLUME=/mnt/fab-e2e`, with a time
  limit;
- starts with `continue-on-error: true`, named `linux (not yet required)`. Engineers with no Linux host
  then see Linux results on every PR while the wiring issues land. The last implementation issue removes
  `continue-on-error`. Making the check required on `main` is a branch-protection setting, which is the
  owner's to change.

A macOS CI job is not part of this design. The local gate runs on macOS on every PR already. A hosted
macOS job would need a disk image as its volume and costs more runner time. The owner can ask for it as
a separate issue.

**Not covered by any automated test:** a real Claude Code on Linux. The e2e uses its stand-in, so
`say`'s box recognition against the real Claude Code screen, the seat's hooks under the real Claude
Code, and cross-session messaging are checked only by the live check (issue G).

## 8. Cross-session messaging on Linux

What the documentation says [docs]:

- Same-machine messaging needs Claude Code v2.1.224 or later "on macOS and Linux, including Linux
  inside WSL 2", and it is "on with nothing to enable".
- On macOS and Linux it is delivered over a Unix domain socket for each session ("never through
  Anthropic servers"), restricted to the operating-system user. A session that cannot accept its socket
  directory falls back to `/tmp/cc-socks-<uid>`.
- The inbound rules (`crossSessionInbound`, the permission-mode classes, held messages and
  `dialogExpiry`) are described without any platform difference. The one difference documented is in
  verifying a session's own child processes, which on Linux works "even for a child that has already
  exited" and on macOS only while it runs. That affects a hook posting to its own session's socket, not
  seat-to-seat messages.
- "A session inside a container and a session on the host can't reach each other." Every seat of a team
  must run on the same side: all on the host, as fabrikito does.

What this design takes from it: no change to how seats message each other on Linux, and no
Linux-specific setting. All seats run as one user, so the per-user restriction is no obstacle.

[not checked yet], all of it, for want of a Linux host with a Claude Code login (activating one is the
owner's step): that `ListAgents` lists the seats and that `SendMessage` delivers between them; that the
hold rules behave as on macOS for a team in bypass mode; and where the socket goes when a seat's
`TMPDIR` is on a storage volume. A vfat or exFAT volume cannot hold a socket file at all, and the
documentation's fallback should apply. The live check (issue G) covers these.

## 9. Out of scope

- A view on Linux (section 4), WSL 2, distributions other than Ubuntu 24.04, and Ubuntu 22.04.
- Running seats as different OS users, or in containers.
- `systemd` user units to start a team at boot. A team still starts with `up` in a shell. Whether a
  host's `KillUserProcesses` setting ends the tmux server at logout (Ubuntu's default is not to) is a
  host setting for the docs to mention, not something fabrikito changes [not checked yet].
- The header comment fix of #370, which is its own issue.

## 10. Proposed implementation issues

Seven issues. The order keeps two engineers off one file at the same time. `fabrikito` (one file of
about 2,100 lines) is touched by A, B, D and E, so those four run one after another. C and F run beside
them on other files.

| Order | Issue | Runs beside | Files |
|---|---|---|---|
| 1 | A. Platform layer | (alone) | new `lib/platform.sh`, new `lib/platform.rb`, new `test/e2e/platform.sh`; `test/e2e.sh` (`AREAS`, the skip count); `test/e2e/lib.sh`; `fabrikito` (sources the layer, refuses an unknown platform: header only); `docs/how-it-works.md` (two rows in the parts table) |
| 2 | B. File and process checks through the layer | C, F | `fabrikito` (`copy_same_or_die`, `ensure_claude_copy`, `seat_exe`, `cwd_users`, `log_unsafe`, `say_box_blocked`, `status_box_notices`, `flush`, `run_osa`); `lib/stop_gate.sh`; `test/e2e/claude-copy.sh`, `boxtext.sh`, `hooks.sh`, `worktrees.sh` |
| 2 | C. Ruby side through the layer | B, F | `lib/team_config.rb`; `lib/run_exclusive.rb`; `test/e2e/exclusive.sh`, `settings.sh`, `say.sh` |
| 2 | F. Linux CI job, not yet required | B, C | new `.github/workflows/linux.yml` |
| 3 | D. Storage volume and view on Linux | (alone on `fabrikito`) | `fabrikito` (`require_volume`, `prepare_tmpdir`, `cmd_check` volume and view lines, `cmd_up`, `cmd_view`, launch-script comments); `test/e2e/view.sh`, `tmpdir.sh`, `config.sh`, `launch.sh`, `live.sh`; `test/live-env.sh` if needed |
| 4 | E. Requirements, lint, CI required | (alone) | `fabrikito` (header: missing-tool messages; `cmd_check`: host block, warnings); new `test/lint-portable.sh`; `.github/pull_request_template.md` and `CLAUDE.md` (the gate list); `.github/workflows/linux.yml` (removes `continue-on-error`); `test/e2e/warnings.sh` |
| 5 | G. Docs and live check on an Ubuntu host | (alone) | `README.md`, `docs/commands.md`, `docs/facts.md`, `docs/testing.md`, `docs/troubleshooting.md`, `docs/team-file.md`, `teams/example.yaml` (comments only); a live-check report as a comment on the issue |

D depends on C (`Platform.mounted?` reached through `cfg`) and on B (both edit `fabrikito`). E depends
on all of B, C, D and F: the lint can be enforced only when nothing it bans is left. Each issue keeps
macOS behaviour identical except where its criteria say otherwise, and each runs the whole gate on
macOS, plus the CI job's Linux run once F has landed.

### A. Platform layer: `lib/platform.sh` and `lib/platform.rb`

Scope: add both files with every function in section 2's tables, for both platforms. `fabrikito`
sources `lib/platform.sh` right after it finds `HERE`, and nothing else calls the layer yet. Add the new
e2e area `platform` and the skip count in `test/e2e.sh`.

Acceptance criteria:
- On macOS, each `fs_*`, `epoch_time` and `sha256_hex` helper prints exactly what today's BSD form prints
  for the same file or input (a case for each).
- Each helper prints nothing and exits non-zero for a path that is not there, and never prints other
  text on standard output on failure (a case for each).
- `fabrikito check` with a stand-in `uname` that prints `FreeBSD` exits 1 with `unsupported platform:
  FreeBSD` and reads no team file. With `Darwin` it behaves as before.
- `ruby lib/platform.rb parse-mountinfo <fixture>` prints the mount points of fixtures holding a
  `\040` space, a `\134` backslash and a name that is not valid UTF-8, each decoded correctly.
- `Platform.lock_dir` and `Platform.removable_root` return section 2's paths on each platform (unit
  cases through a test entry).
- The e2e summary counts skips, and a skipped case prints its reason.

### B. The launcher's file and process checks through the layer

Scope: replace every `stat -f`, `date -r`, `shasum`, `cp -c` and `lsof` in `fabrikito` and
`lib/stop_gate.sh` with the helpers. Move `run_osa` into `lib/platform.sh`. `ensure_claude_copy`
decides "another up made it" by whether its temp file is still there, as it does now, and no longer by
`mv -n`'s exit status: a non-zero exit with the temp file still there is treated the same way, and the
copy is then checked with `copy_same_or_die`. Convert the e2e areas listed.

Acceptance criteria:
- On Linux (the CI job), a second hard link to the message log, to a box record or to the stop gate's
  log or count makes `say` and the stop hook refuse, as on macOS. The cases fail on the current code
  under GNU `stat`.
- On Linux, a second `up` reuses the team's copy of `claude` instead of refusing it, and `.how` says
  `copy`.
- On Linux, `status` shows the copy's path in `EXE` for a running stand-in seat, and `REPLACED` after the
  file at that path is replaced (`/proc/<pid>/exe`). `lsof` is not needed.
- On Linux, `migrate` removes a clean worktree that no process works in, and refuses one that a running
  process works in, with no `lsof` installed.
- Status box notices and `flush` messages show the time on both platforms.
- With `shasum` missing, say's repeat refusal still works on Linux (`sha256sum`).
- macOS: every existing case passes unchanged.

### C. The Ruby side through the layer

Scope: in `lib/team_config.rb` use `Platform.fold` (on both platforms), `Platform.mounted?` and
`Platform.removable_root` in place of the `RUBY_PLATFORM` tests, the `mount` parse and the `/Volumes/`
match. Platform-specific examples go in the `storage.volume` message. Add a `cfg mounted <path>` entry
for the launcher. In `lib/run_exclusive.rb` use `Platform.lock_dir`, keeping the legacy path for macOS
only. Convert the e2e areas listed, and make the stand-in `mount` cases of `say.sh` macOS-only, with
their Linux equivalents in A's parse cases.

Acceptance criteria:
- On Linux, `validate` accepts `state:` under a mounted `/mnt/<name>` and refuses it under an unmounted
  one, with the message naming the mount point.
- On Linux, `other_teams` and `state:` overlap checks refuse two paths that differ only in case.
- On Linux, `run-exclusive` keeps its lock in `~/.local/state/fabrikito/` (home from the user database,
  not `$HOME`), and two runs exclude each other. On macOS the path and the legacy handling are unchanged.
- `ruby -c` passes and the e2e passes under Ruby 2.6 (macOS) and Ruby 3.2 (CI).

### D. The storage volume and the view on Linux

Scope: `require_volume`, `prepare_tmpdir` and `cmd_check` prove the volume with `cfg mounted`. `check`
shows the file-system type and the `noexec`, vfat/exFAT/NTFS and `/` notes of section 3. `up` skips the
view on Linux with its one line, `view` refuses there with the attach commands, and `view --print`
still prints. The launch script's comments no longer give macOS as the reason. Convert the e2e areas
listed.

Acceptance criteria:
- On Linux, `up` with `storage.volume` at an unmounted `/mnt/<name>` (an empty folder on `/`) refuses and
  creates nothing under it. With it mounted, worktrees and temp folders are made there.
- On Linux, `up` with `display.iterm: true` starts the seats, prints the no-view line and exits 0.
- On Linux, `view` exits 1 and prints an attach command for each running seat. `view --print` prints the
  same layout on both platforms.
- On Linux, `check` names the file-system type and warns on `noexec` and on a vfat volume, and the
  volume line says when the volume is `/`.
- macOS: every existing case passes unchanged, the iTerm view included.

### E. Requirements, the portability lint, and the CI job required

Scope: the `host` block and version warnings in `check`, and the missing-tool messages for the platform
(section 6). Add `test/lint-portable.sh` (section 2) and add it to the gate list in `CLAUDE.md` and in the
PR template. Remove `continue-on-error` from the CI job.

Acceptance criteria:
- `check` prints the platform and the version of each tool with its tested minimum, and warns for an
  older one (a stand-in `tmux -V` printing `tmux 3.1`).
- With `ruby` missing from `PATH` on Linux, `fabrikito` exits 1 and names `apt install ruby`.
- On Linux, a non-UTF-8 locale gives `check` a warning.
- `test/lint-portable.sh` passes on the tree, fails on a line added with `stat -f %z` to `fabrikito`,
  and passes when that line carries `# portable-ok:`.
- The CI job is green on `ubuntu-24.04` and fails the run when a case fails.

### F. A Linux CI job, not yet required

Scope: `.github/workflows/linux.yml` as section 7 describes, with `continue-on-error: true`. Adding a
workflow to a public repository is outward-facing, so the owner approves this issue on its own.

Acceptance criteria:
- The job runs on every PR and every push to `main`, on `ubuntu-24.04`, with `permissions: contents:
  read` and no secrets.
- It runs the syntax gates and the whole e2e with `TMUX` unset and `TEST_VOLUME` on a tmpfs it mounts,
  and its log shows the `pass=/fail=/skip=` summary.
- A failing case shows in the job's result (the job is red) without blocking a merge.

### G. Docs, and a live check on an Ubuntu host

Scope: the requirements and Linux notes in the docs listed: Ubuntu 24.04 packages, `storage.volume` on
Linux with an `fstab` mount for a server, no view, and `TEST_VOLUME` on Linux. `docs/facts.md` stops
listing Linux as unsupported. Then a live check on a real Ubuntu 24.04 host with a real Claude Code (the
owner activates its login): a two-seat throwaway team on a private tmux server (`test/live-env.sh`),
run up to `down`.

Acceptance criteria:
- The docs name Ubuntu 24.04 as the tested Linux, list its packages, and say what the view, the wrapper
  and the claude copy do there. `docs/facts.md` says so too, with a source for each statement.
- Live, on Ubuntu 24.04: `check` is valid, `up` starts both seats with no view and exits 0, `say`
  delivers into a real Claude Code input box, `SendMessage` between the two seats arrives (and holds, for
  two seats in bypass mode, as on macOS), `ListAgents` shows both, each seat's hooks run (session start
  note, message log, stop gate), `status` shows `EXE`, and `down --yes` stops both.
- The report names the Claude Code, tmux and Ruby versions it ran with, and anything that differed from
  macOS.

## Not verified

- Nothing on this page was run on Ubuntu. Everything marked [ran] ran on Debian 12 (coreutils 9.1) in a
  container. Whether Ubuntu 24.04's coreutils 9.4 behaves the same for `mv -n`, and what an Ubuntu server
  install has by default (`ruby`, `lsof`, `shasum`, a C compiler, a UTF-8 locale), was not checked.
- The e2e suite has never run on Linux. Which of its cases fail there beyond the forms listed in section 1
  is not known.
- Whether bash 5.2, Ruby 3.2, tmux 3.4 and mawk change any behaviour fabrikito relies on was not checked.
- Cross-session messaging, `say` against the real Claude Code screen, and the hooks were not run on Linux
  (section 8).
- The consequences in section 1 marked as inferred (the claude copy refused or mismatched, `seat_exe`'s
  answers, `up` exiting 1 at the view) were read from the code and from the `stat` output above, not run
  through `fabrikito` on Linux.
- Package versions come from the archive's listing, not from an installed host.
