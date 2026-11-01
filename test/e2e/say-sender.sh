# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# say: who the sender is: TEAM_ROLE unset (#41, #97), across tmux servers (#115), not a sender (#89).
# say writes its messages.log line before its terminal message, so a failed terminal write still logs it (#128).
# Starts a live-env environment and removes it.
echo "--- say with TEAM_ROLE unset (#41): never [from owner] from inside a seat"
# waitlog <lines before>: wait up to 10s for say to append its log line.
waitlog() { local i; for i in $(seq 1 20); do [ "$(wc -l < $T/state/messages.log)" -gt "$1" ] && return 0; sleep 0.5; done; return 1; }
# Inside w1's pane: the stand-in runs the command in a child with no tty (as the Bash tool does) and
# with TEAM_ROLE removed, as a cleared or rebuilt environment would leave it.
n=$(wc -l < $T/state/messages.log)
tmux send-keys -t '=tt-w1:' -l "!env -u TEAM_ROLE $S -c $T/team.yaml say em 'unset role inside w1'"; tmux send-keys -t '=tt-w1:' Enter
waitlog "$n"; sleep 1
em_screen=$(tmux capture-pane -p -t '=tt-em:')
! echo "$em_screen" | grep -qF "[from owner] unset role inside w1" && ! tail -1 $T/state/messages.log | grep -q "	owner	" &&
  ok "say from inside a seat with TEAM_ROLE unset is not labelled [from owner]" || { bad "say inside a seat was labelled owner"; tail -1 $T/state/messages.log; }
echo "$em_screen" | grep -qF "[from w1] unset role inside w1" && [ "$(tail -1 $T/state/messages.log | cut -f2-4)" = "w1	em	delivered" ] &&
  ok "say from inside a seat with TEAM_ROLE unset is labelled with that seat's role" || { bad "say inside a seat: label"; tail -1 $T/state/messages.log; echo "$em_screen" | tail -8; }
# Outside every seat: the owner. This test often runs inside a seat (the stop gate, a reviewer),
# where a tmux server is among its ancestors and say refuses (#115). So say runs detached: the outer
# subshell exits at once, and the inner job, re-parented to launchd by the time its second of sleep is
# over, runs say with no tmux server above it, as from the owner's own terminal. (No $BASHPID: macOS
# bash 3.2 has none.)
n=$(wc -l < $T/state/messages.log); rm -f $T/detached.rc
( ( sleep 1; env -u TEAM_ROLE $S -c $T/team.yaml say w1 "unset role outside every seat" >/dev/null 2>&1; echo $? > $T/detached.rc ) & )
for i in $(seq 1 40); do [ -s $T/detached.rc ] && break; sleep 0.25; done; sleep 1
tmux capture-pane -p -t '=tt-w1:' | grep -qF "[from owner] unset role outside every seat" && [ "$(tail -n +$((n + 1)) $T/state/messages.log | cut -f2-4)" = "owner	w1	delivered" ] &&
  ok "say from outside every seat with TEAM_ROLE unset is still [from owner]" || { bad "say outside seats: owner label"; tail -1 $T/state/messages.log; }
# A tmux pane of the owner's that is not a seat, on the seats' own server, named with the team prefix.
n=$(wc -l < $T/state/messages.log)
tmux new-session -d -s tt-notaseat "env -u TEAM_ROLE $S -c $T/team.yaml say w1 'unset role from a pane that is not a seat'; sleep 30"
waitlog "$n"; sleep 1; tmux kill-session -t '=tt-notaseat' 2>/dev/null
tmux capture-pane -p -t '=tt-w1:' | grep -qF "[from owner] unset role from a pane that is not a seat" && [ "$(tail -n +$((n + 1)) $T/state/messages.log | cut -f2-4)" = "owner	w1	delivered" ] &&
  ok "say from a tmux pane that is not a seat with TEAM_ROLE unset is still [from owner]" || { bad "say from a non-seat pane: owner label"; tail -1 $T/state/messages.log; }
echo "--- say with TEAM_ROLE unset fails closed when it cannot tell (#97)"
# lastlog <sender> <to> <message>: the newest log line is exactly that NOT-DELIVERED record.
lastlog() { [ "$(tail -1 $T/state/messages.log | cut -f2-5)" = "$1	$2	NOT-DELIVERED	$3" ]; }
# tmux cannot list its panes while say has a terminal (a pane that is not a seat): refuse, never owner.
mkdir -p $T/lpfail && printf '#!/bin/sh\n[ "$1" = list-panes ] && exit 1\nexec %s "$@"\n' "$(command -v tmux)" > $T/lpfail/tmux && chmod +x $T/lpfail/tmux
n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
tmux new-session -d -s tt-lpfail "PATH=$T/lpfail:\$PATH env -u TEAM_ROLE $S -c $T/team.yaml say w1 'tmux cannot list panes' > $T/lpfail.out 2>&1; sleep 30"
waitlog "$n"; sleep 1; tmux kill-session -t '=tt-lpfail' 2>/dev/null
lastlog '?' w1 'tmux cannot list panes' && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] && grep -q "tmux could not list" $T/lpfail.out &&
  ok "say with TEAM_ROLE unset refuses when tmux cannot list panes (no keys, NOT-DELIVERED), not [from owner]" || { bad "say when list-panes fails"; tail -1 $T/state/messages.log; cat $T/lpfail.out; }
# ps cannot read say's own process: refuse, and the refusal is logged like every other.
mkdir -p $T/psfail && printf '#!/bin/sh\ncase "$*" in *ppid=*) exit 1 ;; esac\nexec /bin/ps "$@"\n' > $T/psfail/ps && chmod +x $T/psfail/ps
n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
pout=$(PATH=$T/psfail:$PATH env -u TEAM_ROLE $S -c $T/team.yaml say w1 "ps cannot read" 2>&1); rc=$?; sleep 1
[ $rc -ne 0 ] && echo "$pout" | grep -q "ps could not read" && [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && lastlog '?' w1 'ps cannot read' && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] &&
  ok "say with TEAM_ROLE unset refuses when ps fails, and logs NOT-DELIVERED" || { bad "say when ps fails (rc=$rc)"; echo "$pout"; tail -1 $T/state/messages.log; }
# ps fails for say's parent only (an ancestor that exited mid-walk): refuse too, never owner. The
# sh records its pid for the stand-in and runs say as a child (not exec), so it is say's parent.
mkdir -p $T/psparent && printf '#!/bin/sh\ncase "$*" in "-o ppid="*" -p $(cat %s/psparent.pid)") exit 1 ;; esac\nexec /bin/ps "$@"\n' "$T" > $T/psparent/ps && chmod +x $T/psparent/ps
n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
pout=$(PATH=$T/psparent:$PATH sh -c 'echo $$ > "$1/psparent.pid"; env -u TEAM_ROLE "$2" -c "$1/team.yaml" say w1 "ps cannot read the parent"; rc=$?; exit $rc' sh "$T" "$S" 2>&1); rc=$?; sleep 1
[ $rc -ne 0 ] && echo "$pout" | grep -q "ps could not read" && lastlog '?' w1 'ps cannot read the parent' && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] &&
  ok "say with TEAM_ROLE unset refuses when ps fails for an ancestor, and logs NOT-DELIVERED" || { bad "say when ps fails for the parent (rc=$rc)"; echo "$pout"; tail -1 $T/state/messages.log; }
# The walk reads at most 100 processes (#130). A stand-in ps gives say a made-up chain with no tty
# and no tmux server: say's own process, then pids 900000, 900001, ... up to 900000+K, whose parent
# is pid 1. With K=98 the 100th process read is 900098, whose parent is 1: the walk is complete and
# say is the owner. With K=99 the walk stops at the cap before pid 1: refuse, whatever it saw.
mkdir -p $T/pschain && printf '#!/bin/sh\ncase "$*" in "-o ppid=,tty=,comm= -p "*) for p; do :; done; k=$(cat %s/pschain.k)\n  if [ "$p" -lt 900000 ]; then echo "900000 ?? sh"; elif [ "$p" -ge $((900000 + k)) ]; then echo "1 ?? sh"; else echo "$((p + 1)) ?? sh"; fi; exit 0 ;; esac\nexec /bin/ps "$@"\n' "$T" > $T/pschain/ps && chmod +x $T/pschain/ps
echo 99 > $T/pschain.k; n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
pout=$(PATH=$T/pschain:$PATH env -u TEAM_ROLE $S -c $T/team.yaml say w1 "ancestry past the cap" 2>&1); rc=$?; sleep 1
[ $rc -ne 0 ] && echo "$pout" | grep -q "cap of 100" && [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && lastlog '?' w1 'ancestry past the cap' && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] &&
  ok "say with TEAM_ROLE unset refuses when the ancestry walk stops at its cap before pid 1 (no keys, NOT-DELIVERED)" || { bad "say past the ancestry cap (rc=$rc)"; echo "$pout"; tail -1 $T/state/messages.log; }
echo 98 > $T/pschain.k; n=$(wc -l < $T/state/messages.log)
pout=$(PATH=$T/pschain:$PATH env -u TEAM_ROLE $S -c $T/team.yaml say w1 "ancestry at the cap" 2>&1); rc=$?; sleep 1
[ $rc -eq 0 ] && [ "$(tail -n +$((n + 1)) $T/state/messages.log | cut -f2-4)" = "owner	w1	delivered" ] && tmux capture-pane -p -t '=tt-w1:' | grep -qF "[from owner] ancestry at the cap" &&
  ok "say with TEAM_ROLE unset whose walk reaches pid 1 at the cap is still [from owner]" || { bad "say at the ancestry cap (rc=$rc)"; echo "$pout"; tail -1 $T/state/messages.log; }
# Inside a seat of another team on the same server (here w1, running say with a file for team to):
# its pane matches none of that team's seats, but it is a seat, so it is not the owner either.
sed 's/^  prefix: tt$/  prefix: to/' $T/team.yaml > $T/other.yaml
n=$(wc -l < $T/state/messages.log)
tmux send-keys -t '=tt-w1:' -l "!env -u TEAM_ROLE $S -c $T/other.yaml say em 'from a seat of another team' > $T/other.out 2>&1"; tmux send-keys -t '=tt-w1:' Enter
waitlog "$n"; sleep 1
lastlog '?' em 'from a seat of another team' && grep -q "a seat of another team" $T/other.out &&
  ok "say with TEAM_ROLE unset from a seat of another team is refused, not [from owner]" || { bad "say from another team's seat"; tail -1 $T/state/messages.log; cat $T/other.out; }
# A pane of em's with an empty tty (tmux prints the line "<server pid>  tt-em") matches no caller: say from a pane
# that is not a seat, whose ancestors share one tty (so its tty list has two spaces in a row), is
# still the owner, never em.
mkdir -p $T/ttyless && printf '#!/bin/sh\n[ "$1" = list-panes ] && printf "%%s  tt-em\\n" "$(%s list-panes -a -F "#{pid}" | head -1)"\nexec %s "$@"\n' "$(command -v tmux)" "$(command -v tmux)" > $T/ttyless/tmux && chmod +x $T/ttyless/tmux
n=$(wc -l < $T/state/messages.log)
tmux new-session -d -s tt-ttyless "PATH=$T/ttyless:\$PATH env -u TEAM_ROLE $S -c $T/team.yaml say w1 'beside a pane with no tty'; sleep 30"
waitlog "$n"; sleep 1; tmux kill-session -t '=tt-ttyless' 2>/dev/null
[ "$(tail -n +$((n + 1)) $T/state/messages.log | cut -f2-4)" = "owner	w1	delivered" ] &&
  ok "a seat's pane with an empty tty matches no caller (say from a non-seat pane is still [from owner])" || { bad "empty pane tty matched a caller"; tail -1 $T/state/messages.log; }
# A seat messaging itself is refused and logged too.
n=$(wc -l < $T/state/messages.log)
TEAM_ROLE=w1 $S -c $T/team.yaml say w1 "to myself" >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && lastlog w1 w1 'to myself' &&
  ok "say from a seat to itself is refused and logged NOT-DELIVERED" || { bad "say to itself (rc=$rc)"; tail -1 $T/state/messages.log; }
# Record before report (#128): when the terminal write fails, the NOT-DELIVERED line is still logged.
# Two stand-ins for a failed write: stderr closed (the write fails with EBADF, and set -e ends say),
# and stderr a pipe whose reader has already gone (the write kills say with SIGPIPE). The pipe is
# made by perl, which closes its read end before it starts say, so the write fails every time.
# Two paths: a refusal decided in cmd_say (w1 to itself) and one in send_one (w2 is down).
brokenpipe() { perl -e '$SIG{PIPE} = "DEFAULT"; pipe(R, W) or die; close R; open(STDERR, ">&", \*W) or die; close W; exec @ARGV or die' "$@"; }
for c in "w1 closed" "w1 pipe" "w2 closed" "w2 pipe"; do
  to=${c% *} how=${c#* }; n=$(wc -l < $T/state/messages.log)
  if [ $how = closed ]; then TEAM_ROLE=w1 $S -c $T/team.yaml say $to "terminal write fails ($c)" >/dev/null 2>&-; rc=$?
  else TEAM_ROLE=w1 brokenpipe $S -c $T/team.yaml say $to "terminal write fails ($c)" >/dev/null; rc=$?; fi
  [ $rc -ne 0 ] && [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && lastlog w1 $to "terminal write fails ($c)" &&
    ok "say still logs NOT-DELIVERED when its terminal write fails (to $to, stderr $how)" || { bad "say with a failed terminal write ($c, rc=$rc)"; tail -1 $T/state/messages.log; }
done
# send_one's reasons, held until the log line is written, are still shown, and the file that held
# them is never left behind.
out=$(TEAM_ROLE=w1 $S -c $T/team.yaml say w2 "held reason" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && [ "$out" = "not delivered: w2 is down (tt-w2)" ] && lastlog w1 w2 "held reason" && [ -z "$(ls -A $T/state | grep '^say\.')" ] &&
  ok "say shows send_one's reason once it has logged, and leaves no held file" || { bad "say's held reason (rc=$rc)"; echo "$out"; ls -A $T/state; }
# The other way round: a log that cannot be appended to does not lose the terminal message.
mkdir -p $T/unlogstate/messages.log
out=$(TEAM_STATE_DIR=$T/unlogstate TEAM_ROLE=w1 $S -c $T/team.yaml say w2 "log cannot be written" 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "not delivered: w2 is down" && echo "$out" | grep -qF "record could not be written to $T/unlogstate/messages.log (the message was not delivered)" &&
  ok "say whose log cannot be written still shows why it did not deliver, and fails" || { bad "say with an unwritable log (rc=$rc)"; echo "$out"; }
# Delivered, with the log unwritable: the note says it went out, so the caller does not send it again.
out=$(TEAM_STATE_DIR=$T/unlogstate TEAM_ROLE=w1 $S -c $T/team.yaml say em "delivered, log cannot be written" 2>&1); rc=$?; sleep 1
[ $rc -ne 0 ] && echo "$out" | grep -qF "(the message was delivered)" && tmux capture-pane -p -t "=tt-em:" | grep -qF "[from w1] delivered, log cannot be written" &&
  ok "say whose log cannot be written after delivering says the message was delivered" || { bad "say delivered with an unwritable log (rc=$rc)"; echo "$out"; }
echo "--- say across tmux servers (#115): never [from owner] from a pane of another server"
# Server 2 is a live-env environment (test/live-env.sh) with one stand-in seat on it, tx-em, of a
# copy of the team with prefix tx. Its log is the environment's own.
LIVE_D=$($SRC/test/live-env.sh new); XLOG=$LIVE_D/state/messages.log
lenv() { $SRC/test/live-env.sh run "$LIVE_D" "$@"; }
sed 's/^  prefix: tt$/  prefix: tx/' $T/team.yaml > $T/xs.yaml
lenv $S -c $T/xs.yaml up --no-view em >/dev/null 2>&1; sleep 2; touch $XLOG $T/keys-em.log
lenv tmux has-session -t '=tx-em' 2>/dev/null && ok "a stand-in seat runs on a second tmux server (live-env)" || bad "seat on the second server"
# waitfile <file> <lines before>: wait up to 10s for a line to be appended to the file.
waitfile() { local i; for i in $(seq 1 20); do [ "$(wc -l < "$1")" -gt "$2" ] && return 0; sleep 0.5; done; return 1; }
# 1. Inside seat w1 (server 1), say addressed to server 2 with TEAM_ROLE unset: refused, no keys.
n=$(wc -l < $XLOG); k=$(wc -c < $T/keys-em.log)
tmux send-keys -t '=tt-w1:' -l "!env -u TEAM_ROLE -u TMUX TMUX_TMPDIR=$LIVE_D/tmux TEAM_STATE_DIR=$LIVE_D/state $S -c $T/xs.yaml say em 'from w1 to server 2' > $T/xs1.out 2>&1"; tmux send-keys -t '=tt-w1:' Enter
waitfile $XLOG "$n"; sleep 1
[ "$(tail -1 $XLOG | cut -f2-5)" = "?	em	NOT-DELIVERED	from w1 to server 2" ] && [ "$(wc -c < $T/keys-em.log)" = "$k" ] && grep -q "another tmux server" $T/xs1.out &&
  ok "say with TEAM_ROLE unset from a seat on one tmux server to another is refused (no keys, NOT-DELIVERED), not [from owner]" || { bad "say from a seat to another server"; tail -1 $XLOG; cat $T/xs1.out; }
# 2. A plain pane on server 2, say addressed to server 1 with TEAM_ROLE unset: refused, no keys.
n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
lenv tmux new-session -d -s tx-plain "env -u TEAM_ROLE -u TMUX TMUX_TMPDIR=$T/tmux TEAM_STATE_DIR=$T/state $S -c $T/team.yaml say w1 'from a pane on server 2' > $T/xs2.out 2>&1; sleep 30"
waitlog "$n"; sleep 1; lenv tmux kill-session -t '=tx-plain' 2>/dev/null
lastlog '?' w1 'from a pane on server 2' && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] && grep -q "another tmux server" $T/xs2.out && grep -q "terminal outside tmux" $T/xs2.out &&
  ok "say with TEAM_ROLE unset from a pane of another tmux server is refused, naming a terminal outside tmux" || { bad "say from a pane of another server"; tail -1 $T/state/messages.log; cat $T/xs2.out; }
# 3. A driver: inside seat w1, through live-env run, say to the seat on server 2 is [from live-test].
n=$(wc -l < $XLOG); k=$(wc -c < $T/keys-em.log)
tmux send-keys -t '=tt-w1:' -l "!$SRC/test/live-env.sh run $LIVE_D $S -c $T/xs.yaml say em 'driven through live-env' > $T/xs3.out 2>&1"; tmux send-keys -t '=tt-w1:' Enter
waitfile $XLOG "$n"; sleep 1
[ "$(tail -1 $XLOG | cut -f2-4)" = "live-test	em	delivered" ] && tail -c +$((k + 1)) $T/keys-em.log | keytext | grep -qF "[from live-test] driven through live-env" &&
  ok "a live-env driver inside a seat sends as [from live-test], logged live-test" || { bad "live-env driver label"; tail -1 $XLOG; cat $T/xs3.out; }
# 4. live-test addressed to the default server is refused before say runs any tmux command: TMUX and
# TMUX_TMPDIR unset, and a stand-in tmux first on PATH that records every call and runs none. The team
# file here is a throwaway one, which say refuses on the default server anyway (#105), so
# --default-socket lets say past that guard to show that live-test is refused on its own.
mkdir -p $T/rec && printf '#!/bin/sh\necho "tmux $*" >> %s/rec.log\nexit 1\n' "$T" > $T/rec/tmux && chmod +x $T/rec/tmux; rm -f $T/rec.log
n=$(wc -l < $T/state/messages.log)
out=$(env -u TMUX -u TMUX_TMPDIR PATH="$T/rec:$PATH" TEAM_ROLE=live-test $S -c $T/team.yaml say --default-socket w1 "live-test to the default server" 2>&1); rc=$?
[ $rc -ne 0 ] && [ ! -e $T/rec.log ] && lastlog live-test w1 'live-test to the default server' && echo "$out" | grep -q "default tmux server" &&
  ok "TEAM_ROLE=live-test addressed to the default tmux server is refused before any tmux command, logged NOT-DELIVERED" || { bad "live-test on the default server (rc=$rc)"; echo "$out"; cat $T/rec.log 2>&1; tail -1 $T/state/messages.log; }
# 5. This test's own process: when a tmux server is among its ancestors (run from a seat), say with
# TEAM_ROLE unset from it is refused. Run from a plain terminal, it has none, and this is not asserted.
anc_tmux() { local p=$$ pp c; while [ "$p" -gt 1 ]; do read -r pp c < <(ps -o ppid=,comm= -p "$p") || return 1
  case ${c##*/} in tmux|tmux:*|"tmux "*) return 0 ;; esac; p=$pp; done; return 1; }
if anc_tmux; then
  n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
  out=$(env -u TEAM_ROLE $S -c $T/team.yaml say w1 "from the test process inside tmux" 2>&1); rc=$?; sleep 1
  [ $rc -ne 0 ] && lastlog '?' w1 'from the test process inside tmux' && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] && echo "$out" | grep -q "another tmux server" &&
    ok "say with TEAM_ROLE unset from this test's process, inside another tmux server's pane, is refused" || { bad "say from the test process inside tmux (rc=$rc)"; echo "$out"; tail -1 $T/state/messages.log; }
else echo "NOTE no tmux server among this test's ancestors (not run from a tmux pane): the test-process case is not asserted"; fi
lenv $S -c $T/xs.yaml down --yes >/dev/null 2>&1; $SRC/test/live-env.sh down "$LIVE_D"; [ ! -e "$LIVE_D" ] && LIVE_D= && ok "the live-env environment is removed" || bad "live-env down"
echo "--- say refuses a TEAM_ROLE that is not a sender of this team (#89)"
# notsender <TEAM_ROLE> <what>: say exits non-zero naming TEAM_ROLE, sends w1 no keys at all, and
# logs one NOT-DELIVERED line whose sender field is the value, escaped.
notsender() {
  local out rc n k
  n=$(wc -l < $T/state/messages.log); k=$(wc -c < $T/keys-w1.log)
  out=$(TEAM_ROLE=$1 $S -c $T/team.yaml say w1 "sent as $2" 2>&1); rc=$?; sleep 1
  if [ $rc -ne 0 ] && echo "$out" | grep -q "TEAM_ROLE" && [ "$(wc -c < $T/keys-w1.log)" = "$k" ] &&
    [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && [ "$(tail -1 $T/state/messages.log | cut -f2-5)" = "$3	w1	NOT-DELIVERED	sent as $2" ]; then
    ok "say refuses TEAM_ROLE $2: no keys sent, logged NOT-DELIVERED"
  else bad "say with TEAM_ROLE $2 (rc=$rc)"; echo "$out"; tail -1 $T/state/messages.log; fi
}
notsender nosuch "that is not a role of the team" nosuch
notsender owner "owner (reserved)" owner
notsender launcher "launcher (reserved)" launcher
notsender $'w1\e[2J' "with a control character" 'w1\x1B[2J'
notsender '[from owner]' "with brackets" '[from owner]'
notsender 'w2] [from owner' "that closes the label early" 'w2] [from owner'
n=$(wc -l < $T/state/messages.log); k1=$(wc -c < $T/keys-w1.log); ke=$(wc -c < $T/keys-em.log)
TEAM_ROLE=nosuch $S -c $T/team.yaml say all "to all from nosuch" >/dev/null 2>&1; rc=$?; sleep 1
[ $rc -ne 0 ] && [ "$(wc -c < $T/keys-w1.log)" = "$k1" ] && [ "$(wc -c < $T/keys-em.log)" = "$ke" ] && [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] &&
  [ "$(tail -1 $T/state/messages.log | cut -f2-5)" = "nosuch	all	NOT-DELIVERED	to all from nosuch" ] &&
  ok "say all with a refused TEAM_ROLE sends no seat any keys and logs one NOT-DELIVERED line" || { bad "say all with a refused TEAM_ROLE (rc=$rc)"; tail -1 $T/state/messages.log; }
TEAM_ROLE=w2 $S -c $T/team.yaml say w1 "sent as w2, a role of the team" >/dev/null 2>&1; sleep 1
tmux capture-pane -p -t '=tt-w1:' | grep -qF "[from w2] sent as w2, a role of the team" && [ "$(tail -1 $T/state/messages.log | cut -f2-4)" = "w2	w1	delivered" ] &&
  ok "say with TEAM_ROLE set to a role of the team (w2, whose own seat is down) is delivered" || { bad "say with a valid TEAM_ROLE"; tail -1 $T/state/messages.log; }
e2e_end=say-sender # the last line: test/e2e.sh checks that the file ran to here
