# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# The Stop hook gate, lib/stop_gate.sh run directly.
echo "--- stop gate hook (lib/stop_gate.sh, run directly with hook input on stdin)"
# A throwaway repo and a stand-in gate that records each run and passes only once g-pass exists.
mkdir -p $T/g && git -C $T/g init -q && git -C $T/g commit -q --allow-empty -m init
printf '#!/bin/sh\necho ran >> %s/gate-runs\n[ -f %s/g-pass ] && { echo all green; exit 0; }\necho "FAKE FAILURE: 1 test failed"\nexit 1\n' $T $T > $T/gate.sh; chmod +x $T/gate.sh
# gate <session> [workdir] [gate] [timeout]: runs the hook with max blocks 2; sets rc, out, err.
# ACTIVE=true marks a stop in a turn the hook has already sent back (stop_hook_active).
# Every send-back (exit 2) must say how to stop on purpose and give the limit: the text moved there
# from the shared prompt (#117), and the let-through stopReason is shown to the user, not to Claude.
# gate() records each send-back that lacks it in nopurp, and counts send-backs in bounces.
purp='If you are stopping on purpose (waiting for an answer or a review, or with a test red on purpose), say so in your report: the gate lets you stop after it has failed 2 times in a row in one turn.'
nopurp=""; bounces=0
gate() {
  printf '{"session_id":"%s","stop_hook_active":%s,"cwd":"/"}' "$1" "${ACTIVE:-false}" | $SRC/lib/stop_gate.sh $T/gstate w9 "${2:-$T/g}" "${3:-$T/gate.sh}" "${4:-30}" 2 >$T/gout 2>$T/gerr; rc=$?
  out=$(cat $T/gout); err=$(cat $T/gerr)
  if [ $rc = 2 ]; then bounces=$((bounces + 1)); echo "$err" | grep -qF "$purp" || nopurp="$nopurp $1"; fi
}
runs() { [ -f $T/gate-runs ] && wc -l < $T/gate-runs | tr -d ' ' || echo 0; }
gate s1; [ $rc = 0 ] && [ "$(runs)" = 0 ] && ok "clean tree: the stop goes through and the gate does not run" || bad "clean tree (rc=$rc, runs=$(runs))"
gate s1 $T/proj; [ $rc = 0 ] && [ "$(runs)" = 0 ] && ok "not a git work tree: the stop goes through, no gate" || bad "not a repo (rc=$rc)"
touch $T/g/new.txt
gate s1; [ $rc = 2 ] && [ "$(runs)" = 1 ] && echo "$err" | grep -qF "gate failed (exit 1): $T/gate.sh" && echo "$err" | grep -qF "FAKE FAILURE: 1 test failed" && echo "$err" | grep -qF "$T/gstate/gate/w9.log" && ok "dirty tree, failing gate: exit 2 with the command, its output and the log path on stderr" || { bad "failing gate (rc=$rc)"; echo "$err"; }
grep -qF "FAKE FAILURE" $T/gstate/gate/w9.log && ok "the gate's full output is in the log" || bad "gate log"
echo "$err" | grep -qF "Run $T/gate.sh in $T/g yourself (not lib/stop_gate.sh)" && ok "the send-back names the gate to run and where, and not the hook script" || { bad "send-back wording"; echo "$err"; }
ACTIVE=true gate s1; [ $rc = 2 ] && echo "$err" | grep -q "last time" && ok "second failure in a row in a turn (the limit, 2): still sent back, told it is the last time" || { bad "second failure (rc=$rc)"; echo "$err"; }
before=$(runs); ACTIVE=true gate s1; [ $rc = 0 ] && [ "$(runs)" = "$before" ] && echo "$out" | ruby -rjson -e 'j = JSON.parse(STDIN.read); exit(j["continue"] == false && j["stopReason"].include?("still failing") ? 0 : 1)' && ok "past the limit: the stop goes through with a stopReason, without running the gate again" || { bad "past the limit (rc=$rc, runs $before -> $(runs))"; echo "$out"; }
gate s1; [ $rc = 2 ] && ! echo "$err" | grep -q "last time" && ok "a new turn (stop_hook_active false) with the gate still failing is sent back again" || { bad "new turn after the limit (rc=$rc)"; echo "$out"; }
gate s2; [ $rc = 2 ] && ! echo "$err" | grep -q "last time" && ok "a new session starts counting again" || bad "new session (rc=$rc)"
echo "s2 1+1" > $T/gstate/gate/w9.count; ACTIVE=true gate s2; [ $rc = 2 ] && ! echo "$err" | grep -q "last time" && ok "a count file that is not a number counts as zero" || { bad "non-numeric count (rc=$rc)"; echo "$err"; }
touch $T/g-pass; gate s2; [ $rc = 0 ] && [ ! -e $T/gstate/gate/w9.count ] && ok "a passing gate lets the stop through and resets the count" || bad "passing gate (rc=$rc)"
rm $T/g-pass; gate s2; [ $rc = 2 ] && ! echo "$err" | grep -q "last time" && ok "after a pass, a failure counts from one again" || bad "count after a pass (rc=$rc)"
# Run by hand (no hook input): the gate runs and reports, but the count is left as it was.
cp $T/gstate/gate/w9.count $T/count-before; touch $T/g-pass
$SRC/lib/stop_gate.sh $T/gstate w9 $T/g $T/gate.sh 30 2 </dev/null >/dev/null 2>&1; rc=$?; rm $T/g-pass
[ $rc = 0 ] && cmp -s $T/count-before $T/gstate/gate/w9.count && ok "a run with no hook input (by hand) leaves the count alone" || bad "manual run changed the count (rc=$rc)"
# A gate that runs past its time is killed with everything it started (its process group).
printf '#!/bin/sh\nsleep 60 &\necho $! > %s/bgpid\nsleep 60\n' $T > $T/slow.sh; chmod +x $T/slow.sh
t0=$(date +%s); gate s3 $T/g $T/slow.sh 2; t1=$(date +%s); sleep 1
[ $rc = 2 ] && echo "$err" | grep -q "timed out after 2s" && ! echo "$err" | grep -q "Terminated" && [ $((t1 - t0)) -lt 15 ] && ! kill -0 "$(cat $T/bgpid)" 2>/dev/null && ok "a gate past its timeout is killed with its children, and the stop is sent back" || { bad "gate timeout (rc=$rc, $((t1 - t0))s)"; echo "$err"; }
# The hook's git calls never run a repository's fsmonitor program (#104), with the tree clean or
# dirty. The repo has a tracked file, because git asks fsmonitor only when the index has entries.
mkdir -p $T/gf && echo a > $T/gf/f && git -C $T/gf init -q && git -C $T/gf add f && git -C $T/gf commit -q -m init
printf '#!/bin/sh\necho ran >> %s/fsm-runs\nexit 1\n' $T > $T/fsm.sh; chmod +x $T/fsm.sh; git -C $T/gf config core.fsmonitor $T/fsm.sh
git -C $T/gf status --porcelain >/dev/null 2>&1; [ -s $T/fsm-runs ] || bad "test setup: a plain git status did not run the fsmonitor script"; rm -f $T/fsm-runs
touch $T/g-pass; before=$(runs)
gate s4 $T/gf; r1=$rc; echo b >> $T/gf/f; gate s4 $T/gf; r2=$rc; rm $T/g-pass
[ $r1 = 0 ] && [ $r2 = 0 ] && [ "$(runs)" = $((before + 1)) ] && [ ! -e $T/fsm-runs ] && ok "core.fsmonitor set: the hook's git calls do not run it (clean tree: no gate; dirty tree: the gate ran and passed)" \
  || bad "fsmonitor (rc $r1/$r2, gate runs $before -> $(runs), fsmonitor runs: $([ -f $T/fsm-runs ] && wc -l < $T/fsm-runs | tr -d ' ' || echo 0))"
# A git status that fails is not read as a clean tree (#104): the gate runs (fail closed), and the
# send-back says status failed. A garbage index makes status fail; rev-parse does not read it.
mkdir -p $T/gb && echo a > $T/gb/f && git -C $T/gb init -q && git -C $T/gb add f && git -C $T/gb commit -q -m init && printf 'not an index' > $T/gb/.git/index
git -C $T/gb status --porcelain >/dev/null 2>&1 && bad "test setup: a garbage index did not make git status fail"
before=$(runs); gate s5 $T/gb
[ $rc = 2 ] && [ "$(runs)" = $((before + 1)) ] && echo "$err" | grep -qF "git status failed" && echo "$err" | grep -qF "FAKE FAILURE" \
  && ok "a git status that fails (garbage index): the gate runs and its failure sends the seat back, saying status failed" || { bad "failed git status (rc=$rc, gate runs $before -> $(runs))"; echo "$err"; }
touch $T/g-pass; gate s5 $T/gb; rm $T/g-pass
[ $rc = 0 ] && ok "a git status that fails, passing gate: the stop goes through" || { bad "failed git status, passing gate (rc=$rc)"; echo "$err"; }
# A repository git cannot read is not taken for no repository (#118). With a corrupt HEAD, git says
# "not a git repository", exactly as it does for a plain folder, but the .git is there: the gate
# runs, and the send-back names the repository and git's error. The same for a worktree, whose .git
# is a file pointing at a gitdir with a corrupt HEAD. A plain folder with files stays ungated.
mkdir -p $T/gh && echo a > $T/gh/f && git -C $T/gh init -q && git -C $T/gh add f && git -C $T/gh commit -q -m init && echo b >> $T/gh/f && printf 'garbage\n' > $T/gh/.git/HEAD
git -C $T/gh rev-parse --is-inside-work-tree >/dev/null 2>&1 && bad "test setup: a corrupt HEAD did not make git rev-parse fail"
before=$(runs); gate s6 $T/gh
[ $rc = 2 ] && [ "$(runs)" = $((before + 1)) ] && echo "$err" | grep -qF "git cannot read the repository at $T/gh/.git" && echo "$err" | grep -qF "not a git repository" && echo "$err" | grep -qF "FAKE FAILURE" \
  && ok "a corrupt HEAD with a dirty tree: the gate runs, and the send-back names the repository and git's error" || { bad "corrupt HEAD (rc=$rc, gate runs $before -> $(runs))"; echo "$err"; }
mkdir -p $T/gwm && git -C $T/gwm init -q && git -C $T/gwm commit -q --allow-empty -m init && git -C $T/gwm worktree add -q --detach $T/gwt 2>/dev/null
touch $T/gwt/new.txt; printf 'garbage\n' > "$(git -C $T/gwt rev-parse --git-dir)/HEAD"
[ -f $T/gwt/.git ] && ! git -C $T/gwt rev-parse --is-inside-work-tree >/dev/null 2>&1 || bad "test setup: the worktree has no .git file, or its corrupt HEAD did not make rev-parse fail"
before=$(runs); gate s7 $T/gwt
[ $rc = 2 ] && [ "$(runs)" = $((before + 1)) ] && echo "$err" | grep -qF "git cannot read the repository at $T/gwt/.git" \
  && ok "a worktree (.git file) whose gitdir has a corrupt HEAD: the gate runs" || { bad "worktree with a corrupt HEAD (rc=$rc, gate runs $before -> $(runs))"; echo "$err"; }
mkdir -p $T/plain/sub && echo x > $T/plain/sub/file.txt
before=$(runs); gate s8 $T/plain/sub
[ $rc = 0 ] && [ "$(runs)" = "$before" ] && [ -z "$err" ] && ok "a plain folder with files and no .git anywhere above it: still ungated" || { bad "plain folder (rc=$rc, gate runs $before -> $(runs))"; echo "$err"; }
# Every send-back above (first, last, new turn, new session, timeout, failed status, unreadable
# repository and worktree) carried it.
[ "$bounces" -ge 10 ] && [ -z "$nopurp" ] && ok "every send-back ($bounces) says how to stop on purpose and gives the limit (2)" || bad "send-backs without the stop-on-purpose sentence and limit (sessions:$nopurp; $bounces send-backs)"
echo "--- the stop gate never writes or trusts its state through a link (#194)"
# up refuses a link at gate/ (#174), but the hook runs later, so one made after up is met here. The
# hook writes gate/, its log and its count, and trusts the count: a planted count could let a stop
# through ungated. Each link points at a sentinel, which must come out byte for byte as it went in.
# The tree is dirty and the gate fails, so without the check the hook would run it and write.
touch $T/g/new.txt
mkdir -p $T/gsent && printf 'sentinel log\n' > $T/gsent/w9.log && printf 's5 1\n' > $T/gsent/w9.count && cp -R $T/gsent $T/gsent.want
mv $T/gstate/gate $T/gstate/gate.real && ln -s $T/gsent $T/gstate/gate
before=$(runs); gate s5; r1=$rc; e1=$err; ACTIVE=true gate s5; r2=$rc; o2=$out
[ $r1 = 2 ] && echo "$e1" | grep -qF "$T/gstate/gate is a symlink" && [ "$(runs)" = "$before" ] && diff -r $T/gsent $T/gsent.want >/dev/null \
  && ok "a link at gate/: the hook does not run the gate or write through it, and sends the seat back naming it" || { bad "a link at gate/ (rc=$r1, gate runs $before -> $(runs))"; echo "$e1"; diff -r $T/gsent $T/gsent.want; }
[ $r2 = 0 ] && [ "$(runs)" = "$before" ] && echo "$o2" | L="$T/gstate/gate" ruby -rjson -e 'j = JSON.parse(STDIN.read); exit(j["continue"] == false && j["stopReason"].include?(ENV["L"] + " is a symlink") ? 0 : 1)' \
  && diff -r $T/gsent $T/gsent.want >/dev/null && ok "a link at gate/, in a turn the hook already sent back: the stop goes through, with a stopReason naming it" || { bad "a link at gate/, second stop (rc=$r2)"; echo "$o2"; }
rm $T/gstate/gate && mv $T/gstate/gate.real $T/gstate/gate
for f in log count; do
  rm -f $T/gstate/gate/w9.$f && ln -s $T/gsent/w9.$f $T/gstate/gate/w9.$f
  before=$(runs); gate s6
  [ $rc = 2 ] && echo "$err" | grep -qF "$T/gstate/gate/w9.$f is a symlink" && [ "$(runs)" = "$before" ] && diff -r $T/gsent $T/gsent.want >/dev/null \
    && ok "a link at gate/w9.$f: the hook does not run the gate or write through it, and sends the seat back naming it" || { bad "a link at gate/w9.$f (rc=$rc, gate runs $before -> $(runs))"; echo "$err"; diff -r $T/gsent $T/gsent.want; }
  rm $T/gstate/gate/w9.$f
done
# A hard link is a regular file to every test above (tl on #206): the hook refuses a second link.
for f in log count; do
  rm -f $T/gstate/gate/w9.$f && ln $T/gsent/w9.$f $T/gstate/gate/w9.$f
  before=$(runs); gate s7
  [ $rc = 2 ] && echo "$err" | grep -qF "$T/gstate/gate/w9.$f is a symlink, a hard link" && [ "$(runs)" = "$before" ] && diff -r $T/gsent $T/gsent.want >/dev/null \
    && ok "a hard link at gate/w9.$f: the hook does not run the gate or write through it, and sends the seat back naming it" || { bad "a hard link at gate/w9.$f (rc=$rc, gate runs $before -> $(runs))"; echo "$err"; diff -r $T/gsent $T/gsent.want; }
  rm $T/gstate/gate/w9.$f
done
e2e_end=gate # the last line: test/e2e.sh checks that the file ran to here
