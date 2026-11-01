# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# migrate, status, a dirty legacy worktree, an unmounted volume. Stops w2 at the end.
echo "--- migrate then up w2"
$S -c $T/team.yaml migrate w2 2>&1 | grep -E "moved|REFUSE|skip" | cut -c1-150
$S -c $T/team.yaml up --no-view w2 2>&1 | grep -E "start|error" | cut -c1-150
case "$(git -C $T/repo worktree list)" in *"$VOL/$ROOT/team-w2"*) ok "w2 recreated on the volume";; *) bad "w2 recreated on the volume";; esac
[ ! -d $T/repo/.claude/worktrees/team-w2 ] && ok "legacy w2 folder gone" || bad "legacy w2 folder gone"
[ "$(grep -c '^w2 ' $T/boot.log)" = 1 ] && [ "$(grep -c '^w1 ' $T/boot.log)" = 1 ] && ok "repo.bootstrap runs once per new worktree: for w2 now, not again for w1" || { bad "repo.bootstrap runs"; cat $T/boot.log; }
# w2 (auto_memory: true) starts only now: its launch script and environment leave auto memory alone.
[ -f $T/state/launch/w2.sh ] && ! grep -q "export CLAUDE_CODE_DISABLE_AUTO_MEMORY" $T/state/launch/w2.sh && grep -qx "unset CLAUDE_CODE_DISABLE_AUTO_MEMORY" $T/state/launch/w2.sh && grep -qx "w2 CLAUDE_CODE_DISABLE_AUTO_MEMORY=unset" $T/env.log && ok "auto memory: w2 (auto_memory: true) runs without the variable: its launch script unsets it, whatever the tmux server holds" || { bad "auto memory: w2 launch"; grep AUTO_MEMORY $T/env.log; grep -H AUTO_MEMORY $T/state/launch/w2.sh 2>&1; }
echo "--- status"; $S -c $T/team.yaml status | cut -c1-150
echo "--- dirty legacy is refused"
$S -c $T/team.yaml down --yes w1 >/dev/null; $S -c $T/team.yaml migrate w1 2>&1 | grep -c "removed 0" | grep -q 1 && true
rm -rf $VOL/$ROOT/team-w1.tmp 2>/dev/null
git -C $T/repo worktree remove --force $VOL/$ROOT/team-w1 && git -C $T/repo worktree add -q --detach $T/repo/.claude/worktrees/team-w1 origin/main && echo scratch > $T/repo/.claude/worktrees/team-w1/untracked.txt
mig=$($S -c $T/team.yaml migrate w1 2>&1); echo "$mig" | grep -E "REFUSE|moved" | cut -c1-140
echo "$mig" | grep -q "REFUSE w1" && [ -f $T/repo/.claude/worktrees/team-w1/untracked.txt ] && ok "dirty worktree refused and untouched" || bad "dirty worktree refused and untouched"
# A worktree that a running process works in is never removed (#121), whatever tmux server migrate
# reaches. w1 is down here, so `alive` sees no seat, as a copy of the team file on another server
# would see a real one. A stand-in "running seat" (a process whose working folder is inside the
# worktree) must keep it whole, git-ignored files included (.env.local and conf/ are excluded).
LW=$T/repo/.claude/worktrees/team-w1
rm $LW/untracked.txt && mkdir -p $LW/conf && echo "SEAT=1" > $LW/.env.local && echo '{"seat":1}' > $LW/conf/local.json
[ -z "$(git -C $LW status --porcelain)" ] || bad "test setup: the legacy w1 worktree is not clean"
(cd $LW/conf && exec sleep 600) & seatpid=$!
sleep 1
tree() { (cd $LW 2>/dev/null && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done); }
t0=$(tree)
mig=$($S -c $T/team.yaml migrate w1 2>&1)
[ -d $LW ] && [ -n "$t0" ] && [ "$(tree)" = "$t0" ] && echo "$t0" | grep -qF ".env.local" && echo "$mig" | grep -qE "REFUSE w1: .*/worktrees/team-w1 is the working folder of a running process" && echo "$mig" | grep -qF "removed 0 worktree(s)" \
  && ok "migrate keeps a clean worktree that a running process works in (its folder, ignored files and all, byte-identical)" || { bad "migrate removed or changed a worktree in use"; echo "$mig" | head -4; }
kill $seatpid 2>/dev/null; wait $seatpid 2>/dev/null
mig=$($S -c $T/team.yaml migrate w1 2>&1)
[ ! -e $LW ] && echo "$mig" | grep -qE "moved  w1: removed .*/worktrees/team-w1;" && ok "the same worktree, idle once the process is gone, is migrated" || { bad "idle worktree not migrated"; echo "$mig" | head -4; }
# A backslash in the path must not hide the process working there: lsof prints it escaped, so the
# path cannot be matched, and migrate refuses the worktree rather than guess.
BW="$T/back\\tslash/team-w1"; mkdir -p "$T/back\\tslash" && git -C $T/repo worktree add -q --detach "$BW" origin/main
(cd "$BW" && exec sleep 600) & seatpid=$!
sleep 1
mig=$($S -c $T/team.yaml migrate w1 2>&1)
[ -d "$BW" ] && echo "$mig" | grep -qF 'tslash/team-w1: lsof escapes characters in its path' && echo "$mig" | grep -qF "removed 0 worktree(s)" && ok "migrate keeps a worktree in use whose path has a backslash in it (refused: lsof escapes it)" || { bad "worktree in use with a backslash in its path"; echo "$mig" | head -4; }
kill $seatpid 2>/dev/null; wait $seatpid 2>/dev/null
git -C $T/repo worktree remove --force "$BW" 2>/dev/null
# A newline in a worktree's path (#134): read line by line, "$T/nl/a/team-w1<newline>b/team-w1" is
# two paths, the first a truncated one named like w1's worktree. migrate must handle it under its
# full path (lsof would print the newline escaped, so it is refused) and show it escaped, on one line.
# git prints the physical path ($T may sit under a symlink, as /var does on macOS), so NE uses it.
# Every line that names the folder must name all of it: none may show the truncated path.
NW="$T/nl/a/team-w1"$'\n'"b/team-w1"; NE="$(cd "$T" && pwd -P)/nl/a/team-w1\\nb/team-w1"
# The truncated path is made a real folder too, so code that misread the list would get past its -d
# check and act on it, the issue's own case, not only report it "registered but missing".
mkdir -p "$T/nl/a/team-w1"$'\n'"b" "$T/nl/a/team-w1" && git -C $T/repo worktree add -q --detach "$NW" origin/main
mig=$($S -c $T/team.yaml migrate w1 2>&1)
[ -d "$NW" ] && echo "$mig" | grep -qF "REFUSE w1: cannot tell whether a running process works in $NE: lsof escapes" && echo "$mig" | grep -qxF "  $NE" &&
  ! echo "$mig" | grep -F "/nl/a/team-w1" | grep -qvF '/nl/a/team-w1\nb/team-w1' && ! echo "$mig" | grep -qxF "  b/team-w1" && echo "$mig" | grep -qF "removed 0 worktree(s)" &&
  ok "migrate handles a worktree with a newline in its path under its full path (refused), and lists it escaped on one line" || { bad "worktree with a newline in its path"; echo "$mig"; }
git -C $T/repo worktree remove --force "$NW" 2>/dev/null
rmdir "$T/nl/a/team-w1" 2>/dev/null
# A git that cannot list with -z must stop migrate and up (#134, tl's review). The list is read
# through a process substitution, whose exit status bash drops, so without the check it reads as "no
# other worktrees": migrate reports "removed 0" and up skips #121's legacy refusal. The stand-in fails
# only on `worktree list ... -z`, as a git older than 2.36 does, and passes every other call through.
mkdir -p $T/oldgit && cat > $T/oldgit/git <<G
#!/bin/sh
case " \$* " in *" worktree list "*" -z "*) echo "error: unknown switch 'z'" >&2; exit 129 ;; esac
exec $(command -v git) "\$@"
G
chmod +x $T/oldgit/git
og=$(PATH=$T/oldgit:$PATH $S -c $T/team.yaml migrate w1 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$og" | grep -qF "needs git 2.36 or later" && ! echo "$og" | grep -qF "removed 0" &&
  ok "migrate stops when git cannot list the worktrees with -z, instead of reporting nothing to do" || { bad "migrate with a git that cannot list with -z (rc=$rc)"; echo "$og"; }
cp $T/team.yaml $T/team9.yaml && echo '  w9: { title: Worker Nine, workdir: { type: worktree }, prompt_text: "w9 prompt" }' >> $T/team9.yaml
git -C $T/repo worktree add -q --detach $T/legacy9/team-w9 origin/main
og=$(PATH=$T/oldgit:$PATH $S -c $T/team9.yaml up --no-view w9 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$og" | grep -qF "needs git 2.36 or later" && [ ! -e $VOL/$ROOT/team-w9 ] && ! tmux has-session -t '=tt-w9' 2>/dev/null &&
  ok "up stops when git cannot list the worktrees with -z, so the legacy-worktree refusal is never skipped (no worktree made, no seat started)" || { bad "up with a git that cannot list with -z (rc=$rc)"; echo "$og"; }
tmux kill-session -t '=tt-w9' 2>/dev/null; git -C $T/repo worktree remove --force $VOL/$ROOT/team-w9 2>/dev/null; git -C $T/repo worktree remove --force $T/legacy9/team-w9 2>/dev/null
# A worktree's branch name is shown escaped too (sec's review): git refuses ESC and a newline in a ref
# name but takes a bidi override (U+202E), which would reorder the line on a terminal.
BR="bidi"$'\xe2\x80\xae'"txt"; git -C $T/repo worktree add -q -b "$BR" $T/bidi/team-w1 origin/main
mig=$($S -c $T/team.yaml migrate w1 2>&1)
[ -d $T/bidi/team-w1 ] && echo "$mig" | grep -qF "has branch 'bidi\xE2\x80\xAEtxt' checked out" && ! echo "$mig" | grep -qF "$BR" &&
  ok "migrate shows a worktree's branch name escaped (a bidi override), and keeps the worktree" || { bad "branch name with a bidi override"; echo "$mig"; }
git -C $T/repo worktree remove --force $T/bidi/team-w1 2>/dev/null; git -C $T/repo branch -q -D "$BR" 2>/dev/null
echo "--- unmounted volume"
sed "s#volume: $VOL#volume: /Volumes/NotMounted#" $T/team.yaml > $T/team2.yaml
$S -c $T/team.yaml down --yes w2 >/dev/null
echo '  w3: { title: Worker Three, workdir: { type: worktree }, prompt_text: "w3 prompt" }' >> $T/team2.yaml
rm_out=$($S -c $T/team2.yaml up --no-view w3 2>&1); echo "$rm_out" | grep -E "error|skip" | cut -c1-150 | head -2
echo "$rm_out" | grep -q "is not mounted; refusing" && ok "unmounted volume refused with a clear error" || { bad "unmounted volume refused"; echo "<<<$rm_out>>>"; }
[ ! -e /Volumes/NotMounted ] && ok "nothing created at the missing volume" || bad "nothing created at the missing volume"
e2e_end=worktrees # the last line: test/e2e.sh checks that the file ran to here
