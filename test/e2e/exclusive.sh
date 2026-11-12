# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# run-exclusive (#214): one heavy run at a time on the host. Every case uses the run's own lock
# (FACTORY_RUN_LOCK, set by test/e2e.sh), never the real one. Ordering is checked only from marks the
# commands record, never from how long anything took: these runs are meant for a loaded machine.
echo "--- run-exclusive: one heavy run at a time (#214)"
rx=$T/rx; mkdir -p $rx
# Waits for a condition, up to 30s (a limit for a run that went wrong, not a timing check).
rx_until() { local i=0; until eval "$1"; do i=$((i + 1)); [ $i -ge 150 ] && return 1; sleep 0.2; done; }
# Waits for a background run and returns its status. If nesting or the lock's release regressed, a plain
# wait would hang the whole e2e, and every run on the host behind it, instead of failing a case (tl on
# #240). After about a minute the run is killed, and the case fails on its status (137).
rx_wait() { local i=0; while kill -0 $1 2>/dev/null; do i=$((i + 1)); [ $i -ge 300 ] && { kill -KILL $1 2>/dev/null; break; }; sleep 0.2; done; wait $1; }
# The same limit for a run in the foreground: it dies of the alarm (142).
rx_bound() { perl -e 'alarm 60; exec @ARGV' "$@"; }
# A holder (a script: run-exclusive runs a program) that records its start, then waits for a go file
# before it records its end: hold <name> <marks> <go file>.
printf '#!/bin/sh\necho "$1 start" >> "$2"\nuntil [ -e "$3" ]; do sleep 0.1; done\necho "$1 end" >> "$2"\n' > $rx/hold; chmod +x $rx/hold
real="$(ruby -retc -e 'print Etc.getpwuid(Process.uid).dir')/Library/Application Support/software-factory"; [ -e "$real" ] && real_was=1 || real_was=0

out=$($S run-exclusive -- sh -c 'echo ran; exit 7' 2>&1); rc=$?
[ $rc = 7 ] && [ "$out" = ran ] && ok "run-exclusive runs the command and exits with its status" || { bad "run-exclusive status (rc=$rc)"; echo "$out" | tail -2; }
out=$(TEAM_CONFIG=$T/no-such-team.yaml $S run-exclusive -- true 2>&1); rc=$?
[ $rc = 0 ] && [ -z "$out" ] && ok "run-exclusive needs no team file, and prints nothing when the lock is free" || { bad "run-exclusive without a team file (rc=$rc)"; echo "$out" | tail -2; }
out=$($S run-exclusive -- 'echo not a shell' 2>&1); rc=$?
[ $rc = 127 ] && ok "run-exclusive runs an argument list, never a shell string" || { bad "run-exclusive ran a shell string (rc=$rc)"; echo "$out" | tail -2; }

# Two runs wait while a third holds the lock; each says who holds it and since when; none overlaps.
m=$rx/marks; rm -f $rx/go
TEAM_ROLE=hx $S run-exclusive -- $rx/hold H $m $rx/go 2>$rx/h.err &
h=$!
rx_until "grep -q 'H start' $m 2>/dev/null"
for w in W1 W2; do
  TEAM_ROLE=$w $S run-exclusive -- sh -c 'echo "$0 start" >> "$1"; echo "$0 end" >> "$1"' $w $m 2>$rx/$w.err &
  eval "p$w=\$!"
done
rx_until "grep -q 'waiting for the lock' $rx/W1.err && grep -q 'waiting for the lock' $rx/W2.err"; waiting=$?
before=$(cat $m 2>/dev/null)
touch $rx/go; rx_wait $h; hrc=$?; rx_wait $pW1; w1rc=$?; rx_wait $pW2; w2rc=$?
# Each start is followed at once by its own end, H's first.
pairs=$(awk '{ if (NR % 2) { r = $1; if ($2 != "start") bad = 1 } else if ($1 != r || $2 != "end") bad = 1 } END { print (bad || NR != 6) ? "overlap" : "ok" }' $m 2>/dev/null)
[ $waiting = 0 ] && [ "$before" = "H start" ] && [ $hrc = 0 ] && [ $w1rc = 0 ] && [ $w2rc = 0 ] && [ "$pairs" = ok ] && [ "$(head -n 1 $m)" = "H start" ] \
  && ok "run-exclusive: two runs wait for the holder, then run one at a time, none overlapping" || { bad "run-exclusive: two waiting runs (waiting=$waiting h=$hrc w1=$w1rc w2=$w2rc)"; cat $m; cat $rx/W1.err $rx/W2.err; }
grep -q "held by hx[^(]* (pid [0-9]*, in .*), holding since [0-9-]*T[0-9:]*: $rx/hold H" $rx/W1.err && grep -q 'got the lock after' $rx/W1.err \
  && ok "run-exclusive: a waiting run says who holds the lock, since when, and when it got it" || { bad "run-exclusive: the waiting message"; cat $rx/W1.err; }

# A killed holder: TERM ends its command too, and releases the lock.
rm -f $rx/go $rx/k.pid
$S run-exclusive -- sh -c 'echo $$ > "$0"; while :; do sleep 0.2; done' $rx/k.pid 2>/dev/null &
h=$!
rx_until "[ -s $rx/k.pid ]"
$S run-exclusive -- sh -c 'echo ran > "$0"' $rx/k.ran 2>$rx/k.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/k.err"; waiting=$?
kill -TERM $h; rx_wait $h; hrc=$?; rx_wait $w; wrc=$?
rx_until "! kill -0 $(cat $rx/k.pid) 2>/dev/null"; gone=$?
[ $waiting = 0 ] && [ $hrc = 143 ] && [ $wrc = 0 ] && [ "$(cat $rx/k.ran 2>/dev/null)" = ran ] && [ $gone = 0 ] \
  && ok "run-exclusive: TERM to the holder ends its command and releases the lock to the waiting run" || { bad "run-exclusive: TERM to the holder (waiting=$waiting h=$hrc w=$wrc gone=$gone)"; cat $rx/k.err; }
# SIGKILL to the run alone: the kernel drops the lock, so the waiting run starts. (The killed run's
# command is orphaned and may still run: documented. It is ended here by hand.)
rm -f $rx/k.pid $rx/k.ran
$S run-exclusive -- sh -c 'echo $$ > "$0"; while :; do sleep 0.2; done' $rx/k.pid 2>/dev/null &
h=$!
rx_until "[ -s $rx/k.pid ]"
$S run-exclusive -- sh -c 'echo ran > "$0"' $rx/k.ran 2>$rx/k.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/k.err"; waiting=$?
kill -KILL $h; wait $h 2>/dev/null; rx_wait $w; wrc=$?
kill $(cat $rx/k.pid) 2>/dev/null
[ $waiting = 0 ] && [ $wrc = 0 ] && [ "$(cat $rx/k.ran 2>/dev/null)" = ran ] \
  && ok "run-exclusive: a holder killed with SIGKILL releases the lock to the waiting run" || { bad "run-exclusive: SIGKILL to the holder (waiting=$waiting w=$wrc)"; cat $rx/k.err; }
# A kill of the caller's process group, as the stop gate's time limit does: TERM, then KILL. The command
# ignores TERM. It must die with the run: in a group of its own it would run on without the lock, and
# the next run's start would fall between its start and its end (tl on #240).
rm -f $rx/g.pid $rx/g.marks $rx/g.go
perl -e 'setpgrp(0, 0); exec @ARGV' $S run-exclusive -- sh -c 'trap "" TERM; echo $$ > "$0"; echo "A start" >> "$1"; until [ -e "$2" ]; do sleep 0.1; done; echo "A end" >> "$1"' $rx/g.pid $rx/g.marks $rx/g.go 2>/dev/null &
g=$!
rx_until "[ -s $rx/g.pid ]"
gc=$(cat $rx/g.pid)
kill -TERM -- -$g; kill -0 $gc 2>/dev/null; survived=$?
kill -KILL -- -$g; wait $g 2>/dev/null
rx_until "! kill -0 $gc 2>/dev/null"; gone=$?
rx_bound $S run-exclusive -- sh -c 'echo "B start" >> "$0"' $rx/g.marks 2>/dev/null; brc=$?
# A command that ran on would record its end now.
touch $rx/g.go; sleep 0.5; kill -KILL $gc 2>/dev/null
marks=$(tr '\n' ' ' < $rx/g.marks)
[ $survived = 0 ] && [ $gone = 0 ] && [ $brc = 0 ] && [ "$marks" = "A start B start " ] \
  && ok "run-exclusive: TERM then KILL to the caller's group ends the command too, and the next run starts after it" || bad "run-exclusive: a kill of the group (survived=$survived gone=$gone next=$brc marks=$marks)"
# A stopped command acts on no signal until it is continued, so TERM to the run must continue it, or the
# lock stays held for the whole host (qa on #240: a background job that touched the terminal). The command
# handles TERM, as git does: on this system a stopped command with the default action dies of TERM anyway,
# so one without a handler would pass this case with or without the CONT.
rm -f $rx/st.pid
$S run-exclusive -- sh -c 'trap "exit 7" TERM; echo $$ > "$0"; kill -STOP $$; sleep 60' $rx/st.pid >/dev/null 2>&1 &
h=$!
rx_until '[ -s $rx/st.pid ] && ps -o stat= -p "$(cat $rx/st.pid)" | grep -q T'; stopped=$?
kill -TERM $h; rx_wait $h; hrc=$?
sc=$(cat $rx/st.pid 2>/dev/null); [ -n "$sc" ] && kill -KILL $sc 2>/dev/null
[ $stopped = 0 ] && [ $hrc = 7 ] && ok "run-exclusive: TERM to the run ends a stopped command and releases the lock" || bad "run-exclusive: a stopped command (stopped=$stopped run=$hrc)"
# In a terminal, the command stays in the foreground group: it can use the terminal instead of stopping
# there with the lock held, and Ctrl-C ends it (qa on #240). A pane of an interactive shell, as a person's.
rt=$rx/tty; mkdir -p $rt
tmux new-session -d -s rx-tty -x 120 -y 30 "env -u FACTORY_RUN_EXCLUSIVE_HELD FACTORY_RUN_LOCK=$rt/lock bash --norc --noprofile -i"
tmux send-keys -t "=rx-tty:" "$S run-exclusive -- sh -c 'stty -echo; echo set > $rt/set; sleep 60'; echo \$? > $rt/rc" Enter
rx_until "[ -e $rt/set ]"; used=$?
tmux send-keys -t "=rx-tty:" C-c
rx_until "[ -s $rt/rc ]"; ended=$?
trc=$(cat $rt/rc 2>/dev/null)
# Only a failure leaves a run here, stopped: ended by its exact pid from the record, or it would outlive the test.
rp=$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["pid"]' $rt/lock.holder 2>/dev/null)
[ -n "$rp" ] && { pkill -KILL -P $rp 2>/dev/null; kill -KILL $rp 2>/dev/null; }
tmux kill-session -t "=rx-tty:" 2>/dev/null
[ $used = 0 ] && [ $ended = 0 ] && [ "$trc" = 130 ] && ok "run-exclusive: in a terminal the command can use it, and Ctrl-C ends the run with 130" || bad "run-exclusive: in a terminal (used=$used ended=$ended rc=$trc)"
# A background job that reads the terminal: the system stops its whole group, this run too, as any shell
# job, so fg still works. From another shell, TERM and then CONT to the run must end both, though CONT
# reaches only the run, and the lock must come free (the command handles TERM, as in the case above).
rt=$rx/ttybg; mkdir -p $rt
tmux new-session -d -s rx-ttybg -x 120 -y 30 "env -u FACTORY_RUN_EXCLUSIVE_HELD FACTORY_RUN_LOCK=$rt/lock bash --norc --noprofile -i"
tmux send-keys -t "=rx-ttybg:" "$S run-exclusive -- bash -c 'trap \"exit 5\" TERM; echo \$\$ > $rt/pid; read x' &" Enter
rx_until '[ -s $rt/pid ] && ps -o stat= -p "$(cat $rt/pid)" | grep -q T'; stopped=$?
rp=$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["pid"]' $rt/lock.holder 2>/dev/null)
[ -n "$rp" ] && { kill -TERM $rp; kill -CONT $rp; }
rx_until "! kill -0 ${rp:-0} 2>/dev/null"; gone=$?
# Only a failure leaves these, stopped: ended by their exact pids, or they would outlive the test.
[ -n "$rp" ] && kill -KILL $rp 2>/dev/null; bc=$(cat $rt/pid 2>/dev/null); [ -n "$bc" ] && kill -KILL $bc 2>/dev/null
tmux kill-session -t "=rx-ttybg:" 2>/dev/null
[ $stopped = 0 ] && [ $gone = 0 ] && [ -n "$rp" ] && ok "run-exclusive: TERM then CONT to a background run stopped on the terminal ends it and its command" || bad "run-exclusive: a background run stopped on the terminal (stopped=$stopped gone=$gone run=$rp)"

# A holder record whose pid is gone (a SIGKILLed run leaves its record) names no one.
rm -f $rx/go
$S run-exclusive -- $rx/hold U $rx/u.marks $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'U start' $rx/u.marks 2>/dev/null"
sh -c 'exit 0' & dead=$!; wait $dead
printf '{"pid":%s,"who":"gone","since":"2000-01-01T00:00:00","cwd":"/","cmd":"x"}' $dead > $FACTORY_RUN_LOCK.holder
$S run-exclusive -- true 2>$rx/u.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/u.err"
touch $rx/go; rx_wait $h; rx_wait $w
grep -q 'held by an unknown holder' $rx/u.err && ! grep -q 'gone' $rx/u.err \
  && ok "run-exclusive: a holder record whose pid is gone shows an unknown holder" || { bad "run-exclusive: a dead holder record"; cat $rx/u.err; }
# The record's fields come from another run: control characters are shown escaped, never sent to the
# terminal that reads the waiting message (sec on #240).
rm -f $rx/go
$S run-exclusive -- $rx/hold C $rx/c.marks $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'C start' $rx/c.marks 2>/dev/null"
printf '{"pid":%s,"who":"a\\u001b[31mb","since":"x","cwd":"/","cmd":"y"}' $h > $FACTORY_RUN_LOCK.holder
$S run-exclusive -- true 2>$rx/c.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/c.err"
touch $rx/go; rx_wait $h; rx_wait $w
grep -qF 'a\x1B[31mb' $rx/c.err && ! LC_ALL=C grep -q "$(printf '\033')" $rx/c.err \
  && ok "run-exclusive: control characters in a holder record are shown escaped" || { bad "run-exclusive: control characters in a holder record"; cat -v $rx/c.err; }

# Nesting: a run-exclusive inside the command of another runs at once, instead of waiting for itself.
out=$(rx_bound $S run-exclusive -- $S run-exclusive -- sh -c 'echo nested' 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = nested ] && ok "run-exclusive inside run-exclusive runs at once (no wait for itself)" || { bad "nested run-exclusive (rc=$rc)"; echo "$out" | tail -2; }
# A stale variable (left in a tmux server started under the lock) whose pid is gone still waits.
rm -f $rx/go $rx/s.ran
$S run-exclusive -- $rx/hold S $rx/s.marks $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'S start' $rx/s.marks 2>/dev/null"
FACTORY_RUN_EXCLUSIVE_HELD=$FACTORY_RUN_LOCK:$dead $S run-exclusive -- sh -c 'echo ran > "$0"' $rx/s.ran 2>$rx/s.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/s.err"; waiting=$?
early=$(cat $rx/s.ran 2>/dev/null)
touch $rx/go; rx_wait $h; rx_wait $w
[ $waiting = 0 ] && [ -z "$early" ] && [ "$(cat $rx/s.ran 2>/dev/null)" = ran ] \
  && ok "run-exclusive: a stale FACTORY_RUN_EXCLUSIVE_HELD whose holder is gone does not skip the lock" || { bad "run-exclusive: stale held variable (waiting=$waiting early=$early)"; cat $rx/s.err; }
# The same, when the record names the same dead pid as the variable: only the pid's being alive tells.
rm -f $rx/go $rx/d.ran
$S run-exclusive -- $rx/hold D $rx/d.marks $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'D start' $rx/d.marks 2>/dev/null"
printf '{"pid":%s,"who":"gone","since":"2000-01-01T00:00:00","cwd":"/","cmd":"x"}' $dead > $FACTORY_RUN_LOCK.holder
FACTORY_RUN_EXCLUSIVE_HELD=$FACTORY_RUN_LOCK:$dead $S run-exclusive -- sh -c 'echo ran > "$0"' $rx/d.ran 2>$rx/d.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/d.err"; waiting=$?
early=$(cat $rx/d.ran 2>/dev/null)
touch $rx/go; rx_wait $h; rx_wait $w
[ $waiting = 0 ] && [ -z "$early" ] && [ "$(cat $rx/d.ran 2>/dev/null)" = ran ] \
  && ok "run-exclusive: a held variable and a record that name the same dead pid do not skip the lock" || { bad "run-exclusive: a dead pid in the variable and the record (waiting=$waiting early=$early)"; cat $rx/d.err; }
# No record means a nested call cannot see its parent holds the lock, and it would wait for itself with
# every other run behind it. So nothing runs, even the outer command (tl on #240).
mkdir -p $rx/nr/lock.holder
out=$(rx_bound env FACTORY_RUN_LOCK=$rx/nr/lock $S run-exclusive -- $S run-exclusive -- sh -c 'echo SHOULD-NOT-RUN' 2>&1); rc=$?
left=$(ls -A $rx/nr | grep -v -x -e lock -e lock.holder)
rmdir $rx/nr/lock.holder
after=$(rx_bound env FACTORY_RUN_LOCK=$rx/nr/lock $S run-exclusive -- sh -c 'echo ran' 2>&1); arc=$?
[ $rc = 1 ] && echo "$out" | grep -q 'could not write the holder record' && ! echo "$out" | grep -q SHOULD-NOT-RUN && [ -z "$left" ] && [ $arc = 0 ] && [ "$after" = ran ] \
  && ok "run-exclusive: a holder record it cannot write runs nothing, leaves no temporary file and frees the lock" || { bad "run-exclusive: an unwritable holder record (rc=$rc left=$left after=$arc)"; echo "$out" | tail -2; }
# Bytes that are not valid text (under LC_ALL=C, any that are not ASCII) reach the record, the waiting
# message and the nesting check. None may end the run in a stack trace.
out=$(rx_bound $S run-exclusive -- sh -c 'echo ran' "$(printf '\377')" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = ran ] && ok "run-exclusive runs a command with an argument that is not valid UTF-8" || { bad "run-exclusive: an argument that is not valid UTF-8 (rc=$rc)"; echo "$out" | tail -2; }
out=$(FACTORY_RUN_EXCLUSIVE_HELD="$(printf '\377'):1" rx_bound $S run-exclusive -- sh -c 'echo ran' 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = ran ] && ok "run-exclusive takes the lock when the held variable is not valid UTF-8" || { bad "run-exclusive: a held variable that is not valid UTF-8 (rc=$rc)"; echo "$out" | tail -2; }
# Under LC_ALL=C, in a folder and with a lock whose names are not ASCII: a run, a nested run and a waiter.
rb=$rx/$(printf 'd\303\251'); mkdir -p $rb/w; rm -f $rx/go
out=$(cd $rb/w && LC_ALL=C FACTORY_RUN_LOCK=$rb/lock rx_bound $S run-exclusive -- $S run-exclusive -- sh -c 'echo nested' 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = nested ] && ok "run-exclusive under LC_ALL=C runs and nests in a folder whose name is not ASCII" || { bad "run-exclusive: LC_ALL=C and a name that is not ASCII (rc=$rc)"; echo "$out" | tail -2; }
(cd $rb/w && exec env FACTORY_RUN_LOCK=$rb/lock $S run-exclusive -- $rx/hold E $rx/e.marks $rx/go) 2>/dev/null &
h=$!
rx_until "grep -q 'E start' $rx/e.marks 2>/dev/null"
LC_ALL=C FACTORY_RUN_LOCK=$rb/lock $S run-exclusive -- true 2>$rx/e.err &
w=$!
rx_until "grep -q 'waiting for the lock' $rx/e.err"; waiting=$?
touch $rx/go; rx_wait $h; rx_wait $w; wrc=$?
[ $waiting = 0 ] && [ $wrc = 0 ] && ! grep -q 'Error\|\.rb:' $rx/e.err \
  && ok "run-exclusive under LC_ALL=C waits for a holder whose folder name is not ASCII" || { bad "run-exclusive: a waiter under LC_ALL=C (waiting=$waiting w=$wrc)"; cat $rx/e.err; }

# The lock is never taken through a link (#194's checks).
mkdir -p $rx/ln && ln -s $rx/ln-target $rx/ln/lock
out=$(FACTORY_RUN_LOCK=$rx/ln/lock $S run-exclusive -- sh -c 'echo SHOULD-NOT-RUN' 2>&1); rc=$?
[ $rc = 1 ] && echo "$out" | grep -qF "$rx/ln/lock is a symlink" && ! echo "$out" | grep -q SHOULD-NOT-RUN && [ ! -e $rx/ln-target ] \
  && ok "run-exclusive refuses a lock file that is a symlink, and runs nothing" || { bad "run-exclusive through a symlink (rc=$rc)"; echo "$out" | tail -2; }
: > $rx/hl-other; mkdir -p $rx/hl && ln $rx/hl-other $rx/hl/lock
out=$(FACTORY_RUN_LOCK=$rx/hl/lock $S run-exclusive -- sh -c 'echo SHOULD-NOT-RUN' 2>&1); rc=$?
[ $rc = 1 ] && echo "$out" | grep -qF "$rx/hl/lock is a symlink, a hard link" && echo "$out" | grep -qF "Do not delete this file: it may be the real one, with a second name made elsewhere. Remove the other name, or move this file aside" && ! echo "$out" | grep -qF "exact path" && ! echo "$out" | grep -q SHOULD-NOT-RUN \
  && ok "run-exclusive refuses a lock file that is a hard link, and runs nothing" || { bad "run-exclusive through a hard link (rc=$rc)"; echo "$out" | tail -2; }
mkdir -p $rx/ld-target && ln -s $rx/ld-target $rx/ld
out=$(FACTORY_RUN_LOCK=$rx/ld/lock $S run-exclusive -- sh -c 'echo SHOULD-NOT-RUN' 2>&1); rc=$?
[ $rc = 1 ] && echo "$out" | grep -qF "$rx/ld is a symlink or not a folder" && ! echo "$out" | grep -q SHOULD-NOT-RUN && [ -z "$(ls -A $rx/ld-target)" ] \
  && ok "run-exclusive refuses a lock folder that is a symlink, and makes nothing in it" || { bad "run-exclusive through a symlinked folder (rc=$rc)"; echo "$out" | tail -2; }
out=$(cd $rx && FACTORY_RUN_LOCK=rel/lock $S run-exclusive -- sh -c 'echo SHOULD-NOT-RUN' 2>&1); rc=$?
[ $rc = 64 ] && echo "$out" | grep -q 'must be an absolute path' && ! echo "$out" | grep -q SHOULD-NOT-RUN && [ ! -e $rx/rel ] \
  && ok "run-exclusive refuses a relative FACTORY_RUN_LOCK: it would name a different lock in each folder" || { bad "run-exclusive with a relative lock (rc=$rc)"; echo "$out" | tail -2; }
[ "$(stat -f %Lp $(dirname $FACTORY_RUN_LOCK))" = 700 ] && ok "run-exclusive makes the lock's folder owner-only (700)" || bad "run-exclusive lock folder mode ($(stat -f %Lp $(dirname $FACTORY_RUN_LOCK)))"
# Waiting runs get the lock in the order they arrived (#283). D holds it; W1..W4 start one after the other,
# each only once the one before it is waiting (a run's place is taken before it says it waits), and they
# must run in that order. Checked from the marks the commands record, never from timing.
qd=$FACTORY_RUN_LOCK.queue; rm -f $rx/go $rx/ord.marks
$S run-exclusive -- $rx/hold D $rx/ord.d $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'D start' $rx/ord.d 2>/dev/null"
for w in W1 W2 W3 W4; do
  $S run-exclusive -- sh -c 'echo "$0" >> "$1"' $w $rx/ord.marks 2>$rx/ord-$w.err &
  eval "p$w=\$!"
  rx_until "grep -q 'waiting for the lock' $rx/ord-$w.err"
  sleep 1.2 # runs that poll the lock every 2s would then be at different points of their cycle: first come, first served is not luck
done
nq=$(ls $qd 2>/dev/null | wc -l | tr -d " ")
touch $rx/go; rx_wait $h; rx_wait $pW1; r1=$?; rx_wait $pW2; r2=$?; rx_wait $pW3; r3=$?; rx_wait $pW4; r4=$?
[ "$(tr '\n' ' ' < $rx/ord.marks)" = "W1 W2 W3 W4 " ] && [ $r1 = 0 ] && [ $r2 = 0 ] && [ $r3 = 0 ] && [ $r4 = 0 ] && [ "$nq" = 4 ] \
  && ok "run-exclusive: four waiting runs get the lock in the order they arrived" || { bad "run-exclusive: arrival order (marks: $(tr '\n' ' ' < $rx/ord.marks), tickets=$nq, rc $r1 $r2 $r3 $r4)"; cat $rx/ord-W3.err; }
grep -q '2 earlier runs are waiting ahead of this one' $rx/ord-W3.err && ! grep -q 'earlier run' $rx/ord-W1.err && [ ! -e $qd ] \
  && ok "run-exclusive: a waiting run says how many are ahead of it, and the queue folder is gone when the last has run" || { bad "run-exclusive: the queue message or folder"; cat $rx/ord-W3.err $rx/ord-W1.err; ls -A $qd 2>&1; }
# A waiter that is killed gives up its place: TERM at once (its own exit removes the ticket), SIGKILL as soon as
# the next poll finds the ticket's lock dropped. The others still run in order, nothing blocks a later run,
# and no ticket is left. W1 (first in line) gets TERM, W2 SIGKILL; W3 and W4 must run, in that order.
rm -f $rx/go $rx/kq.marks
$S run-exclusive -- $rx/hold D $rx/kq.d $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'D start' $rx/kq.d 2>/dev/null"
for w in W1 W2 W3 W4; do
  $S run-exclusive -- sh -c 'echo "$0" >> "$1"' $w $rx/kq.marks 2>$rx/kq-$w.err &
  eval "p$w=\$!"
  rx_until "grep -q 'waiting for the lock' $rx/kq-$w.err"
  sleep 1.2 # runs that poll the lock every 2s would then be at different points of their cycle: first come, first served is not luck
done
kill -TERM $pW1; rx_wait $pW1; k1=$?
t1=$(ls $qd | wc -l | tr -d " ")
kill -KILL $pW2; wait $pW2 2>/dev/null
rx_until "[ \"\$(ls $qd | wc -l | tr -d ' ')\" = 2 ]"; t2=$?
touch $rx/go; rx_wait $h; rx_wait $pW3; k3=$?; rx_wait $pW4; k4=$?
after=$(rx_bound $S run-exclusive -- sh -c 'echo ran' 2>&1); arc=$?
[ $k1 = 143 ] && [ "$t1" = 3 ] && [ $t2 = 0 ] && [ "$(tr '\n' ' ' < $rx/kq.marks)" = "W3 W4 " ] && [ $k3 = 0 ] && [ $k4 = 0 ] && [ ! -e $qd ] && [ $arc = 0 ] && [ "$after" = ran ] \
  && ok "run-exclusive: a waiter killed by TERM or SIGKILL gives up its place, the others still run in order, nothing is left behind" || { bad "run-exclusive: killed waiters (k1=$k1 tickets after TERM=$t1, after KILL wait=$t2, marks: $(tr '\n' ' ' < $rx/kq.marks), k3=$k3 k4=$k4, after=$arc/$after)"; ls -A $qd 2>&1; }
# A waiter that is stopped (Ctrl-Z, kill -STOP) still holds its flock, so it must not hold up the line (tl on
# #284): each waiting run touches its ticket every poll, and one untouched for TICKET_STALE seconds is dropped.
# W1 is stopped at the front while D holds; D ends; W2 must run without W1 being continued. Then W1 is
# continued: it finds its ticket gone, takes a new place, and runs.
rm -f $rx/go $rx/st.marks
$S run-exclusive -- $rx/hold D $rx/st.d $rx/go 2>/dev/null &
h=$!
rx_until "grep -q 'D start' $rx/st.d 2>/dev/null"
for w in W1 W2; do
  $S run-exclusive -- sh -c 'echo "$0" >> "$1"' $w $rx/st.marks 2>$rx/st-$w.err &
  eval "p$w=\$!"
  rx_until "grep -q 'waiting for the lock' $rx/st-$w.err"
  sleep 1.2
done
t1=$(ls $qd | sort | head -1); rpid=${t1##*-}
kill -STOP $rpid
touch $rx/go; rx_wait $h
rx_wait $pW2; s2=$?
m2=$(tr '\n' ' ' < $rx/st.marks)
kill -CONT $rpid; rx_wait $pW1; s1=$?
[ $s2 = 0 ] && [ "$m2" = "W2 " ] && [ $s1 = 0 ] && [ "$(tr '\n' ' ' < $rx/st.marks)" = "W2 W1 " ] && [ ! -e $qd ] \
  && ok "run-exclusive: a stopped waiter at the front does not hold up the runs behind it, and runs after it is continued" || { bad "run-exclusive: stopped waiter (W2 rc=$s2 marks then: $m2, W1 rc=$s1, marks now: $(tr '\n' ' ' < $rx/st.marks))"; cat $rx/st-W1.err $rx/st-W2.err; ls -A $qd 2>&1; }
# A ticket whose run is gone, and things that are not tickets, never hold a run up; only names are removed.
mkdir -p $qd; : > $qd/00000000000000000001-1; ln -s $rx/ord.marks $qd/00000000000000000002-2; mkdir $qd/00000000000000000003-3; : > $qd/.tmp-99; touch -t 202001010000 $qd/.tmp-99 # a .tmp younger than 5s may be a run about to lock it
before=$(cat $rx/ord.marks | wc -l)
out=$(rx_bound $S run-exclusive -- sh -c 'echo ran' 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = ran ] && [ ! -e $qd/00000000000000000001-1 ] && [ ! -e $qd/.tmp-99 ] && [ ! -L $qd/00000000000000000002-2 ] && [ -d $qd/00000000000000000003-3 ] && [ "$(cat $rx/ord.marks | wc -l)" = "$before" ] \
  && ok "run-exclusive: a stale ticket is not waited for and is removed, and a link or folder in the queue is never followed" || { bad "run-exclusive: stale tickets (rc=$rc)"; echo "$out" | tail -2; ls -A $qd; }
rmdir $qd/00000000000000000003-3; rmdir $qd 2>/dev/null

# test/e2e.sh takes the lock itself (#309): it starts itself again under run-exclusive, whoever started it.
# The file runs as it is, from a scratch tree where every area is a stub and the first one is a fixture (as
# in test/e2e-exit-trap.sh), with the real fabrikito behind a link: a run takes a few seconds, starts no
# tmux server, and takes this run's lock (FACTORY_RUN_LOCK), never the real one. The fixture writes down
# what it finds inside the run: its arguments, what is left of the lock step's variables, whether the
# caller's lock is held and by which command, and whether the run's own lock works. With $el/wait there,
# it then waits for $el/ego. Ordering is checked from the marks, as above.
echo "--- test/e2e.sh takes the run lock itself (#309)"
el=$rx/el; mkdir -p $el/src/test/e2e $el/vol
cp $SRC/test/e2e.sh $el/src/test/e2e.sh; ln -s $SRC/fabrikito $el/src/fabrikito
# The tmux guard too (#307): test/e2e.sh starts nothing from a tree that has none, as test/e2e-exit-trap.sh's tree shows.
mkdir $el/src/test/guard && cp $SRC/test/guard/tmux $el/src/test/guard/tmux && chmod +x $el/src/test/guard/tmux
echo 'int main(void) { return 0; }' > $el/src/test/e2e/fake-claude.c
for el_a in lib $AREAS; do echo "e2e_end=$el_a" > $el/src/test/e2e/$el_a.sh; done
{ echo "el_d=$el; el_lock=$FACTORY_RUN_LOCK"; cat <<'EOF'
echo "$T_TOP" > $el_d/top; echo "E start" >> $el_d/marks
{ echo "args=$#:${2-}"; echo "var=${EL_VAR-unset}"
  echo "left=${E2E_LOCK_PID-unset},${E2E_NO_LOCK-unset},${FACTORY_RUN_EXCLUSIVE_HELD-unset}"; echo "tree=${E2E_LOCK_TREE-unset}"
  [ "$FACTORY_RUN_LOCK" = "$T/rx-lock/run-exclusive.lock" ] && echo "own=yes" || echo "own=no"
  echo "outer=$(ruby -e 'f = (File.open(ARGV[0]) rescue exit); puts f.flock(File::LOCK_EX | File::LOCK_NB) ? "free" : "held"' "$el_lock")"
  echo "holder=$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["cmd"]' "$el_lock.holder" 2>/dev/null)"
  echo "inner=$($S run-exclusive -- sh -c 'echo ran' 2>&1)$([ -f "$T/rx-lock/run-exclusive.lock" ] && echo ", on its own lock")"
} > $el_d/seen
if [ -e $el_d/wait ]; then until [ -e $el_d/ego ]; do sleep 0.1; done; fi
echo "E end" >> $el_d/marks
EOF
  echo "e2e_end=${AREAS%% *}"; } > $el/src/test/e2e/${AREAS%% *}.sh
el_cmd="env TEST_VOLUME=$el/vol $BASH $el/src/test/e2e.sh"
el_reset() { rm -f $el/marks $el/seen $el/top $el/out $el/wait $el/ego $el/hgo; }
el_result() { grep -qE '^RESULT pass=[1-9][0-9]* fail=0$'; }
el_show() { echo "  marks: $(tr '\n' ' ' < $el/marks 2>/dev/null)"; sed 's/^/  seen: /' $el/seen 2>/dev/null; }

# Outside the lock, and the lock is free: the run takes it, and holds it while the cases run.
el_reset
out=$(EL_VAR=kept rx_bound $el_cmd one "two words" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | el_result && grep -qx 'outer=held' $el/seen && grep -q "^holder=.* $el/src/test/e2e.sh one two words\$" $el/seen \
  && ok "test/e2e.sh started outside the lock takes it: the lock is held while the cases run, by this run" || { bad "test/e2e.sh outside the lock (rc=$rc)"; echo "$out" | tail -3; el_show; }
grep -qx 'left=unset,unset,unset' $el/seen && grep -qx 'own=yes' $el/seen && grep -qx 'inner=ran, on its own lock' $el/seen \
  && ok "test/e2e.sh under the lock it took: none of the lock's variables is left, and the run's own lock works" || { bad "test/e2e.sh: the run's own lock and what is left of the variables"; el_show; }
grep -qx 'args=2:two words' $el/seen && grep -qx 'var=kept' $el/seen \
  && ok "test/e2e.sh: arguments and the environment reach the run it starts under the lock" || { bad "test/e2e.sh: arguments and environment after the lock step"; el_show; }
# Outside the lock while another run holds it: it waits, says so, and runs after that run.
el_reset
$S run-exclusive -- $rx/hold H $el/marks $el/hgo 2>/dev/null &
h=$!
rx_until "grep -q 'H start' $el/marks 2>/dev/null"
$el_cmd > $el/out 2>&1 &
e=$!
rx_until "grep -q 'waiting for the lock' $el/out"; waiting=$?
before=$(cat $el/marks 2>/dev/null)
touch $el/hgo; rx_wait $h; hrc=$?; rx_wait $e; erc=$?
[ $waiting = 0 ] && [ "$before" = "H start" ] && [ $hrc = 0 ] && [ $erc = 0 ] && el_result < $el/out && [ "$(tr '\n' ' ' < $el/marks)" = "H start H end E start E end " ] \
  && ok "test/e2e.sh started while another run holds the lock waits for it, says so, and runs after it" || { bad "test/e2e.sh while the lock is held (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
# Under run-exclusive already (the command the docs gave until #309): it does not wait for itself.
el_reset
out=$(rx_bound $S run-exclusive -- $el_cmd 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | el_result && ! echo "$out" | grep -q 'waiting for the lock' && grep -qx 'outer=held' $el/seen && grep -q "^holder=env TEST_VOLUME=$el/vol " $el/seen \
  && ok "test/e2e.sh under run-exclusive runs at once: it does not wait for itself, and the lock stays with the run that took it" || { bad "test/e2e.sh under run-exclusive (rc=$rc)"; echo "$out" | tail -3; el_show; }
# The explicit option: E2E_NO_LOCK=1 runs without the lock, here while another run holds it.
el_reset
$S run-exclusive -- $rx/hold H $el/marks $el/hgo 2>/dev/null &
h=$!
rx_until "grep -q 'H start' $el/marks 2>/dev/null"
out=$(E2E_NO_LOCK=1 rx_bound $el_cmd 2>&1); rc=$?
during=$(tr '\n' ' ' < $el/marks)
touch $el/hgo; rx_wait $h; hrc=$?
[ $rc = 0 ] && echo "$out" | el_result && [ "$during" = "H start E start E end " ] && [ $hrc = 0 ] && grep -q "^holder=$rx/hold H " $el/seen && grep -qx 'left=unset,unset,unset' $el/seen \
  && ok "test/e2e.sh with E2E_NO_LOCK=1 runs without the lock, while another run holds it, and the option is not left for what it starts" || { bad "test/e2e.sh with E2E_NO_LOCK=1 (rc=$rc h=$hrc during: $during)"; echo "$out" | tail -3; el_show; }
# E2E_LOCK_PID alone is not trusted: one that names another process, here the very run that holds the
# lock, does not skip the lock. Then TERM to the waiting run ends it, and nothing of the run starts.
el_reset
$S run-exclusive -- $rx/hold H $el/marks $el/hgo 2>/dev/null &
h=$!
rx_until "grep -q 'H start' $el/marks 2>/dev/null"
E2E_LOCK_PID=$h $el_cmd > $el/out 2>&1 &
e=$!
rx_until "grep -q 'waiting for the lock' $el/out"; waiting=$?
[ $waiting = 0 ] && [ "$(cat $el/marks)" = "H start" ] \
  && ok "test/e2e.sh does not trust E2E_LOCK_PID alone: one that names another process, even the lock's holder, still waits for the lock" || { bad "test/e2e.sh skipped the lock on an E2E_LOCK_PID that is not its own (waiting=$waiting)"; tail -3 $el/out; el_show; }
kill -TERM $e; rx_wait $e; erc=$?
touch $el/hgo; rx_wait $h; hrc=$?
[ $erc = 143 ] && [ $hrc = 0 ] && [ "$(tr '\n' ' ' < $el/marks)" = "H start H end " ] && [ ! -e $el/top ] && ! grep -q -e RESULT -e ABORTED $el/out \
  && ok "TERM to test/e2e.sh while it waits for the lock ends the wait (143), and nothing of the run starts" || { bad "TERM to test/e2e.sh while it waits (e=$erc h=$hrc)"; tail -3 $el/out; el_show; }
# TERM during the run goes to the pid the caller started, which is run-exclusive now: it must still reach
# the run's exit trap (#306), and the lock must come free.
el_reset; touch $el/wait
$el_cmd > $el/out 2>&1 &
e=$!
rx_until "[ -s $el/seen ]"; started=$?
kill -TERM $e; rx_wait $e; erc=$?
el_top=$(cat $el/top 2>/dev/null)
after=$(rx_bound $S run-exclusive -- sh -c 'echo ran' 2>&1)
[ $started = 0 ] && [ $erc = 143 ] && grep -q '^ABORTED before the end' $el/out && [ "$(cat $el/marks)" = "E start" ] && [ -n "$el_top" ] && [ ! -e "$el_top" ] && [ "$after" = ran ] \
  && ok "TERM to test/e2e.sh during the run reaches its exit trap through run-exclusive: the scratch folder is removed, exit 143, and the lock is free" || { bad "TERM to test/e2e.sh during the run (started=$started e=$erc after=$after)"; tail -3 $el/out; el_show; }
# Whatever the result: the fixture waits for this file, and rx_wait's limit bounds run-exclusive, not the
# run under it. If TERM did not get through, which is what the case is for, the run would loop for ever.
touch $el/ego
# Only a failure leaves that run's scratch folder: removed by the path it wrote down, if shaped like one.
case $el_top in "$e2e_tmp"/team-e2e.????) if [ -d "$el_top" ]; then rm -rf "$el_top"; fi ;; esac
# el_queued [command...]: a run queued behind a held lock. The command runs while the run waits, then the
# lock is released. Leaves waiting, hrc (the holder) and erc (the run); EL_RUN replaces the run's command.
el_queued() {
  el_reset
  $S run-exclusive -- $rx/hold H $el/marks $el/hgo 2>/dev/null &
  h=$!
  rx_until "grep -q 'H start' $el/marks 2>/dev/null"
  ${EL_RUN:-$el_cmd} > $el/out 2>&1 &
  e=$!
  rx_until "grep -q 'waiting for the lock' $el/out"; waiting=$?
  [ $# -eq 0 ] || "$@"
  touch $el/hgo; rx_wait $h; hrc=$?; rx_wait $e; erc=$?
}
el_ran() { [ $waiting = 0 ] && [ $hrc = 0 ] && [ $erc = 0 ] && el_result < $el/out && [ "$(tr '\n' ' ' < $el/marks)" = "H start H end E start E end " ]; }
el_stopped() { [ $waiting = 0 ] && [ $hrc = 0 ] && [ $erc = 64 ] && [ "$(tr '\n' ' ' < $el/marks)" = "H start H end " ] && [ ! -e $el/top ] && ! grep -q -e RESULT -e ABORTED $el/out; }
el_git() { git -C $el/src -c user.name=e2e -c user.email=e2e@example.invalid "$@"; }
# The option is 1 and nothing else (sec2 on #356): any other value takes the lock, as no value does.
EL_RUN="env E2E_NO_LOCK=0 $el_cmd" el_queued
el_ran && grep -qx 'left=unset,unset,unset' $el/seen \
  && ok "test/e2e.sh with E2E_NO_LOCK=0 takes the lock like a run without the option: only 1 runs without it" || { bad "test/e2e.sh with E2E_NO_LOCK=0 (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
# A run that waited tests the tree as it is after the wait, so it stops when that is no longer the tree it
# was queued for (sec2 on #356): a seat that moves its worktree to its next task while its run queues
# would otherwise report a result for another commit. Only a tree that is itself the top of a git checkout
# is recorded and compared. The stub tree above was none, and its runs went on; one that merely sits
# inside some other checkout is not judged by that checkout's state either (tl on #356).
git init -q $el && git -C $el -c user.name=e2e -c user.email=e2e@example.invalid commit -q --allow-empty -m outer
el_queued git -C $el -c user.name=e2e -c user.email=e2e@example.invalid commit -q --allow-empty -m "outer moved"
el_ran && ok "test/e2e.sh in a tree that only sits inside another git checkout is not judged by that checkout: the run goes on after its wait" || { bad "test/e2e.sh in a tree inside another checkout (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
git init -q $el/src && el_git add -A && el_git commit -q -m tree || bad "test setup: could not make the stub tree a git checkout"
el_h1=$(el_git rev-parse HEAD)
el_queued
el_ran && grep -qx 'tree=unset' $el/seen \
  && ok "test/e2e.sh in a git checkout that did not change while the run waited runs as before, and the record of the tree is not left for what it starts" || { bad "test/e2e.sh in an unchanged checkout (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
el_queued el_git commit -q --allow-empty -m "the next task"
el_h2=$(el_git rev-parse HEAD)
el_stopped && grep -F "$el_h1" $el/out | grep -F "$el_h2" | grep -qF "export" \
  && ok "test/e2e.sh stops (64) before anything is made when HEAD moved while the run waited, naming both commits and the export" || { bad "test/e2e.sh after HEAD moved during the wait (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
el_queued touch $el/src/a-new-file
el_stopped && grep -F "$el_h2" $el/out | grep -qF "changed or new files" \
  && ok "test/e2e.sh stops (64) when the tree's changed or new files differ after the wait, at the same commit" || { bad "test/e2e.sh after a new file during the wait (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
rm -f $el/src/a-new-file
# git missing or failing, at either start, means no record and no check, never a new failure (tl on #356).
# Here git answers at the first start and fails at the second, with HEAD moved in between.
mkdir -p $el/nogit; printf '#!/bin/sh\nif [ -e %s/gitfails ]; then for a in "$@"; do [ "$a" = --show-toplevel ] && exit 1; done; fi\nexec %s "$@"\n' $el "$(command -v git)" > $el/nogit/git; chmod +x $el/nogit/git
el_break() { touch $el/gitfails; el_git commit -q --allow-empty -m "moved, and git fails"; }
# A script puts the stand-in first on PATH: PATH may hold a space, and EL_RUN is split into words.
printf '#!/bin/sh\nPATH=%s/nogit:$PATH exec env TEST_VOLUME=%s/vol %s %s/src/test/e2e.sh\n' $el $el "$BASH" $el > $el/nogit/run; chmod +x $el/nogit/run
EL_RUN=$el/nogit/run el_queued el_break
rm -f $el/gitfails
el_ran && ok "test/e2e.sh goes on when git cannot describe the tree after the wait: no check, never a new failure" || { bad "test/e2e.sh with a git that fails after the wait (waiting=$waiting h=$hrc e=$erc)"; tail -3 $el/out; el_show; }
# What this can show is that the cases of this area, which all run on the run's own lock, did not make
# the real lock's folder. It says nothing about the run as a whole: started plainly, the run's own lock
# step (#309) took the real lock before this area began, and made the folder then if it was not there.
# So it can fail only where the folder was missing when the area began: a run with E2E_NO_LOCK=1 or with
# a lock elsewhere, on a machine that has none yet. Where the folder exists it cannot tell who made it.
{ [ $real_was = 1 ] || [ ! -e "$real" ]; } && ok "this area's cases, on the run's own lock, did not make the real lock's folder ($real)" || bad "this area's cases made the real lock's folder $real"
e2e_end=exclusive # the last line: test/e2e.sh checks that the file ran to here
