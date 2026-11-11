#!/usr/bin/env bash
# Regression test of the exit trap and the cleanup of test/e2e.sh (#306): no tmux command they run may
# reach a server other than the run's own, and a child of the run that exits early cleans up nothing.
#
#   test/e2e-exit-trap.sh [e2e.sh]     the file to test; test/e2e.sh next to this one if not given
#
# It starts no tmux server and runs no tmux command, so it is safe on any machine, on the old code too:
#   git show <base>:test/e2e.sh > "$TMPDIR/old-e2e.sh" && test/e2e-exit-trap.sh "$TMPDIR/old-e2e.sh"
# It runs the file under test as it is, from a scratch tree where every area is a stub and the first one
# is a fixture, with two stand-ins that record their call and do nothing else: a tmux first on PATH, and
# the tree's fabrikito. The fixture makes a socket file where the run's tmux server would have its own (a
# file only, nothing listens), so the cleanup has a socket to find.
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
echo 'int main(void) { return 0; }' > "$X/src/test/e2e/fake-claude.c"
for a in lib $areas; do echo "e2e_end=$a" > "$X/src/test/e2e/$a.sh"; done
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
chmod +x "$X/bin/tmux" "$X/src/fabrikito"
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
# nested <fixture>: run the file under test with this fixture as its first area. Sets out and rc, and what
# the fixture wrote down: t and top (the run's $T and $T_TOP), own (its server's socket), marks.
nested() {
  rm -f "$X/t" "$X/top" "$X/marks"; : > "$LOG"; f0=$f
  { cat <<'EOF'
xt_x=$SRC/..; echo "$T" > "$xt_x/t"; echo "$T_TOP" > "$xt_x/top"
xt_sock=$T/tmux/tmux-$(id -u)/default; mkdir -p -m 700 "${xt_sock%/*}"
xt_socket() { ruby -rsocket -e 'UNIXServer.new(ARGV[0])' "$1"; }
xt_mark() { if [ -d "$T/bin" ] && [ -S "$xt_sock" ]; then echo "$1: kept"; else echo "$1: gone"; fi >> "$xt_x/marks"; }
EOF
    printf '%s\n' "$1"; } > "$X/src/test/e2e/$first.sh"
  out=$(env PATH="$xt_path" TEST_VOLUME="$X/vol" "$BASH" "$X/src/test/e2e.sh" 2>&1); rc=$?
  t=$(cat "$X/t" 2>/dev/null); top=$(cat "$X/top" 2>/dev/null); own=$t/tmux/tmux-$uid/default
  marks=$(cat "$X/marks" 2>/dev/null)
}
# The recorded tmux calls that could have reached a server other than the run's own: one through -S to
# another socket, or one that leaves the choice to tmux (no -S) when TMUX is set, or when TMUX_TMPDIR is
# not the run's own folder or that folder is not there (tmux then falls back to /tmp, the default server).
leaks() {
  local kind tmpd dir tm sock args
  while IFS=$'\t' read -r kind tmpd dir tm sock args; do
    [ "$kind" = tmux ] || continue
    case $args in
      "-S $own "*) continue ;;
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

echo "--- the socket is a link to another server's"
nested 'xt_socket "$T/other-socket"; ln -s "$T/other-socket" "$xt_sock"; xt_mark "at the start"
: "$xt_unset_top"'
[ "$marks" = "at the start: kept" ] && [ "$rc" != 0 ] && [ "$(aborted)" = 1 ]; check "linked socket: the exit trap ran, in the run's own shell (exit $rc)" $?
[ "$(calls tmux)" = 0 ]; check "linked socket: skipped, no tmux call at all (tmux would follow the link)" $?
[ -n "$top" ] && [ ! -e "$top" ]; check "linked socket: the scratch folder is still removed" $?
finish

rm -rf "$X"
echo "e2e-exit-trap: $n checks, $f failed"
[ "$f" -eq 0 ]
