# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# The seats' claude copy: replaced, failed, mid-reinstall, a link. Uses the running em. Also the
# files up writes in the state folder, never written through a link.
echo "--- the seats' claude copy: replaced, failed, mid-reinstall"
cc -o $CP.new $T/c.c && mv $CP.new $CP
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
echo "--- up never writes or trusts a file of the state folder through a link (#194)"
# #165 and #174 refuse a link at the state folders; these are the files in them. A link at a file
# up writes (the prompt, the kickoff, the launch script) would have up write wherever it points; a
# link at the claude copy would have every seat run whatever it points at. Each link points at a
# sentinel, which must come out byte for byte as it went in.
mkdir -p $T/state9/prompts $T/state9/launch
for f in prompts/x.md prompts/x.kickoff launch/x.sh; do
  printf 'sentinel for %s\n' $f > $T/sent9-${f##*/}; cp $T/sent9-${f##*/} $T/sent9-${f##*/}.want; ln -s $T/sent9-${f##*/} $T/state9/$f
done
fc=$(TEAM_STATE_DIR=$T/state9 TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?
for f in prompts/x.md prompts/x.kickoff launch/x.sh; do
  [ $rc = 0 ] && cmp -s $T/sent9-${f##*/} $T/sent9-${f##*/}.want && [ -f $T/state9/$f ] && [ ! -L $T/state9/$f ] && [ -s $T/state9/$f ] \
    && ok "up: a link at $f is replaced by the file up writes, and what it pointed at is untouched" || { bad "up wrote $f through a link (rc=$rc)"; ls -l $T/state9/$f; cat $T/sent9-${f##*/}; echo "$fc" | tail -2; }
done
TEAM_STATE_DIR=$T/state9 $S -c $T/tc.yaml down --yes x >/dev/null 2>&1
# The copy's folder is a real one (#174 checks that); the copy in it is a link to a runnable file.
cv=$(basename "$(dirname "$CP")")
printf '#!/bin/sh\necho sentinel claude\n' > $T/sent-claude; chmod +x $T/sent-claude; cp $T/sent-claude $T/sent-claude.want
mkdir -p $T/statea/bin/$cv && ln -s $T/sent-claude $T/statea/bin/$cv/claude
fc=$(TEAM_STATE_DIR=$T/statea TEAM_VIEW=0 $S -c $T/tc.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$fc" | grep -qF "$T/statea/bin/$cv/claude is a symlink" && ! tmux has-session -t '=tc-x' 2>/dev/null && cmp -s $T/sent-claude $T/sent-claude.want \
  && ok "up refuses a claude copy that is a link, naming it, and starts no seat" || { bad "a linked claude copy (rc=$rc)"; echo "$fc" | tail -2; }
TEAM_STATE_DIR=$T/statea $S -c $T/tc.yaml down --yes x >/dev/null 2>&1
e2e_end=claude-copy # the last line: test/e2e.sh checks that the file ran to here
