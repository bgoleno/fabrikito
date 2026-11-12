#!/usr/bin/env bash
# Regression test of the tmux guard (test/guard/tmux, #307): the tmux first on the PATH of an e2e run and
# of test/live-env.sh run, which lets a call through only to a socket inside the run's own folders.
#
#   test/e2e-tmux-guard.sh [guard [live-env.sh]]     the guard to test, and the live-env.sh to test it
#                                                    with; the ones in this tree if not given
#
# It starts no tmux server and runs no tmux command, so it is safe on any machine, with a guard that is
# wrong too: the "real tmux" behind the guard is a stand-in that records its arguments and does nothing
# else, and every call runs with a PATH that holds the guard, the stand-in and the system's folders only.
# The default server's socket appears below as a path in arguments and variables; nothing connects to it.
# What a refusal must show: a status that is not 0, a message that names the call, and no line recorded
# by the stand-in, for `tmux ls` and for `tmux kill-server` alike.
# The nested runs of test/e2e.sh with the guard in place are in test/e2e-exit-trap.sh.
set -u
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UNDER=${1:-$SRC/test/guard/tmux}; UNDER_LE=${2:-$SRC/test/live-env.sh}
[ $# -le 2 ] && [ -f "$UNDER" ] && [ -f "$UNDER_LE" ] || { echo "usage: test/e2e-tmux-guard.sh [guard [live-env.sh]]   ($UNDER or $UNDER_LE is not a file)" >&2; exit 64; }
xt_tmp=${TMPDIR:-/tmp}; xt_tmp=${xt_tmp%/}
X=$(mktemp -d "$xt_tmp/e2e-guard.XXXXXX") || { echo "cannot make a scratch folder under $xt_tmp" >&2; exit 2; }
X=$(cd -P -- "$X" && pwd -P) || exit 2
uid=$(id -u); LOG=$X/calls.log; sys=/usr/bin:/bin:/usr/sbin:/sbin
# $X/g: the guard under test. $X/bin: the stand-in. $X/run: a run's folder, with its tmux folder and a
# state folder. $X/out: a folder that is not the run's. $X/src: a tree for test/live-env.sh and its guard.
R=$X/run; OWN=$R/tmux/tmux-$uid/default; DEF=/tmp/tmux-$uid/default
mkdir -p "$X/g" "$X/bin" "$X/cwd" "$R/tmux" "$R/state/tmux" "$X/out/d" "$X/out/tmux" "$X/out/t4/tmux-$uid" "$X/src/test/guard"
cp "$UNDER" "$X/g/tmux" && cp "$UNDER" "$X/src/test/guard/tmux" && cp "$UNDER_LE" "$X/src/test/live-env.sh" || exit 2
# One line for each call that got past the guard: its arguments, one to a field.
cat > "$X/bin/tmux" <<'EOF'
#!/bin/sh
{ printf 'tmux'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "${0%/*}/../calls.log"
exit 0
EOF
chmod +x "$X/g/tmux" "$X/bin/tmux" "$X/src/test/guard/tmux" "$X/src/test/live-env.sh"
# Nothing below runs unless tmux, without the guard, is the stand-in, and it records. Without that a guard
# that lets a call through would reach a real server, and a log that stays empty would prove nothing.
got=$(env -i PATH="$X/bin:$sys" /bin/sh -c 'command -v tmux')
[ "$got" = "$X/bin/tmux" ] || { echo "refusing to run: tmux would be '$got', not the stand-in $X/bin/tmux" >&2; rm -rf "$X"; exit 2; }
env -i PATH="$X/bin:$sys" tmux self test
[ "$(cat "$LOG" 2>/dev/null)" = "tmux	self	test" ] || { echo "refusing to run: the stand-in tmux did not record its call in $LOG" >&2; rm -rf "$X"; exit 2; }

n=0; f=0; allerr=
# limited <command...>: run it from $X/cwd; sets err (both streams) and rc. A call takes a few
# milliseconds. A guard that takes itself, or a second copy of itself, for the real tmux would call itself
# for ever, in one process (exec after exec): after 10 seconds that process and its children are stopped,
# and the check that follows fails. (A limit on processor time, ulimit -t, does not end such a loop on
# macOS: measured, it ran for minutes.)
limited() {
  local pid wd
  ( cd "$X/cwd" && exec "$@" ) > "$X/out.txt" 2>&1 & pid=$!
  ( sleep 10; pkill -P "$pid"; kill "$pid" ) > /dev/null 2>&1 & wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  pkill -P "$wd" 2>/dev/null; kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  err=$(cat "$X/out.txt")
}
def_before=absent; [ -e "/tmp/tmux-$uid" ] && def_before=there
# check <name> <status>: one check, passed when the status is 0. A failed one shows the last call.
check() {
  n=$((n+1)); if [ "$2" = 0 ]; then echo "ok   $1"; return; fi
  f=$((f+1)); echo "FAIL $1"; echo "  call: tmux $call (exit $rc)"; echo "  message: $err"; echo "  recorded: $rec"
}
# g [NAME=value | -NAME ...] -- <tmux arguments>: one call of the guard under test, from $X/cwd, in an
# environment that holds only PATH, HOME and the four variables below, changed as asked (-NAME drops one).
# Sets rc, err (what it printed, both streams), rec (what the stand-in recorded) and call.
g() {
  local -a e=("TMUX_GUARD_ROOTS=$R" "TMUX_GUARD_REAL=$X/bin/tmux" "TMUX_GUARD_LOG=$X/refused.log" "TMUX_TMPDIR=$R/tmux") k=()
  local a v
  while [ "$1" != -- ]; do
    case $1 in
      -*) a=${1#-}; k=(); for v in ${e[@]+"${e[@]}"}; do [ "${v%%=*}" = "$a" ] || k+=("$v"); done; e=(${k[@]+"${k[@]}"}) ;;
      *) e+=("$1") ;;
    esac
    shift
  done
  shift; call="$*"; : > "$LOG"; : > "$X/refused.log"
  limited env -i PATH="$X/g:$X/bin:$sys" HOME="$HOME" ${e[@]+"${e[@]}"} tmux "$@"
  rec=$(cat "$LOG"); allerr="$allerr$err"$'\n'
}
refused() { [ "$rc" != 0 ] && [ -z "$rec" ] && case $err in *"tmux-guard: refused: tmux $call:"*) true ;; *) false ;; esac; }
# both <name> [NAME=value | -NAME ...] [-- <tmux options>]: the call must be refused for ls and for kill-server
both() {
  local name=$1 c; local -a e=() o=(); shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done
  [ $# -gt 0 ] && shift; o=(${1+"$@"})
  for c in ls kill-server; do
    g ${e[@]+"${e[@]}"} -- ${o[@]+"${o[@]}"} $c; refused; check "refused, $name: tmux ${o[*]+${o[*]} }$c" $?
  done
}
# passed <name> <the arguments the stand-in must have got...>
passed() {
  local name=$1 want=tmux a; shift
  for a in "$@"; do want="$want	$a"; done
  [ "$rc" = 0 ] && [ "$rec" = "$want" ]; check "passed on, $name" $?
}
xt_socket() { ruby -rsocket -e 'UNIXServer.new(ARGV[0])' "$1"; }

echo "--- a call with no socket named: TMUX_TMPDIR, with none of tmux's fallback to /tmp"
g -- ls; passed "TMUX_TMPDIR is the run's tmux folder: the socket in it, by -S" -S "$OWN" ls
[ -d "${OWN%/*}" ] && [ ! -L "${OWN%/*}" ] && [ "$(stat -f %Lp "${OWN%/*}" 2>/dev/null || stat -c %a "${OWN%/*}")" = 700 ]; check "the guard made tmux-<uid> as tmux would have, mode 700" $?
g -- kill-server; passed "kill-server with TMUX_TMPDIR the run's tmux folder" -S "$OWN" kill-server
both "TMUX_TMPDIR is not set" -TMUX_TMPDIR
both "TMUX_TMPDIR is empty" TMUX_TMPDIR=
case $err in *"TMUX_TMPDIR is not set or is empty"*) true ;; *) false ;; esac; check "the message for an empty TMUX_TMPDIR says so" $?
both "TMUX_TMPDIR names a folder that is not there" "TMUX_TMPDIR=$R/gone"
case $err in *"TMUX_TMPDIR names a folder that is not there ($R/gone)"*) true ;; *) false ;; esac; check "the message for a TMUX_TMPDIR that is not there names the folder" $?
both "TMUX_TMPDIR holds a colon" "TMUX_TMPDIR=$R/tmux:$R/tmux"
mkdir "$R/a:b"
both "TMUX_TMPDIR is a folder of the run's with a colon in its name (a list of folders to tmux)" "TMUX_TMPDIR=$R/a:b"
both "TMUX_TMPDIR is /tmp" TMUX_TMPDIR=/tmp
both "TMUX_TMPDIR is another folder, outside the run's" "TMUX_TMPDIR=$X/out/tmux"
[ ! -e "$X/out/tmux/tmux-$uid" ]; check "the guard made no tmux-<uid> in a folder that is not the run's" $?
ln -s /tmp "$R/to-tmp"
both "TMUX_TMPDIR is a link in the run's folder that leads to /tmp" "TMUX_TMPDIR=$R/to-tmp"
mkdir -p "$R/t2" "$R/t3"; ln -s "$X/out/d" "$R/t2/tmux-$uid"; ln -s "/tmp/tmux-$uid" "$R/t3/tmux-$uid"
both "tmux-<uid> under TMUX_TMPDIR is a link that leads out of the run's folder" "TMUX_TMPDIR=$R/t2"
both "tmux-<uid> under TMUX_TMPDIR is a link to the one in /tmp" "TMUX_TMPDIR=$R/t3"
ln -s run "$X/lnk"
g "TMUX_TMPDIR=$X/lnk/tmux" -- ls; passed "TMUX_TMPDIR through a link that stays in the run's folder: the resolved path, as tmux uses" -S "$OWN" ls
g TMUX_TMPDIR=../run/tmux -- ls; passed "a relative TMUX_TMPDIR, from the current folder" -S "$OWN" ls
g TMUX=,1,0 -- ls; passed "a TMUX that names no socket is left aside, as tmux does" -S "$OWN" ls
g -- -L other ls; passed "-L: that name in the run's tmux folder" -S "$R/tmux/tmux-$uid/other" ls
both "-L with TMUX_TMPDIR gone" "TMUX_TMPDIR=$R/gone" -- -L other
both "-L with a name that leaves the folder" -- -L ../../../out/d/default

echo "--- a call inside a tmux pane: TMUX names the socket, and tmux follows it before TMUX_TMPDIR"
g "TMUX=$OWN,1,0" -TMUX_TMPDIR -- ls; passed "TMUX names the run's socket (TMUX_TMPDIR not set)" -S "$OWN" ls
both "TMUX names the socket in /tmp, with TMUX_TMPDIR the run's" "TMUX=$DEF,1,0"
both "TMUX names a socket outside the run's folder" "TMUX=$X/out/d/default,1,0"

echo "--- a call that names its socket: -S"
g -- -S "$OWN" ls; passed "-S to the run's socket, as written" -S "$OWN" ls
g -- -S "$R/state/tmux/server" has-session -t "=a b"; passed "-S to another socket in the run's folder (a state folder), arguments as given" -S "$R/state/tmux/server" has-session -t "=a b"
g -- -S "../run/tmux/tmux-$uid/default" ls; passed "-S with a relative path that stays inside" -S "../run/tmux/tmux-$uid/default" ls
g "TMUX=$DEF,1,0" -TMUX_TMPDIR -- -S "$OWN" ls; passed "-S to the run's socket, whatever TMUX and TMUX_TMPDIR say" -S "$OWN" ls
both "-S to the socket in /tmp" -- -S "$DEF"
both "-S to a socket outside the run's folder" -- -S "$X/out/d/default"
both "-S with a relative path that leaves the run's folder" -- -S ../out/d/default
both "-S into a folder that is not there (the guard makes none for -S)" -- -S "$R/none/server"
xt_socket "$X/out/d/default"; ln -s "$X/out/d/default" "$R/tmux/tmux-$uid/linked"
both "-S to a link in the run's folder that leads to a socket outside it" -- -S "$R/tmux/tmux-$uid/linked"
both "-S in a cluster of options (-uS)" -- -uS "$DEF"
# A folder with a line break in its path, made so that its second line reads as a folder of its own: the
# guard reads resolved paths one to a line, and must not take the first line for the socket's folder.
mkdir -p "$X/out/a" "$X/out/a
$X/out"
both "-S into a folder outside the run's with a line break in its path" -- -S "$X/out/a
$X/out/default"
g -- -S "$DEF" -S "$OWN" ls; passed "-S twice: the last one counts, as for tmux, and it is the run's" -S "$OWN" ls
both "-S twice, the last one the socket in /tmp" -- -S "$OWN" -S "$DEF"
# The user's id comes from the system. bash 3.2 and dash both take UID from the environment when it is there.
both "UID in the environment is another user's, the roots are /tmp, -S to the socket in /tmp" UID=12345 TMUX_GUARD_ROOTS=/tmp -- -S "$DEF"
g UID=12345 -- ls; passed "UID in the environment is another user's: the socket is still in tmux-<the real uid>" -S "$OWN" ls
# cd takes a folder named - for the one before (dash does, even after --): the socket's folder would then
# be judged as some other folder. Run under dash where there is one, as /bin/sh is not dash everywhere.
mkdir "$X/cwd/-" "$X/cwd/-/tmux-$uid"
for sh in /bin/sh /bin/dash; do
  [ -x "$sh" ] || continue
  : > "$LOG"; call="-S -/sock kill-server"; limited env -i PATH="$X/g:$X/bin:$sys" "OLDPWD=$X/cwd/-" "TMUX_GUARD_ROOTS=$R" "TMUX_GUARD_REAL=$X/bin/tmux" "$sh" "$X/g/tmux" -S -/sock kill-server; rec=$(cat "$LOG")
  refused; check "refused, -S into a folder named - outside the run's, which is also the folder before, OLDPWD ($sh)" $?
done
both "-S written in one word (-S<path>)" -- "-S$DEF"

echo "--- the run's folders: TMUX_GUARD_ROOTS"
both "TMUX_GUARD_ROOTS is not set" -TMUX_GUARD_ROOTS
both "TMUX_GUARD_ROOTS is empty" TMUX_GUARD_ROOTS=
both "TMUX_GUARD_ROOTS names a folder that is not there" "TMUX_GUARD_ROOTS=$X/gone"
both "TMUX_GUARD_ROOTS is relative" TMUX_GUARD_ROOTS=../run
both "TMUX_GUARD_ROOTS is . (were it taken from the socket's folder, every socket would be inside it)" TMUX_GUARD_ROOTS=. -- -S "$X/out/d/default"
both "TMUX_GUARD_ROOTS is .., with TMUX_TMPDIR outside the run's folder" TMUX_GUARD_ROOTS=.. "TMUX_TMPDIR=$X/out/t4"
both "TMUX_GUARD_ROOTS is /, with the socket in /tmp" TMUX_GUARD_ROOTS=/ TMUX_TMPDIR=/tmp
both "TMUX_GUARD_ROOTS is /, even for the run's own socket" TMUX_GUARD_ROOTS=/
both "TMUX_GUARD_ROOTS is /, -S to a socket directly in /" TMUX_GUARD_ROOTS=/ -- -S /default
both "TMUX_GUARD_ROOTS is /tmp, with the socket in /tmp (never the folder of the user's own servers)" TMUX_GUARD_ROOTS=/tmp TMUX_TMPDIR=/tmp
both "TMUX_GUARD_ROOTS is /tmp, -S to the socket in /tmp" TMUX_GUARD_ROOTS=/tmp -- -S "$DEF"
both "TMUX_GUARD_ROOTS is /tmp, -L in /tmp" TMUX_GUARD_ROOTS=/tmp TMUX_TMPDIR=/tmp -- -L other
g "TMUX_GUARD_ROOTS=$X/gone:$X/out:$R" -- ls; passed "several folders: a socket in the last one" -S "$OWN" ls
g "TMUX_GUARD_ROOTS=$X/lnk" -- ls; passed "a folder given through a link" -S "$OWN" ls
mkdir "$X/ru"
both "a folder whose name the run's only starts with" "TMUX_GUARD_ROOTS=$X/ru"
mkdir -p "$X/run2/tmux"
g "TMUX_GUARD_ROOTS=$X/run2" "TMUX_TMPDIR=$X/run2/tmux" -- ls; passed "a second run's folder, while it is there" -S "$X/run2/tmux/tmux-$uid/default" ls
rm -rf "$X/run2"
both "the run's folder removed mid-run, bare call" "TMUX_GUARD_ROOTS=$X/run2" "TMUX_TMPDIR=$X/run2/tmux"
both "the run's folder removed mid-run, -S to where its socket was" "TMUX_GUARD_ROOTS=$X/run2" -- -S "$X/run2/tmux/tmux-$uid/default"
both "the run's folder removed mid-run, TMUX still naming its socket" "TMUX_GUARD_ROOTS=$X/run2" "TMUX=$X/run2/tmux/tmux-$uid/default,1,0"
mkdir -p "$X/run3/tmux"; g "TMUX_GUARD_ROOTS=$X/run3" "TMUX_TMPDIR=$X/run3/tmux" -- ls; rm -rf "$X/run3/tmux"
both "only the run's tmux folder removed mid-run" "TMUX_GUARD_ROOTS=$X/run3" "TMUX_TMPDIR=$X/run3/tmux"

echo "--- tmux's own options"
g -- -2 -u -f /dev/null -T "256,RGB" new-session -d -s "a b" "echo 'x  y'"; passed "options before the command are kept, and every argument as given" -S "$OWN" -2u -f /dev/null -T "256,RGB" new-session -d -s "a b" "echo 'x  y'"
g -- -CC -N attach; passed "a flag given twice (-CC)" -S "$OWN" -CCN attach
g -- -- ls; passed "-- before the command" -S "$OWN" ls
# The guard puts its own -S before the caller's words. A word with a dash after -- is a command to tmux
# (and an error); passed on without the --, it would be an option, and a second -S is the one tmux takes.
both "-- and then -S: an option where the command belongs" -- -- -S "$DEF"
g -- -- -x; refused; check "refused, -- and then another word with a dash" $?
both "-T twice (tmux adds them up, the guard passes one)" -- -T 256 -T RGB
both "-f twice (tmux loads both, the guard passes one)" -- -f /dev/null -f /dev/null
g TMUX_TMPDIR= -- send-keys 'a\tb\c' x; refused && case $err in *'send-keys a\tb\c x: TMUX_TMPDIR is not set or is empty'*) true ;; *) false ;; esac
check "a refusal names the call as it was given, backslashes and all, and still gives its reason" $?
g -- ; passed "no command at all" -S "$OWN"
g -TMUX_GUARD_ROOTS -TMUX_TMPDIR -- -V; passed "-V reaches no server: passed on as it is, whatever the environment" -V
both "an option the guard does not know" -- -Z
g -- -S; refused; check "refused, -S with nothing after it" $?

echo "--- finding the real tmux, and the record of refusals"
g -TMUX_GUARD_REAL -- ls; passed "TMUX_GUARD_REAL not set: the first tmux on PATH that is not the guard" -S "$OWN" ls
g "TMUX_GUARD_REAL=$X/g/tmux" -- ls; passed "TMUX_GUARD_REAL names the guard itself: the next tmux on PATH, no loop" -S "$OWN" ls
g "TMUX_GUARD_REAL=$X/none/tmux" -- ls; passed "TMUX_GUARD_REAL names nothing: the next tmux on PATH" -S "$OWN" ls
# Two copies of the guard (a tree and an export of it, both with a guard on PATH) must not hand a call to
# each other for ever: a copy that has passed the call on is not taken for the real tmux again.
mkdir "$X/g2"; cp "$X/g/tmux" "$X/g2/tmux"; chmod +x "$X/g2/tmux"
: > "$LOG"; call=ls; limited env -i PATH="$X/g:$X/g2:$X/g:$X/bin:$sys" "TMUX_GUARD_ROOTS=$R" "TMUX_TMPDIR=$R/tmux" tmux ls; rec=$(cat "$LOG")
passed "two copies of the guard on PATH, the first one twice: the call ends at the real tmux" -S "$OWN" ls
: > "$LOG"; call=-V; limited env -i PATH="$X/g:$X/g2:$X/g:$X/bin:$sys" tmux -V; rec=$(cat "$LOG")
passed "two copies of the guard on PATH, the first one twice, -V" -V
g "TMUX_GUARD_REAL=$X/g2/tmux" -- ls; passed "TMUX_GUARD_REAL names a second copy of the guard that is not on PATH: the call ends at the real tmux" -S "$OWN" ls
# A stand-in before the guard on PATH that passes its calls on to it, as the areas of test/e2e/ build
# them: the guard must not take that stand-in for the real tmux, or the two call each other for ever.
mkdir "$X/shim"; printf '#!/bin/sh\nexec %s "$@"\n' "$X/g/tmux" > "$X/shim/tmux"; chmod +x "$X/shim/tmux"
: > "$LOG"; call=ls; limited env -i PATH="$X/shim:$X/g:$X/bin:$sys" "TMUX_GUARD_ROOTS=$R" "TMUX_TMPDIR=$R/tmux" tmux ls; rec=$(cat "$LOG")
passed "a stand-in before the guard on PATH that passes on to it: the real tmux is the one after the guard" -S "$OWN" ls
mkdir "$X/via"; ln -s "$X/g/tmux" "$X/via/tmux"
: > "$LOG"; limited env -i PATH="$X/via:$sys" "TMUX_GUARD_ROOTS=$R" "TMUX_GUARD_REAL=$X/bin/tmux" "TMUX_TMPDIR=$R/tmux" tmux ls; rec=$(cat "$LOG"); call=ls
passed "the guard reached through a link, with no other tmux on PATH" -S "$OWN" ls
: > "$LOG"; limited env -i PATH="$X/via:$sys" "TMUX_GUARD_ROOTS=$R" "TMUX_TMPDIR=$R/tmux" tmux ls; rec=$(cat "$LOG"); allerr="$allerr$err"$'\n'
refused; check "refused, no tmux but the guard on PATH and none named" $?
g TMUX_TMPDIR= -- kill-server
[ "$(cat "$X/refused.log")" = "$err" ] && [ -n "$err" ]; check "a refusal is appended to TMUX_GUARD_LOG, as printed" $?
g TMUX_TMPDIR= "TMUX_GUARD_LOG=$X/gone/refused.log" -- kill-server; refused && [ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" = 1 ]; check "refused all the same when TMUX_GUARD_LOG cannot be written, with one line printed" $?
# The launcher's own refusals are found in its output by these words (test/e2e/live.sh, say-sender.sh):
# a guard that printed them could make one of those cases pass without the launcher refusing anything.
! printf '%s' "$allerr" | grep -q -e "default tmux server" -e "--default-socket" -e "another tmux server" -e "terminal outside tmux"; check "no message of the guard holds the words the launcher's own refusals are recognised by" $?

echo "--- test/live-env.sh: run and down give a live test the same guard, for the environment's own folder"
LE=$X/src/test/live-env.sh
# le <NAME=value ...> -- <live-env arguments>: as g, without the guard on PATH unless an argument adds it
le() {
  local -a e=()
  while [ "$1" != -- ]; do e+=("$1"); shift; done
  shift; call="$*"; : > "$LOG"
  limited env -i PATH="$X/bin:$sys" HOME="$HOME" ${e[@]+"${e[@]}"} "$LE" "$@"
  rec=$(cat "$LOG"); allerr="$allerr$err"$'\n'
}
lerefused() { [ "$rc" != 0 ] && [ -z "$rec" ] && case $err in *"tmux-guard: refused: tmux "*) true ;; *) false ;; esac; }
d=$(env -i PATH="$X/bin:$sys" HOME="$HOME" "$LE" new 2>&1); dp=$(cd -P -- "$d" 2>/dev/null && pwd -P)
case $dp in */sf-live.??????) ;; *) dp=; echo "live-env new made no folder: $d" ;; esac
if [ -n "$dp" ]; then
  les=$dp/tmux/tmux-$uid/default
  le -- run "$d" tmux ls; passed "live-env run, a bare call: the environment's socket, by -S" -S "$les" ls
  le -- run "$d" /bin/sh -c 'command -v tmux'; [ "$err" = "$X/src/test/guard/tmux" ]; check "live-env run: tmux is the guard next to live-env.sh, first on PATH" $?
  le "TMUX_GUARD_ROOTS=$R" "PATH=$X/g:$X/bin:$sys" -- run "$d" tmux ls; passed "live-env run inside a guarded run (an e2e run): the environment's socket still" -S "$les" ls
  le -- run "$d" env TMUX_TMPDIR=/tmp tmux ls; lerefused; check "refused, live-env run with the command's own TMUX_TMPDIR=/tmp" $?
  le -- run "$d" env TMUX_TMPDIR= tmux kill-server; lerefused; check "refused, live-env run with the command's own empty TMUX_TMPDIR: tmux kill-server" $?
  le -- run "$d" tmux -S "$DEF" kill-server; lerefused; check "refused, live-env run with -S to the socket in /tmp: tmux kill-server" $?
  le -- run "$d" env "TMUX=$DEF,1,0" tmux ls; lerefused; check "refused, live-env run with the command's own TMUX on the socket in /tmp" $?
  le "TMUX_GUARD_ROOTS=$R" -- run "$d" tmux -S "$OWN" ls; lerefused; check "refused, live-env run with -S to a socket of the run around it: only the environment's own folder" $?
  le "TMUX_GUARD_ROOTS=$R" "TMUX_GUARD_REAL=$X/bin/tmux" "PATH=$X/g:$X/bin:$sys" -- down "$d"
  [ "$rc" = 0 ] && [ -z "$rec" ] && [ ! -e "$dp" ]; check "live-env down with no server started: no tmux call, the folder removed" $?
  d=$(env -i PATH="$X/bin:$sys" HOME="$HOME" "$LE" new 2>&1); dp=$(cd -P -- "$d" 2>/dev/null && pwd -P)
  case $dp in */sf-live.??????) ;; *) dp= ;; esac
fi
if [ -n "$dp" ]; then
  les=$dp/tmux/tmux-$uid/default; mkdir -m 700 "${les%/*}" && xt_socket "$les"
  le "TMUX_GUARD_ROOTS=$R" "TMUX_GUARD_REAL=$X/bin/tmux" "PATH=$X/g:$X/bin:$sys" -- down "$d"
  [ ! -e "$dp" ] && passed "live-env down inside a guarded run: kill-server to the environment's socket gets through, and the folder is removed" -S "$les" kill-server || check "live-env down inside a guarded run" 1
  case $dp in */sf-live.??????) if [ -d "$dp" ]; then rm -rf "$dp"; fi ;; esac
else
  check "live-env new makes a folder for the live-env checks" 1
fi

def_after=absent; [ -e "/tmp/tmux-$uid" ] && def_after=there
call=; rc=; err=; rec=; [ "$def_after" = "$def_before" ]; check "the guard made no /tmp/tmux-<uid>: it is as it was before these checks ($def_before)" $?
rm -rf "$X"
echo "e2e-tmux-guard: $n checks, $f failed"
[ "$f" -eq 0 ]
