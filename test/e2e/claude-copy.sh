# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# The seats' claude copy: replaced, failed, mid-reinstall. Uses the running em.
echo "--- the seats' claude copy: replaced, failed, mid-reinstall"
# Built under the name claude, so the new copy still matches the shared file (see settings.sh, #208).
mkdir -p $T/cc && cc -o $T/cc/claude $T/c.c && mv $T/cc/claude $CP
$S -c $T/team.yaml status | grep -E "^em " | grep -q REPLACED && ok "status: a seat whose claude file was replaced under it shows REPLACED" || { bad "status REPLACED"; $S -c $T/team.yaml status; }
TEAM_VIEW=0 $S -c $T/team.yaml up --no-view em 2>&1 | grep -q "ATTENTION em .*replaced" && ok "up: ATTENTION for a running seat whose claude was replaced" || bad "up: ATTENTION for a replaced claude"
printf 'team: tc\nrepo: { path: %s/repo, github: local/origin.git }\nproject: { name: B, url: "https://github.com/users/x/projects/9" }\nstorage: { volume: %s, root: %s }\nsessions: { prefix: tc, claude: { wrapper: %s/bin/wrap } }\nroles:\n  x: { title: X, workdir: { type: project, path: %s/proj }, prompt_text: "x" }\n' $T $VOL $ROOT $T $T > $T/tc.yaml
mkdir -p $T/state2/bin && chmod a-w $T/state2/bin
fc=$(TEAM_STATE_DIR=$T/state2 TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?; chmod u+w $T/state2/bin
[ $rc -ne 0 ] && echo "$fc" | grep -q "could not copy" && ! tmux has-session -t '=tc-x' 2>/dev/null && ok "a claude copy that cannot be written stops the start; nothing falls back to the shared install" || { bad "failed copy (rc=$rc)"; echo "$fc" | tail -3; }
mkdir -p $T/brk && ln -s $T/gone/claude.exe $T/brk/claude && ln -s "$(command -v tmux)" $T/brk/tmux
fc=$(PATH=$T/brk:/usr/bin:/bin TEAM_STATE_DIR=$T/state2 TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$fc" | grep -q "retry up" && ! tmux has-session -t '=tc-x' 2>/dev/null && ok "a shared claude caught mid-reinstall (a dangling link) stops the start with 'retry up'" || { bad "mid-reinstall (rc=$rc)"; echo "$fc" | tail -3; }
# Two ups at once: the second must not replace a copy the first one's seat may already run. A file
# put at the copy's path before the move (not executable, so up does not take it as finished) stays.
mkdir -p $T/state4/bin/claude-9.9.9 && printf 'x' > $T/state4/bin/claude-9.9.9/claude && ino=$(stat -f %i $T/state4/bin/claude-9.9.9/claude)
fc=$(TEAM_STATE_DIR=$T/state4 TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && [ "$(stat -f %i $T/state4/bin/claude-9.9.9/claude)" = "$ino" ] && [ -z "$(ls -A $T/state4/bin/claude-9.9.9 | grep partial)" ] && ! tmux has-session -t '=tc-x' 2>/dev/null && ok "an existing file at the copy's path is never replaced (no partial left, and the start is refused while it is not runnable)" || { bad "copy race (rc=$rc)"; echo "$fc" | tail -2; ls -la $T/state4/bin/claude-9.9.9; }
echo "--- up never runs a claude copy that differs from the shared claude (#208)"
# A runnable file already at the copy's path was taken as the copy without a look. Planted at the path
# of the version up is about to use, it would be what every seat runs: here, a script that records
# that it ran and then runs the real claude, as a seat would never notice. up must refuse it, start no
# seat, and leave the file as it is.
cv=$(basename "$(dirname "$CP")")
mkdir -p $T/stateb/bin/$cv && printf '#!/bin/sh\necho ran >> %s/planted.log\nexec %s/bin/claude "$@"\n' $T $T > $T/stateb/bin/$cv/claude && chmod 0555 $T/stateb/bin/$cv/claude
cp $T/stateb/bin/$cv/claude $T/planted.want; ino=$(stat -f %i $T/stateb/bin/$cv/claude)
fc=$(TEAM_STATE_DIR=$T/stateb TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?
sleep 1
[ $rc -ne 0 ] && echo "$fc" | grep -qF "$T/stateb/bin/$cv/claude is not the same file as" && echo "$fc" | grep -qF "refused, not replaced" && ! tmux has-session -t '=tc-x' 2>/dev/null && [ ! -e $T/planted.log ] \
  && [ "$(stat -f %i $T/stateb/bin/$cv/claude)" = "$ino" ] && cmp -s $T/stateb/bin/$cv/claude $T/planted.want \
  && ok "up refuses a runnable claude copy that differs from the shared claude, says it was not replaced, and no seat runs it" || { bad "a planted claude copy (rc=$rc)"; echo "$fc" | tail -3; cat $T/planted.log 2>/dev/null; }
TEAM_STATE_DIR=$T/stateb $S -c $T/tc.yaml down --yes x >/dev/null 2>&1
# A copy that matches the shared claude byte for byte is the copy: reused as it is, never copied again.
mkdir -p $T/statec/bin/$cv && cp $T/bin/claude $T/statec/bin/$cv/claude && chmod 0555 $T/statec/bin/$cv/claude && ino=$(stat -f %i $T/statec/bin/$cv/claude)
fc=$(TEAM_STATE_DIR=$T/statec TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?
[ $rc = 0 ] && tmux has-session -t '=tc-x' 2>/dev/null && [ "$(stat -f %i $T/statec/bin/$cv/claude)" = "$ino" ] && ! echo "$fc" | grep -qF "copied claude" \
  && [ ! -e $T/statec/bin/$cv/.how ] && [ -z "$(ls -A $T/statec/bin/$cv | grep partial)" ] \
  && ok "up reuses a claude copy that matches the shared claude, unchanged and without a new copy" || { bad "a matching claude copy (rc=$rc)"; echo "$fc" | tail -3; ls -la $T/statec/bin/$cv; }
TEAM_STATE_DIR=$T/statec $S -c $T/tc.yaml down --yes x >/dev/null 2>&1
e2e_end=claude-copy # the last line: test/e2e.sh checks that the file ran to here
