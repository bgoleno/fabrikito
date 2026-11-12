#!/usr/bin/env bash
# Regression test of the exit trap and the cleanup of test/e2e.sh (#306): no tmux command they run may
# reach a server other than the run's own, and a child of the run that exits early cleans up nothing.
# And of the tmux guard in a run (#307, test/guard/tmux): once the run's folders are gone, mid-run or after
# the exit trap, a tmux call from the run or from a job it left behind fails at the guard and reaches no
# server at all. The guard alone, call by call, is test/e2e-tmux-guard.sh.
#
#   test/e2e-exit-trap.sh [e2e.sh]     the file to test; test/e2e.sh next to this one if not given
#
# It starts no tmux server and runs no tmux command, so it is safe on any machine, on the old code too:
#   git show <base>:test/e2e.sh > "$TMPDIR/old-e2e.sh" && test/e2e-exit-trap.sh "$TMPDIR/old-e2e.sh"
# It runs the file under test as it is, from a scratch tree where every area is a stub and the first one
# is a fixture, with three stand-ins that record their call and do nothing else: a tmux first on PATH, and
# the tree's fabrikito and test/live-env.sh. The fixture makes a socket file where the run's tmux server
# would have its own (a file only, nothing listens), so the cleanup has a socket to find. The caller's
# LIVE_D and TD, which the exit trap of the old code acts on, are kept out of every nested run.
# The tree also gets the guard of the tree this script is in. A file under test that puts it first on PATH
# (#307) then has the stand-in behind it as its real tmux, so the stand-in records what the guard lets
# through; a file from before that does not use it, and its calls reach the stand-in as they are.
#
# What trips is the shape seen on 2026-11-10, `echo x | grep -q "$unset"` under set -u. bash 3.2 (the bash
# of macOS) expands a simple command's words in the child it forked for a pipeline or for &, before that
# child drops the parent's traps: an unset variable there ends the child, and the child runs the parent's
# EXIT trap, with BASH_SUBSHELL still 0. A { ...; } group, a function, $(...) and ( ... ) do not do that.
set -u
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UNDER=${1:-$SRC/test/e2e.sh}
[ $# -le 1 ] && [ -f "$UNDER" ] || { echo "usage: test/e2e-exit-trap.sh [e2e.sh]   ($UNDER is not a file)" >&2; exit 64; }
areas=$(sed -n 's/^AREAS="\(.*\)"$/\1/p' "$UNDER"); first=${areas%% *}
[ -n "$first" ] || { echo "no AREAS=\"...\" line in $UNDER" >&2; exit 2; }
xt_tmp=${TMPDIR:-/tmp}; xt_tmp=${xt_tmp%/}
X=$(mktemp -d "$xt_tmp/e2e-trap.XXXXXX") || { echo "cannot make a scratch folder under $xt_tmp" >&2; exit 2; }
LOG=$X/calls.log; uid=$(id -u)
mkdir -p "$X/bin" "$X/src/test/e2e" "$X/vol"
cp "$UNDER" "$X/src/test/e2e.sh" || exit 2
# The stand-in claude of the tree this script is in, as the file under test compiles it: one case runs it.
cp "$SRC/test/e2e/fake-claude.c" "$X/src/test/e2e/fake-claude.c" || exit 2
for a in lib $areas; do echo "e2e_end=$a" > "$X/src/test/e2e/$a.sh"; done
if [ -f "$SRC/test/guard/tmux" ]; then mkdir "$X/src/test/guard" && cp "$SRC/test/guard/tmux" "$X/src/test/guard/tmux" && chmod +x "$X/src/test/guard/tmux" || exit 2; fi
# The stand-ins. Each line they write is one call: what it would have reached, then its arguments. They
# touch nothing else: not the socket they are given, which could be anyone's if the code under test is wrong.
cat > "$X/bin/tmux" <<'EOF'
#!/bin/sh
d=no; [ -d "${TMUX_TMPDIR-}" ] && d=yes
s=-; if [ "${1-}" = -S ]; then s=no; [ -S "${2-}" ] && s=yes; fi
printf 'tmux\ttmpdir=%s\tdir=%s\tTMUX=%s\tsock=%s\t%s\n' "${TMUX_TMPDIR-unset}" "$d" "${TMUX-unset}" "$s" "$*" >> "${0%/*}/../calls.log"
exit 1
EOF
cat > "$X/src/fabrikito" <<'EOF'
#!/bin/sh
s=no; [ -S "${TMUX_TMPDIR-}/tmux-$(id -u)/default" ] && s=yes
printf 'fabrikito\tsock=%s\t%s\n' "$s" "$*" >> "${0%/*}/../calls.log"
EOF
cat > "$X/src/test/live-env.sh" <<'EOF'
#!/bin/sh
printf 'live-env\t%s\n' "$*" >> "${0%/*}/../../calls.log"
EOF
chmod +x "$X/bin/tmux" "$X/src/fabrikito" "$X/src/test/live-env.sh"
# Nothing below runs unless tmux, on the PATH the run under test gets, is the stand-in, and it records.
# Without that, the old code would reach a real server, and a log that stays empty would prove nothing.
xt_path=$X/bin:$PATH
got=$(env PATH="$xt_path" /bin/sh -c 'command -v tmux')
[ "$got" = "$X/bin/tmux" ] || { echo "refusing to run: tmux would be '$got', not the stand-in $X/bin/tmux" >&2; rm -rf "$X"; exit 2; }
env PATH="$xt_path" TMUX_TMPDIR="$X/none" tmux self-test
[ "$(cat "$LOG" 2>/dev/null)" = "tmux	tmpdir=$X/none	dir=no	TMUX=${TMUX-unset}	sock=-	self-test" ] || { echo "refusing to run: the stand-in tmux did not record its call in $LOG" >&2; rm -rf "$X"; exit 2; }

n=0; f=0
# check <name> <status>: one check, passed when the status is 0
check() { n=$((n+1)); if [ "$2" = 0 ]; then echo "ok   $1"; else f=$((f+1)); echo "FAIL $1"; fi; }
# nested <fixture> [NAME=value ...]: run the file under test with this fixture as its first area, and
# with these variables in its environment. Sets out and rc, and what the fixture wrote down: t and top (the
# run's $T and $T_TOP), own (its server's socket), marks. LIVE_D and TD are the names the exit trap reads
# that only an area sets: the caller's own values never reach a nested run, so not even the old code under
# test can act on them. The one case that sets them names folders in this test's scratch folder.
nested() {
  local fixture=$1; shift
  rm -f "$X/t" "$X/top" "$X/tp" "$X/marks" "$X/tries" "$X/refused"; : > "$LOG"; f0=$f
  { cat <<'EOF'
xt_x=$SRC/..; echo "$T" > "$xt_x/t"; echo "$T_TOP" > "$xt_x/top"; (cd -P "$T" && pwd -P) > "$xt_x/tp"
# xt_try <command...>: a tmux call the guard is expected to judge. What it printed and its status go to
# tries; its refusal, if any, to a record of its own and not to the run's, which must stay empty.
xt_try() { local o rc; o=$(TMUX_GUARD_LOG="$xt_x/refused" "$@" 2>&1); rc=$?; echo "rc=$rc $*: $o" >> "$xt_x/tries"; }
xt_sock=$T/tmux/tmux-$(id -u)/default; mkdir -p -m 700 "${xt_sock%/*}"
xt_socket() { ruby -rsocket -e 'UNIXServer.new(ARGV[0])' "$1"; }
xt_mark() { if [ -d "$T/bin" ] && [ -S "$xt_sock" ]; then echo "$1: kept"; else echo "$1: gone"; fi >> "$xt_x/marks"; }
EOF
    printf '%s\n' "$fixture"; } > "$X/src/test/e2e/$first.sh"
  out=$(env -u LIVE_D -u TD PATH="$xt_path" TEST_VOLUME="$X/vol" ${1+"$@"} "$BASH" "$X/src/test/e2e.sh" 2>&1); rc=$?
  t=$(cat "$X/t" 2>/dev/null); top=$(cat "$X/top" 2>/dev/null); own=$t/tmux/tmux-$uid/default
  marks=$(cat "$X/marks" 2>/dev/null); tries=$(cat "$X/tries" 2>/dev/null)
  # the same socket by its resolved path, which is how the guard (as tmux) names one found through TMUX_TMPDIR
  ownp=$(cat "$X/tp" 2>/dev/null)/tmux/tmux-$uid/default
}
# The recorded tmux calls that could have reached a server other than the run's own: one through -S to
# another socket, or one that leaves the choice to tmux (no -S) when TMUX is set, or when TMUX_TMPDIR is
# not the run's own folder or that folder is not there (tmux then falls back to /tmp, the default server).
leaks() {
  local kind tmpd dir tm sock args
  while IFS=$'\t' read -r kind tmpd dir tm sock args; do
    [ "$kind" = tmux ] || continue
    case $args in
      "-S $own "*|"-S $ownp "*) continue ;;
      -S*) ;;
      *) [ "$tmpd" = "tmpdir=$t/tmux" ] && [ "$dir" = dir=yes ] && [ "$tm" = TMUX=unset ] && continue ;;
    esac
    echo "$tmpd $dir $tm: tmux $args"
  done < "$LOG"
}
calls() { grep -c "^$1	" "$LOG"; }
aborted() { printf '%s\n' "$out" | grep -c '^ABORTED before the end'; }
# The one call that stops the run's own server: through its socket, made while the socket was still there.
killed_own_once() { [ "$(grep '^tmux	' "$LOG")" = "tmux	tmpdir=$t/tmux	dir=yes	TMUX=unset	sock=yes	-S $own kill-server" ]; }
# After a run's checks: what it printed and recorded if one of them failed, and its scratch folder removed
# if the run left it (by the path the fixture wrote down, and only one shaped like the run's own).
finish() {
  if [ "$f" -ne "$f0" ]; then
    echo "  --- its output (last 12 lines)"; printf '%s\n' "$out" | tail -12 | sed 's/^/  /'
    echo "  --- its marks"; printf '%s\n' "$marks" | sed 's/^/  /'
    if [ -n "$tries" ]; then echo "  --- its tmux calls and what came of them"; printf '%s\n' "$tries" | sed 's/^/  /'; fi
    echo "  --- the calls recorded"; sed 's/^/  /' "$LOG"
  fi
  case $top in "$xt_tmp"/team-e2e.????) if [ -d "$top" ]; then rm -rf "$top"; fi ;; esac
}

echo "--- an unset variable in a pipeline, then again, and the run carries on to its end (2026-11-10)"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
echo x | grep -q "$xt_unset_1"
xt_mark "after an unset variable in a pipeline"
echo x | grep -q "$xt_unset_2"
xt_mark "after a second one"
grep -q "$xt_unset_3" /dev/null &
wait $!
xt_mark "after one in a background command"
xt_v=$(grep -q "$xt_unset_4" /dev/null)
xt_mark "after one in a command substitution"
( grep -q "$xt_unset_5" /dev/null )
xt_mark "after one in parentheses"
e2e_end='"$first"
want="at the start: kept
after an unset variable in a pipeline: kept
after a second one: kept
after one in a background command: kept
after one in a command substitution: kept
after one in parentheses: kept"
[ "$marks" = "$want" ]; check "a child that exits early removes nothing: the scratch folder and the socket are there after each of the five" $?
[ "$(aborted)" = 0 ]; check "no child ran the cleanup: ABORTED is never printed" $?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qE '^RESULT pass=[1-9][0-9]* fail=0$'; check "the run reaches its end and exits 0 (exit $rc)" $?
[ -z "$(leaks)" ]; check "no tmux call could reach a server other than the run's own" $?
killed_own_once; check "the cleanup at the end stops the server once, through its socket (-S), while the socket is there" $?
[ "$(calls fabrikito)" = 1 ] && [ "$(head -1 "$LOG")" = "fabrikito	sock=yes	-c $t/team.yaml down --yes" ]; check "down --yes runs once, before that, while the socket is there" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "the scratch folder is removed at the end" $?
finish

echo "--- an unset variable in a pipeline, then one in the run's own shell"
nested 'xt_socket "$xt_sock"
echo x | grep -q "$xt_unset_1"
xt_mark "after an unset variable in a pipeline"
: "$xt_unset_top"
xt_mark "after the one that ends the run"'
[ "$marks" = "after an unset variable in a pipeline: kept" ]; check "the child removes nothing, and the run ends at the unset variable in its own shell" $?
[ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "the cleanup runs once, in the run's own shell: one ABORTED line, exit not 0 (exit $rc)" $?
[ -z "$(leaks)" ]; check "aborted: no tmux call could reach a server other than the run's own" $?
killed_own_once; check "the exit trap stops the server once, through its socket (-S), before the folder is removed" $?
[ "$(grep -c '^fabrikito	sock=no' "$LOG")" = 0 ]; check "aborted: fabrikito is not run without the run's own socket" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "the scratch folder is removed by the exit trap" $?
finish

echo "--- the scratch folder is gone when the exit trap runs"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
rm -rf "$T_TOP"
: "$xt_unset_top"'
[ "$marks" = "at the start: kept" ] && [ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "folder gone: the exit trap ran, in the run's own shell (exit $rc)" $?
[ "$(calls tmux)" = 0 ]; check "folder gone: a socket that is not there is skipped, no tmux call at all" $?
[ "$(calls fabrikito)" = 0 ]; check "folder gone: fabrikito is not run" $?
finish

echo "--- the tmux folder is gone when the run reaches its end"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
rm -rf "$T/tmux"
e2e_end='"$first"
[ "$marks" = "at the start: kept" ] && [ "$rc" = 0 ] && [ "$(aborted)" = 0 ]; check "tmux folder gone: the run reaches its end (exit $rc)" $?
[ "$(calls tmux)" = 0 ]; check "tmux folder gone: the cleanup at the end makes no tmux call" $?
[ "$(calls fabrikito)" = 0 ]; check "tmux folder gone: down --yes is not run (it would find its server through TMUX_TMPDIR)" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "tmux folder gone: the scratch folder is still removed" $?
finish

# tmux connects through a link at any of the three places below the scratch folder, so each one is a case:
# the socket there leads to another server's (a socket file elsewhere in the scratch folder, with short
# names, so that no socket path is longer than the run's own).
linked() { # linked <what is a link> <fixture lines that make it one>
  echo "--- $1 is a link to another server's"
  nested "$2"'; xt_mark "at the start"
: "$xt_unset_top"'
  [ "$marks" = "at the start: kept" ] && [ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "linked $1: the exit trap ran, in the run's own shell (exit $rc)" $?
  [ "$(calls tmux)" = 0 ]; check "linked $1: skipped, no tmux call at all (tmux would follow the link)" $?
  [ -n "$top" ] && [ ! -e "$top" ]; check "linked $1: the scratch folder is still removed" $?
  finish
}
linked "socket" 'xt_socket "$T/os"; ln -s "$T/os" "$xt_sock"'
linked "tmux-<uid>" 'rmdir "${xt_sock%/*}"; mkdir -m 700 "$T/od"; xt_socket "$T/od/default"; ln -s "$T/od" "${xt_sock%/*}"'
linked "tmux/" 'rmdir "${xt_sock%/*}" "$T/tmux"; mkdir -p -m 700 "$T/ot/tmux-$(id -u)"; xt_socket "$T/ot/tmux-$(id -u)/default"; ln -s "$T/ot" "$T/tmux"'

# A signal must not end the cleanup of the run's own shell before it starts (tl on #318). Neither case
# depends on timing: the fixture puts a wrapper around a function of the file under test, which sends the
# TERM at the exact point, to the run's own shell ($$), and then runs the real function.
echo "--- a TERM arrives while the exit trap works out which shell it is in"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
eval "xt_orig_$(declare -f e2e_top)"; e2e_top() { kill -TERM $$; xt_orig_e2e_top; }
: "$xt_unset_top"'
[ "$marks" = "at the start: kept" ] && [ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "TERM in the exit trap: the cleanup still runs to its end, one ABORTED line (exit $rc)" $?
killed_own_once; check "TERM in the exit trap: the server is still stopped, once, through its socket" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "TERM in the exit trap: the scratch folder is still removed" $?
finish

echo "--- a TERM ends the run, and a second one arrives as the exit trap starts (run-exclusive passes it on too)"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
xt_status() { return "$1"; }
eval "xt_orig_$(declare -f on_exit)"; on_exit() { local xt_rc=$?; kill -TERM $$; xt_status $xt_rc; xt_orig_on_exit; }
kill -TERM $$
xt_mark "after the TERM"'
[ "$marks" = "at the start: kept" ] && [ "$rc" = 143 ] && [ "$(aborted)" = 1 ]; check "second TERM: the cleanup still runs to its end, one ABORTED line, exit 143 (exit $rc)" $?
killed_own_once; check "second TERM: the server is still stopped, once, through its socket" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "second TERM: the scratch folder is still removed" $?
finish

# The tmux guard in a run (#307). A call the guard refuses must show three things: a status that is not 0,
# the guard's message naming the call, and no line from the stand-in, which is all a real tmux would get.
# refused_tries <n>: the fixture's last n tmux calls all failed at the guard, each named in its message
refused_tries() {
  local n=$1 last
  last=$(printf '%s\n' "$tries" | tail -n "$n")
  [ "$(printf '%s\n' "$last" | grep -c '^rc=1 .*: tmux-guard: refused: tmux ')" = "$n" ] && [ "$(wc -l < "$X/refused" 2>/dev/null | tr -d ' ')" = "$n" ]
}
echo "--- the run's tmux folder is removed mid-run, and the run goes on making tmux calls"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
xt_try tmux ls
rm -rf "$T/tmux"
xt_try tmux ls
xt_try tmux kill-server
xt_try tmux has-session -t "=tt-em"
xt_try env TMUX_TMPDIR= tmux kill-server
xt_try env -u TMUX_TMPDIR tmux kill-server
xt_try env TMUX=/tmp/tmux-$(id -u)/default,1,0 tmux kill-server
xt_try tmux -S "$xt_sock" kill-server
xt_try tmux -S /tmp/tmux-$(id -u)/default kill-server
e2e_end='"$first"
[ "$(printf '%s\n' "$tries" | head -1)" = "rc=1 tmux ls: " ] && [ "$(grep '^tmux	' "$LOG")" = "tmux	tmpdir=$t/tmux	dir=yes	TMUX=unset	sock=yes	-S $ownp ls" ]
check "folder there: a bare tmux ls is passed on once, with -S and the run's own socket (the stand-in fails it, with no message)" $?
refused_tries 8; check "folder gone: bare ls, kill-server and has-session, and kill-server with TMUX_TMPDIR empty or unset, with TMUX or -S on /tmp, or with -S where the socket was, all fail at the guard, each named" $?
[ "$(calls tmux)" = 1 ]; check "folder gone: nothing but that first call reached tmux, so nothing was sent to the socket in /tmp" $?
[ "$rc" = 0 ] && [ "$(aborted)" = 0 ] && printf '%s\n' "$out" | grep -qE '^RESULT pass=[1-9][0-9]* fail=0$'; check "folder gone: the run still reaches its end (exit $rc)" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "folder gone mid-run: the scratch folder is removed at the end" $?
finish

echo "--- the whole scratch folder is removed mid-run"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
rm -rf "$T_TOP"
xt_try tmux ls
xt_try tmux kill-server
xt_try env TMUX=/tmp/tmux-$(id -u)/default,1,0 tmux kill-server
: "$xt_unset_top"'
refused_tries 3; check "scratch folder gone: the guard is still the tmux on PATH (it is in the tree), and bare ls and kill-server fail at it, each named" $?
[ "$(calls tmux)" = 0 ]; check "scratch folder gone: no tmux call reached tmux at all" $?
finish

# tl on #318: the exit trap does not stop a job the run left in the background, and its later tmux calls
# find TMUX_TMPDIR gone. The job here ignores the signals, waits until the trap has removed the folder,
# then calls tmux as an area's background `up` or `say` would. nested returns when the job has ended,
# because the job holds the pipe its output is read from.
echo "--- a job the run left in the background calls tmux after the exit trap has removed the folder"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
( trap "" TERM INT HUP
  while [ -e "$T_TOP" ]; do sleep 0.2; done
  xt_try tmux ls
  xt_try tmux kill-server
  xt_try tmux send-keys -t "=tt-em:" Enter ) &
: "$xt_unset_top"'
[ "$marks" = "at the start: kept" ] && [ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "background job: the exit trap ran, in the run's own shell (exit $rc)" $?
refused_tries 3; check "background job: its ls, kill-server and send-keys after the trap all fail at the guard, each named" $?
killed_own_once; check "background job: the one call that reached tmux is the trap's own, through the run's socket while it was there" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "background job: the scratch folder is removed" $?
finish

echo "--- a tmux that lands in the run's own bin folder does not come before the guard"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
printf "#!/bin/sh\\necho reached >> %s/bypass\\nexit 0\\n" "$xt_x" > "$T/bin/tmux"; chmod +x "$T/bin/tmux"; hash -r
xt_try tmux ls
rm -f "$T/bin/tmux"
e2e_end='"$first"
[ ! -e "$X/bypass" ] && [ "$(grep '^tmux	' "$LOG" | head -1)" = "tmux	tmpdir=$t/tmux	dir=yes	TMUX=unset	sock=yes	-S $ownp ls" ]; check "a tmux in the run's bin folder: the call still goes through the guard, to the run's own socket" $?
rm -f "$X/bypass"
finish

echo "--- the guard refuses a tmux call that no case asked for, and the run does not pass"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
TMUX_TMPDIR=$T/no-such-folder tmux has-session -t "=tt-em" 2>/dev/null
e2e_end='"$first"
[ "$rc" != 0 ] && [ "$(aborted)" = 0 ] && printf '%s\n' "$out" | grep -qE '^RESULT pass=[1-9][0-9]* fail=1$' && printf '%s\n' "$out" | grep -qE '^FAIL the tmux guard refused 1 tmux call'; check "unasked refusal: the run reaches its end and fails, with one failure that says the guard refused a call (exit $rc)" $?
printf '%s\n' "$out" | grep -qF 'tmux-guard: refused: tmux has-session -t =tt-em:'; check "unasked refusal: the run shows the call that was refused" $?
[ -z "$(leaks)" ]; check "unasked refusal: the call reached no tmux" $?
finish

# A seat's pane runs a login shell, whose profile builds PATH again with the system's folders first: the
# guard, first on the run's PATH, is not first there (seen in a full run, where a seat's tmux was the real
# one). So the stand-in claude, as the file under test compiles it, puts the guard first itself. It is
# started here with a PATH that has neither the guard nor the stand-in tmux, and given one submitted !
# line, as a seat's command is. The line calls tmux only once it has seen that its tmux is the guard.
echo "--- the stand-in claude of the run puts the guard first on its own PATH"
rm -f "$X/seat" "$X/seat.done"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
cat > "$T/seat.sh" <<S
{ command -v tmux
  if [ "\$(command -v tmux)" -ef "$SRC/test/guard/tmux" ]; then tmux ls; echo "rc=\$?"; else echo "no call made"; fi; } > "$xt_x/seat" 2>&1
touch "$xt_x/seat.done"
S
printf "!sh %s/seat.sh\r" "$T" | env PATH=/usr/bin:/bin "$T/bin/claude" > /dev/null 2>&1
for xt_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$xt_x/seat.done" ] && break; sleep 0.25; done
e2e_end='"$first"
seat1=$(sed -n 1p "$X/seat" 2>/dev/null)   # before the check: a $( ) among its words would set the $? it is given
[ -e "$X/seat.done" ] && [ "$seat1" = "$X/src/test/guard/tmux" ]; check "stand-in claude: tmux in a ! line it runs is the guard, though its own PATH did not have it (it is: ${seat1:-none})" $?
[ "$(grep '^tmux	' "$LOG" | head -1)" = "tmux	tmpdir=$t/tmux	dir=yes	TMUX=unset	sock=yes	-S $ownp ls" ]; check "stand-in claude: the call of its ! line goes through the guard, to the run's own socket" $?
rm -f "$X/seat" "$X/seat.done"
finish

echo "--- the file under test will not start without its guard"
if [ -d "$X/src/test/guard" ]; then
  # With a TMPDIR of its own, so that what the run made, if anything, is all there is in it.
  mv "$X/src/test/guard" "$X/src/test/guard.away"; mkdir "$X/tmp"
  nested 'xt_mark "the first area ran"
e2e_end='"$first" TMPDIR="$X/tmp"
  mv "$X/src/test/guard.away" "$X/src/test/guard"
  [ "$rc" = 2 ] && [ -z "$marks" ] && printf '%s\n' "$out" | grep -qF "test/guard/tmux"; check "no guard in the tree: the run stops before its first area, exit 2, naming the file (exit $rc)" $?
  [ "$(calls tmux)" = 0 ] && [ "$(calls fabrikito)" = 0 ]; check "no guard in the tree: nothing was run" $?
  [ -z "$(ls -A "$X/tmp")" ]; check "no guard in the tree: no scratch folder was made" $?
  finish
else
  check "the tree this script is in has test/guard/tmux" 1
fi

echo "--- the caller's environment has LIVE_D and TD, and the run ends before an area sets them"
mkdir "$X/td-marker" "$X/live-marker"
nested 'xt_socket "$xt_sock"; xt_mark "at the start"
: "$xt_unset_top"' LIVE_D="$X/live-marker" TD="$X/td-marker"
[ "$marks" = "at the start: kept" ] && [ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "caller's LIVE_D and TD: the exit trap ran, in the run's own shell (exit $rc)" $?
[ -d "$X/td-marker" ]; check "caller's TD: the exit trap does not remove the folder it names" $?
[ "$(calls live-env)" = 0 ]; check "caller's LIVE_D: the exit trap does not run live-env.sh down on it" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "caller's LIVE_D and TD: the run's own scratch folder is still removed" $?
finish

rm -rf "$X"
echo "e2e-exit-trap: $n checks, $f failed"
[ "$f" -eq 0 ]
