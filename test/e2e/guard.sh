# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# The tmux guard of the run (test/guard/tmux, #307), with the real tmux behind it: in the test's own shell,
# in the launcher under test and in a stand-in seat. Uses em and w1, which are running, and leaves them so.
# Every call here that the guard must refuse is one that only reads (ls, has-session through the
# launcher's status): were the guard wrong, it would list the user's own server and change nothing. Calls
# that stop or type (kill-server, send-keys) are tried against a recording stand-in only, in
# test/e2e-tmux-guard.sh and test/e2e-exit-trap.sh. A refusal asked for here goes to a record of its own
# ($GREF), not to the run's, which test/e2e.sh checks is empty at the end.
echo "--- tmux guard (#307): no tmux call of the run reaches a server that is not the run's own"
GREF=$T/guard-refused.log; GDEF=/tmp/tmux-$(id -u)/default; GOWN=$(cd $T/tmux && pwd -P)/tmux-$(id -u)/default
got=$(tmux display-message -p -t '=tt-em:' '#{socket_path}' 2>&1)
[ "$(command -v tmux)" = "$SRC/test/guard/tmux" ] && [ "$got" = "$GOWN" ] && ok "tmux in the test's shell is the guard, and a bare call reaches the run's own server through it" || { bad "the guard in the test's shell (tmux is $(command -v tmux))"; echo "$got"; }
# grefused <how the call is made> <command...>: it fails at the guard, with one message that names the
# call, and that refusal is the one line recorded.
grefused() {
  local how=$1 out rc; shift; : > $GREF
  out=$(TMUX_GUARD_LOG=$GREF "$@" 2>&1); rc=$?
  [ $rc -ne 0 ] && [ "$(echo "$out" | grep -c '^tmux-guard: refused: tmux .*ls: ')" = 1 ] && [ "$(cat $GREF)" = "$out" ] \
    && ok "the guard refuses tmux ls $how, naming the call" || { bad "tmux ls $how was not refused by the guard (rc=$rc)"; echo "$out" | head -3 | cut -c1-200; }
}
grefused "with TMUX_TMPDIR naming a folder that is not there" env TMUX_TMPDIR=$T/no-such-dir tmux ls
grefused "with an empty TMUX_TMPDIR" env TMUX_TMPDIR= tmux ls
grefused "with TMUX_TMPDIR unset" env -u TMUX_TMPDIR tmux ls
grefused "with TMUX_TMPDIR=/tmp" env TMUX_TMPDIR=/tmp tmux ls
grefused "with TMUX naming the socket in /tmp" env TMUX=$GDEF,1,0 tmux ls
grefused "with -S naming the socket in /tmp" tmux -S $GDEF ls
grefused "with -L and TMUX_TMPDIR unset" env -u TMUX_TMPDIR tmux -L default ls
# The launcher under test. status only reads the seats and is not among the commands that refuse the
# default server themselves (#105), so with TMUX_TMPDIR gone or TMUX set its has-session calls went
# wherever tmux took them. Now each fails at the guard, and status shows the seat as down.
$S -c $T/team.yaml status 2>&1 | grep -qE '^em +.* tt-em +up ' || bad "test setup: status does not show em as up"
gstatus() {
  local how=$1 out; shift; : > $GREF
  out=$(TMUX_GUARD_LOG=$GREF "$@" $S -c $T/team.yaml status 2>&1)
  [ -s $GREF ] && ! grep -qv '^tmux-guard: refused: tmux has-session ' $GREF && echo "$out" | grep -qE '^em +.* tt-em +down ' \
    && ok "the launcher's status $how: each of its tmux calls fails at the guard, and it shows em as down" || { bad "status $how"; echo "$out" | head -4 | cut -c1-200; head -3 $GREF | cut -c1-200; }
}
gstatus "with TMUX_TMPDIR naming a folder that is not there" env TMUX_TMPDIR=$T/no-such-dir
gstatus "with TMUX naming the socket in /tmp" env TMUX=$GDEF,1,0
# A stand-in seat. Its PATH and the guard's variables reach it through the run's tmux server, and TMUX
# names the run's socket in its pane. The script runs as a seat's command would (a submitted ! line).
cat > $T/gseat.sh <<G
{ command -v tmux; tmux display-message -p '#{socket_path}'
  TMUX_GUARD_LOG=$GREF.seat env -u TMUX TMUX_TMPDIR=$T/no-such-dir tmux ls; echo "rc=\$?"
  TMUX_GUARD_LOG=$GREF.seat env TMUX=$GDEF,1,0 tmux ls; echo "rc=\$?"; } > $T/gseat.out 2>&1
touch $T/gseat.done
G
rm -f $T/gseat.out $T/gseat.done $GREF.seat
tmux send-keys -t '=tt-w1:' -l "!sh $T/gseat.sh"; tmux send-keys -t '=tt-w1:' Enter
for i in $(seq 1 20); do [ -e $T/gseat.done ] && break; sleep 0.5; done
[ "$(sed -n 1p $T/gseat.out 2>/dev/null)" = "$SRC/test/guard/tmux" ] && [ "$(sed -n 2p $T/gseat.out)" = "$GOWN" ] \
  && ok "tmux in a stand-in seat is the guard, and the seat's bare call reaches the run's own server (TMUX names it)" || { bad "the guard in a stand-in seat"; head -3 $T/gseat.out 2>&1 | cut -c1-200; }
[ "$(sed -n '3,$p' $T/gseat.out 2>/dev/null | grep -c '^tmux-guard: refused: tmux ls: ')" = 2 ] && [ "$(grep -c '^rc=1$' $T/gseat.out)" = 2 ] && [ "$(wc -l < $GREF.seat 2>/dev/null | tr -d ' ')" = 2 ] \
  && ok "the guard refuses a seat's tmux ls with TMUX_TMPDIR gone, and with TMUX naming the socket in /tmp" || { bad "a seat's calls were not refused by the guard"; cat $T/gseat.out 2>&1 | cut -c1-200; }
# The guard alone, call by call, by test/e2e-tmux-guard.sh: what it refuses and what it passes on, for ls
# and for kill-server, with a stand-in that records as the real tmux behind it, so that it reaches no
# server whatever the guard does. It is a script of its own so that it can run alone, on any guard. The
# nested runs with the run's folders gone are in test/e2e-exit-trap.sh, which live.sh runs.
out=$($SRC/test/e2e-tmux-guard.sh 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qE '^e2e-tmux-guard: [1-9][0-9]* checks, 0 failed$' \
  && ok "test/e2e-tmux-guard.sh: the guard passes a tmux call on only to a socket in the run's own folders, by -S, and refuses every other, in test/live-env.sh run and down too" || { bad "test/e2e-tmux-guard.sh (rc=$rc)"; echo "$out" | grep -v '^ok ' | head -40; }
e2e_end=guard # the last line: test/e2e.sh checks that the file ran to here
