#!/usr/bin/env bash
# End-to-end test of fabrikito in isolation: a private tmux server, a throwaway git repo,
# and a stand-in `claude` compiled as a real binary named claude (the launcher's process check
# looks at the process name). Worktrees go to a scratch folder on a REAL mounted volume
# (TEST_VOLUME, required, e.g. /Volumes/MyDrive) so the mount check is exercised for real; the
# folder is removed at the end. Needs: tmux, ruby, a C compiler, git.
set -u
[ -n "${TEST_VOLUME:-}" ] || { echo "set TEST_VOLUME to a mounted volume that can be written to, e.g. /Volumes/MyDrive" >&2; exit 64; }
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
S=$SRC/fabrikito
# The scratch folder. Cases in settings.sh and skills.sh check that a rule is written for a path both as
# configured ($T) and as its real path ($RT), so the two spellings must differ wherever TMPDIR is. They
# used to differ only by luck, through the /var and /tmp symlinks on macOS, and a TMPDIR on a volume has
# none (#249). So $T always runs through a link of its own, made here: <scratch>/l -> r. Both stay under
# TMPDIR and go when the scratch folder does. Remove $T_TOP, never $T: removing $T removes only the link.
# tmux's socket is $T/tmux/tmux-<uid>/default in either spelling, and tmux 3.7b on macOS refuses a path
# over 103 characters (File name too long, measured), which shows up as failures deep in the run. So a
# TMPDIR too long for it, in either of its own spellings, is refused here, before anything is made.
e2e_tmp=${TMPDIR:-/tmp}; e2e_tmp=${e2e_tmp%/}
e2e_sock=/team-e2e.XXXX/l/tmux/tmux-$(id -u)/default; e2e_max=$((103 - ${#e2e_sock}))
e2e_real=$(cd "$e2e_tmp" && pwd -P) || { echo "TMPDIR ($e2e_tmp) is not a folder this test can enter" >&2; exit 64; }
for e2e_p in "$e2e_tmp" "$e2e_real"; do
  [ ${#e2e_p} -le $e2e_max ] || { echo "TMPDIR is too long: $e2e_p has ${#e2e_p} characters and this test takes at most $e2e_max, because tmux's socket goes $e2e_sock below it (see docs/testing.md)" >&2; exit 64; }
done
# One heavy run at a time on the host (#309): the run starts itself again under fabrikito run-exclusive,
# whoever started it and from wherever, so two runs never overlap and nobody has to remember the lock. It
# waits its turn there, and run-exclusive says who holds the lock. Started under run-exclusive already,
# the call below is a nested one, which runs at once instead of waiting for itself.
# The step comes after the refusals above (a run that would be refused must not wait in the queue first)
# and before anything is made or cleared: the clearing below removes the lock's variables and gives the
# run a lock of its own, which is what keeps its run-exclusive cases off the real lock (#214). Arguments
# and the environment go to the second start as they are, so a run of part of the cases is covered too.
# The second start knows itself by E2E_LOCK_PID, the pid of the first start. run-exclusive keeps that pid
# (the first start execs it), so it is this shell's parent, or this shell itself when the call was nested
# (run-exclusive then execs the command). The variable alone is never trusted: left in an environment by
# anything else it names some other process, and the run takes the lock again. It is cleared below with
# the launcher's variables, so nothing the run starts has it.
# E2E_NO_LOCK=1 skips the step (docs/testing.md says when that is right), and only 1 does: any other
# value takes the lock, as the docs say (sec2 on #356). The stand-in runs inside test/e2e-exit-trap.sh
# set it: their tree's fabrikito is a stand-in, and they take a few seconds.
# The second start reads this file, and the tree, again after its wait, so what runs is the tree as it is
# then. A seat that moved its worktree to the next task while its run queued would get a result for
# another commit than the one it names (sec2 on #356). So the first start hands on what the tree was
# (E2E_LOCK_TREE, from e2e_tree), and the second stops, before anything is made, when that has changed.
# Not seen: more edits to a file that was already changed when the run queued, as its status line stays
# the same. docs/testing.md says to queue a run that will wait from an export of the commit.
# e2e_tree prints "<HEAD> <a digest of git status>", or nothing where there is nothing to hold the run
# to: $SRC is not itself the top of a git checkout (a stub tree or an export inside some other repository
# must not be judged by that repository's state), there is no commit yet, or git is missing or fails.
# Nothing recorded, or nothing to compare with after the wait, means no check, never a new failure.
e2e_tree() {
  local top head st
  top=$(GIT_OPTIONAL_LOCKS=0 git -C "$SRC" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || return 0
  [ "$(cd "$top" 2>/dev/null && pwd -P)" = "$(cd "$SRC" && pwd -P)" ] || return 0
  head=$(git -C "$SRC" rev-parse --verify -q HEAD 2>/dev/null) && [ -n "$head" ] || return 0
  # GIT_OPTIONAL_LOCKS=0: reading the status must not rewrite the index of a tree someone works in.
  st=$(GIT_OPTIONAL_LOCKS=0 git -C "$SRC" status --porcelain 2>/dev/null) || return 0
  st=$(printf '%s' "$st" | git hash-object --stdin 2>/dev/null) && [ -n "$st" ] || return 0
  echo "$head $st"
}
if [ "${E2E_NO_LOCK:-}" != 1 ]; then
  case ${E2E_LOCK_PID:-} in
    "$PPID" | "$$")
      e2e_now=$(e2e_tree)
      if [ -n "${E2E_LOCK_TREE:-}" ] && [ -n "$e2e_now" ] && [ "$e2e_now" != "$E2E_LOCK_TREE" ]; then
        if [ "${e2e_now%% *}" = "${E2E_LOCK_TREE%% *}" ]; then e2e_what="its changed or new files are no longer the same"; else e2e_what="it is now at ${e2e_now%% *}"; fi
        echo "test/e2e.sh: the tree changed while this run waited for the lock: it was queued at commit ${E2E_LOCK_TREE%% *}, and $e2e_what. Nothing was run, as the result would be for another tree than the one queued. Start the run again; to keep working while a run waits, queue it from an export or a separate worktree of the commit (docs/testing.md)." >&2
        exit 64
      fi ;;
    *) E2E_LOCK_PID=$$ E2E_LOCK_TREE=$(e2e_tree) exec "$S" run-exclusive -- "$BASH" "$SRC/test/e2e.sh" ${1+"$@"} ;;
  esac
fi
T_TOP=$(mktemp -d "$e2e_tmp/team-e2e.XXXX") || { echo "cannot make a scratch folder under $e2e_tmp" >&2; exit 2; }
mkdir "$T_TOP/r" && ln -s r "$T_TOP/l" && T=$(cd "$T_TOP/l" && pwd) || { echo "cannot make the scratch link under $T_TOP" >&2; exit 2; }
T_TOP=${T%/l}; mkdir -p $T/bin $T/tmux $T/local
ROOT="Projects/_teamtest-$$"; VOL=${TEST_VOLUME:-}
# Start from a clean environment. Run from a seat, this shell inherits what the seat's launcher
# and claude set there (DISABLE_AUTOUPDATER, TEAM_*, CLAUDE* including CLAUDE_CONFIG_DIR, TMUX*), and the test's tmux server
# and everything it starts would inherit it in turn: the leak check on DISABLE_AUTOUPDATER below
# would fail only when run from a seat, and a stand-in seat could reach the real seat's tmux or
# messaging socket (#75). This is the one list of what is cleared; add any new launcher variable here.
# It runs before anything below exports a TEAM_* variable (TEAM_VIEW=0), or it would clear it.
# FACTORY_*: run under run-exclusive (#214), the run inherits its lock's variables; nothing in it may
# take or skip the real lock, so the run has a lock of its own in $T. E2E_LOCK_PID, E2E_LOCK_TREE and
# E2E_NO_LOCK (#309, above): a test/e2e.sh that a case starts must not skip its lock step because this
# run did, nor be held to this run's tree.
for v in $(compgen -e); do case $v in DISABLE_AUTOUPDATER|TEAM_*|CLAUDE*|TMUX*|FACTORY_*|E2E_LOCK_PID|E2E_LOCK_TREE|E2E_NO_LOCK) unset "$v" ;; esac; done
export TMUX_TMPDIR=$T/tmux TEAM_STATE_DIR=$T/state FACTORY_RUN_LOCK=$T/rx-lock/run-exclusive.lock
# No run may drive iTerm (#93). A stand-in osascript first on PATH records every call and does
# nothing, and the run fails at the end if it was called: `up` opens a real iTerm window unless told
# not to, every run left its windows on the user's screen, and enough of them used up every pty on
# the machine, so tmux could no longer start the test's own seats. The view is off for the whole run
# (TEAM_VIEW=0), and every up says --no-view too, so dropping either one still opens no window.
printf '#!/bin/sh\necho "osascript $*" >> %s/osascript.log\nexit 1\n' "$T" > $T/bin/osascript; chmod +x $T/bin/osascript
export PATH=$T/bin:$PATH TEAM_VIEW=0
# The run's own tmux server, named by its socket (#306). The exit trap and the cleanup at the end stop it
# with e2e_stop_server and nothing else: never a bare `tmux kill-server`, which finds its server through
# TMUX_TMPDIR, and tmux falls back to /tmp, silently, when that folder does not exist. That is the default
# server, where a real team runs, and the folder is one this run removes. -S names the socket outright, so
# no other server can be reached, and a socket that is not there is skipped. Nothing on the way to it may
# be a link either, as tmux connects through links (test/live-env.sh down checks the same).
E2E_SOCK=$T/tmux/tmux-$(id -u)/default
e2e_own_server() { [ -S "$E2E_SOCK" ] && [ ! -L "$E2E_SOCK" ] && [ ! -L "${E2E_SOCK%/*}" ] && [ ! -L "$T/tmux" ]; }
e2e_stop_server() { e2e_own_server && tmux -S "$E2E_SOCK" kill-server 2>/dev/null; }
# True only in the shell that started the run. $$ is that shell's pid in every child too, and
# BASH_SUBSHELL is still 0 in the child that matters below, so this asks the kernel: the parent of a
# process that this shell starts is this shell. If /bin/sh cannot be started the answer is no, and nothing
# is cleaned up, which is the safe way to be wrong.
e2e_top() { [ "$(exec /bin/sh -c 'echo "$PPID"')" = "$$" ]; }
# Stopped early (a gate timeout kills this test's process group, a setup step exits, set -u trips):
# stop the private tmux server, which has left that group, and remove what the test made, as the
# cleanup at the end does. Not every assertion ran, so the exit status is never 0. The exit code is
# what a gate reads (repo.gate, lib/stop_gate.sh): only a run that reaches the end with fail=0 is 0.
# Invariant, here and in the cleanup at the end: the server is stopped before its folder is removed, and
# no tmux command runs once the folder is gone.
# LIVE_D (say-sender.sh) and TD (tmpdir.sh) are the two names the trap reads that an area sets later. They
# start empty, and not exported, so a run that ends before those areas acts on nothing: with a value from
# the caller's environment the trap would stop a live-test server and remove a folder that are not this
# run's (sec on #306). The scrub above covers the launcher's variables, not these.
unset LIVE_D TD; LIVE_D=; TD=
finished=
on_exit() {
  local rc=$?
  [ -n "$finished" ] && return
  # Under run-exclusive a signal to the process group reaches this shell twice (lib/run_exclusive.rb
  # passes it on as well), and the second would run the trap below inside this cleanup and end it early.
  # This comes before e2e_top, which starts a process: a TERM while it ran would end the shell there, with
  # no cleanup at all (tl on #318). In a child it changes nothing, as the child returns on the next line.
  trap '' TERM INT
  # Only the shell that started the run cleans up (#306). bash 3.2 expands the words of a simple command
  # in the child it forked for a pipeline or for &, before that child drops this trap: an unset variable
  # there (`echo "$out" | grep -q "$unset"`) ends the child, and the child runs this function. It used to
  # stop the server and remove the scratch folder under a run that carried on, and the next one found
  # TMUX_TMPDIR gone. A child removes nothing and stops nothing, and exits with the status it had.
  e2e_top || return 0
  e2e_stop_server
  [ -n "${LIVE_D:-}" ] && $SRC/test/live-env.sh down "$LIVE_D" 2>/dev/null
  for w in "$VOL/$ROOT"/*; do [ -d "$w" ] && git -C $T/repo worktree remove --force "$w" 2>/dev/null; done
  [ -n "${TD:-}" ] && rm -rf "$TD"; rmdir "$VOL/$ROOT" 2>/dev/null; rm -rf "$T_TOP"
  echo "ABORTED before the end (exit $rc): pass=${pass:-0} fail=${fail:-0}" >&2
  [ "$rc" -eq 0 ] && rc=1; exit "$rc"
}
trap on_exit EXIT
# The first signal ends the run, through on_exit. It ignores the next ones before it does: a second TERM a
# few milliseconds later would otherwise run `exit` again while on_exit starts, and end the shell before
# its cleanup (tl on #318).
trap 'trap "" TERM INT; exit 143' TERM INT
# Every name is kept, so the run can check, after the last assertion, that no two assertions print the
# same name (#163): a diff of the PASS lines of two runs could not tell them apart.
# An empty or whitespace-only name is a failure of its own (#169), reported at the file and line of the
# ok or bad call (BASH_SOURCE and BASH_LINENO, one level up). It is not kept: the check after the last
# assertion would miss an empty one anyway, as $(...) drops the empty line uniq -d prints.
# ok and bad still return 0, so "cond && ok x || bad x" never runs both.
pass=0; fail=0; e2e_names=
e2e_blank(){ case $1 in *[![:space:]]*) return 1 ;; esac
  echo "FAIL an assertion at ${BASH_SOURCE[2]#"$SRC"/}:${BASH_LINENO[1]} has an empty name: give it one"; fail=$((fail+1)); }
ok(){ echo "PASS $1"; pass=$((pass+1)); e2e_blank "$1" || e2e_names="$e2e_names$1"$'\n'; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); e2e_blank "$1" || e2e_names="$e2e_names$1"$'\n'; }
# The area files (#70) are sourced in the order of AREAS, in this shell, so they share the setup above,
# the count and the exit trap. Each holds a run of sections and relies on the state the areas before it
# leave. A file not listed here would never run, and sourcing a file with a syntax error runs part of it
# and carries on, so either one would lower the count without a failure: both stop the run here.
# bash -n does not catch every way a sourced file stops short: bash 3.2 passes a heredoc whose
# terminator does not match (sourced, it swallows the rest of the file and returns 0), and a top-level
# return, continue or break ends the file (continue and break also act on the loop that sources it).
# So each file's last line is e2e_end=<its name>, checked after it is sourced, and the list of files
# that got there is checked after the loop, which catches the continue and break that skip the check.
AREAS="launch settings say say-sender worktrees tmpdir view delivery boxtext config skills warnings gate hooks claude-copy prompts audit exclusive live"
E2E_DIR=$SRC/test/e2e
for e2e_f in "$E2E_DIR"/*.sh; do e2e_a=${e2e_f##*/}; e2e_a=${e2e_a%.sh}; [ "$e2e_a" = lib ] && continue
  case " $AREAS " in *" $e2e_a "*) ;; *) echo "test/e2e/$e2e_a.sh is not in AREAS in test/e2e.sh: add it there, or it never runs" >&2; exit 2 ;; esac
done
for e2e_a in lib $AREAS; do
  [ -f "$E2E_DIR/$e2e_a.sh" ] || { echo "test/e2e/$e2e_a.sh is missing" >&2; exit 2; }
  "$BASH" -n "$E2E_DIR/$e2e_a.sh" || { echo "test/e2e/$e2e_a.sh has a syntax error" >&2; exit 2; }
done
# throwaway repo with a "github" slug the origin URL contains
git init -q --bare $T/local/origin.git; git clone -q $T/local/origin.git $T/repo 2>/dev/null
(cd $T/repo && git commit -q --allow-empty -m init && git branch -M main && git push -q origin main)
# Git-ignored files a new worktree needs (#10): repo.copy brings them over from the main checkout,
# then repo.bootstrap (a stand-in that logs where it ran and whether the copy came first) runs there.
mkdir -p $T/repo/conf && echo "SECRET=1" > $T/repo/.env.local && echo '{"dev":true}' > $T/repo/conf/dev.json && printf '.env.local\nconf/\n' >> $T/repo/.git/info/exclude
printf '#!/bin/sh\necho "$TEAM_ROLE $(pwd -P) env=$(test -f .env.local && echo yes || echo no) repo=$TEAM_REPO" >> %s/boot.log\n' $T > $T/bin/boot; chmod +x $T/bin/boot
# fake claude: a real binary named claude (the process check looks at the process name). It
# draws Claude Code 2.1.316's input box as captured on 2026-10-30 (a rule naming the session from
# -n, cursor and no-break space, a plain rule, then a status line and the mode line; an empty box
# shows a dim hint) and redraws it after
# every key. Bracketed paste is on, so a pasted newline stays in the box and only a typed Enter
# submits. Every byte read goes to $FAKE_KEYLOG. Optional files per seat, named by $FAKE_FILES-*:
#   prompt  a dialog, drawn instead of the box     output  lines drawn above the box
#   mode    swallow (input never shows), below (a list under the box), prefill (text left in the box),
#           suggest (a dim suggested prompt in the empty box), sticky (that suggestion stays drawn after
#           any text), mixed (typed text and the dim suggestion), mention (the @-mention list drawn
#           above the box while its last word starts with @, no row highlighted, as after a paste),
#           mentionsel (text "sel @sr" with the list's first row highlighted: Enter completes it)
#           cut (the screen ends at the input row: no bottom rule and no footer, as a pane too
#           short for what is drawn above the box)
#           small (the tall box, with the seat's output file, the diff panel notice, drawn only
#           while the pane is under 110 columns; under it, at 13 rows or fewer, the screen ends at
#           the input row, as #95 measured), small-clean (the tall box with no notice; under 12
#           rows a paste grows the box past the bottom, so its rule and footer are gone, as qa2
#           measured on #73), small-slow (small-clean that waits 1.5s before redrawing after a
#           resize, as a busy seat might: until then the old, smaller frame stays on the screen)
# On SIGWINCH it redraws at the new size, as Claude Code does, with its rules as wide as the pane.
# A submitted line that starts with ! is run by /bin/sh the way Claude Code's Bash tool runs a
# command: in a child that leaves the pane's terminal (setsid), so the child has no tty of its own
# and only the stand-in, its parent, holds the pane's tty.
# Its source is test/e2e/fake-claude.c, copied to $T/c.c, where later sections recompile it.
cp "$SRC/test/e2e/fake-claude.c" $T/c.c || { echo "cannot copy test/e2e/fake-claude.c"; exit 2; }
cc -o $T/bin/claude $T/c.c || { echo "no compiler"; exit 2; }
printf '#!/bin/sh\necho "$TEAM_ROLE $1" >> %s/bin.log\nc=$1\nshift\necho "$TEAM_ROLE $*" >> %s/args.log\necho "$TEAM_ROLE DISABLE_AUTOUPDATER=${DISABLE_AUTOUPDATER-unset}" >> %s/env.log\necho "$TEAM_ROLE CLAUDE_CODE_DISABLE_AUTO_MEMORY=${CLAUDE_CODE_DISABLE_AUTO_MEMORY-unset}" >> %s/env.log\nexport FAKE_KEYLOG=%s/keys-$TEAM_ROLE.log FAKE_FILES=%s/fake-$TEAM_ROLE\nexec "$c" "$@"\n' $T $T $T $T $T $T > $T/bin/wrap; chmod +x $T/bin/wrap
mkdir -p $T/proj
cat > $T/team.yaml <<Y
team: tt
repo: { path: $T/repo, github: local/origin.git, base: origin/main, gate: "make check", gate_timeout: 120, gate_max_blocks: 2,
        bootstrap: "$T/bin/boot", copy: [.env.local, conf/dev.json, missing.txt] }
project: { name: TestBoard, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions:
  prefix: tt
  claude: { wrapper: $T/bin/wrap, permission_mode: bypassPermissions }
permissions:
  deny: ["Read(//**/.env)", "Bash(touch tt-deny*)"]
  ask: ["Bash(gh pr merge *)"]
  allow: ["Bash(npm test)"]
prompts: { common: $SRC/roles/common.md }
roles:
  em: { title: Manager, workdir: { type: project, path: $T/proj }, prompt_text: "em prompt" }
  w1: { title: Worker One, model: sonnet, effort: low, permission_mode: default, gate_on_stop: true, workdir: { type: worktree }, prompt_text: "w1 prompt",
        permissions: { deny: ["Bash(gh pr merge *)", "Read(//**/.env)"], allow: ["Bash(make *)"] } }
  w2: { title: Worker Two, auto_memory: true, workdir: { type: worktree }, prompt_text: "w2 prompt" }
Y
export PATH=$T/bin:$PATH
# legacy worktree for w2, internal disk
git -C $T/repo worktree add -q --detach $T/repo/.claude/worktrees/team-w2 origin/main
e2e_done=
for e2e_a in lib $AREAS; do
  e2e_end=
  . "$E2E_DIR/$e2e_a.sh"
  # An empty e2e_end means the file stopped short; any other value means its last line names another file.
  [ -n "$e2e_end" ] || { echo "test/e2e/$e2e_a.sh stopped before its last line (e2e_end=$e2e_a): a heredoc terminator that does not match, or a top-level return" >&2; exit 2; }
  [ "$e2e_end" = "$e2e_a" ] || { echo "test/e2e/$e2e_a.sh ends with the wrong marker: expected e2e_end=$e2e_a, found e2e_end=$e2e_end" >&2; exit 2; }
  e2e_done="$e2e_done $e2e_a"
done
[ "$e2e_done" = " lib $AREAS" ] || { for e2e_x in lib $AREAS; do case "$e2e_done " in *" $e2e_x "*) ;; *) break ;; esac; done
  echo "test/e2e/$e2e_x.sh did not run to its last line (these did:$e2e_done): a top-level continue or break" >&2; exit 2; }
echo "--- iTerm"
[ ! -e $T/osascript.log ] && ok "nothing in this run called osascript, so no iTerm window was opened" || { bad "osascript was called $(wc -l < $T/osascript.log | tr -d ' ') time(s)"; cut -c1-120 $T/osascript.log | head -5; }
echo "--- cleanup"
# down finds its server through TMUX_TMPDIR, so it runs only while the run's own socket is there (#306).
e2e_own_server && $S -c $T/team.yaml down --yes >/dev/null 2>&1; e2e_stop_server
for w in team-w1 team-w2; do git -C $T/repo worktree remove --force $VOL/$ROOT/$w 2>/dev/null; git -C $T/repo worktree remove --force $T/repo/.claude/worktrees/$w 2>/dev/null; done
rmdir $VOL/$ROOT 2>/dev/null; [ ! -e $VOL/$ROOT ] && ok "test folder removed from the volume" || bad "test folder removed from the volume ($(ls -A $VOL/$ROOT 2>&1 | head -3))"
rm -rf "$T_TOP"; [ ! -e "$T_TOP" ] && ok "the scratch folder under TMPDIR is removed, and the link in it" || bad "the scratch folder is still there: $T_TOP"
# No two assertions may print the same name (#163). This is not an assertion itself, so the count stays
# the number of assertions; each name printed more than once is one more failure.
e2e_dup=$(printf '%s' "$e2e_names" | LC_ALL=C sort | LC_ALL=C uniq -d)
if [ -n "$e2e_dup" ]; then
  printf '%s\n' "$e2e_dup" | sed 's/^/FAIL two or more assertions print this name (give each its own, or a PASS-line diff cannot tell them apart): /'
  fail=$((fail + $(printf '%s\n' "$e2e_dup" | wc -l)))
fi
echo "RESULT pass=$pass fail=$fail"
finished=1; [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
