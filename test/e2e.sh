#!/usr/bin/env bash
# End-to-end test of factory.sh in isolation: a private tmux server, a throwaway git repo,
# and a stand-in `claude` compiled as a real binary named claude (the launcher's process check
# looks at the process name). Worktrees go to a scratch folder on a REAL mounted volume
# (TEST_VOLUME, required, e.g. /Volumes/MyDrive) so the mount check is exercised for real; the
# folder is removed at the end. Needs: tmux, ruby, a C compiler, git.
set -u
[ -n "${TEST_VOLUME:-}" ] || { echo "set TEST_VOLUME to a mounted volume that can be written to, e.g. /Volumes/MyDrive" >&2; exit 64; }
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
S=$SRC/factory.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/team-e2e.XXXX"); mkdir -p $T/bin $T/tmux $T/local
ROOT="Projects/_teamtest-$$"; VOL=${TEST_VOLUME:-}
unset TMUX; export TMUX_TMPDIR=$T/tmux TEAM_STATE_DIR=$T/state
pass=0; fail=0; ok(){ echo "PASS $1"; pass=$((pass+1)); }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
# throwaway repo with a "github" slug the origin URL contains
git init -q --bare $T/local/origin.git; git clone -q $T/local/origin.git $T/repo 2>/dev/null
(cd $T/repo && git commit -q --allow-empty -m init && git branch -M main && git push -q origin main)
# fake claude: a real binary named claude (the process check looks at the process name)
cat > $T/c.c <<'C'
#include <stdio.h>
int main(int n,char**v){printf("FAKE-CLAUDE");for(int i=1;i<n;i++)printf(" [%.50s]",v[i]);printf("\n");fflush(stdout);int c;while((c=getchar())!=EOF)putchar(c);return 0;}
C
cc -o $T/bin/claude $T/c.c || { echo "no compiler"; exit 2; }
printf '#!/bin/sh\nshift\necho "$TEAM_ROLE $*" >> %s/args.log\nexec %s/bin/claude "$@"\n' $T $T > $T/bin/wrap; chmod +x $T/bin/wrap
mkdir -p $T/proj
cat > $T/team.yaml <<Y
team: tt
repo: { path: $T/repo, github: local/origin.git, base: origin/main }
project: { name: TestBoard, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions:
  prefix: tt
  claude: { wrapper: $T/bin/wrap, args: [--dangerously-skip-permissions] }
prompts: { common: $SRC/roles/common.md }
roles:
  em: { title: Manager, workdir: { type: project, path: $T/proj }, prompt_text: "em prompt" }
  w1: { title: Worker One, model: sonnet, effort: low, workdir: { type: worktree }, prompt_text: "w1 prompt" }
  w2: { title: Worker Two, workdir: { type: worktree }, prompt_text: "w2 prompt" }
Y
export PATH=$T/bin:$PATH
# legacy worktree for w2, internal disk
git -C $T/repo worktree add -q --detach $T/repo/.claude/worktrees/team-w2 origin/main
echo "--- up (w2 has a legacy worktree, expect it to be refused)"
out=$($S -c $T/team.yaml up 2>&1); echo "$out" | grep -E "start|error|ATTENTION" | cut -c1-170
echo "$out" | grep -q "start  w1" && ok "w1 started" || bad "w1 started"
echo "$out" | grep -q "migrate w2" && ok "w2 refused with migrate hint" || bad "w2 refused with migrate hint"
case "$(git -C $T/repo worktree list)" in *"$VOL/$ROOT/team-w1"*) ok "w1 worktree is on the volume";; *) bad "w1 worktree is on the volume";; esac
sleep 3
grep -q "^w1 .*--model sonnet --effort low" $T/args.log && ok "w1 launched with --model sonnet --effort low" || { bad "w1 args"; cat $T/args.log; }
grep -q "^em --dangerously-skip-permissions -n tt-em" $T/args.log && ok "em launched with no --model/--effort (inherit)" || { bad "em args"; cat $T/args.log; }
grep -E "^(em|w1) " $T/args.log | grep -c -- "--effort" | grep -q '^1$' && ok "only w1 got --effort" || bad "only w1 got --effort"
echo "--- say"
TEAM_ROLE=em $S -c $T/team.yaml say w1 "hello w1 from em" && sleep 1
tmux capture-pane -p -t '=tt-w1:' | grep -q "from em\] hello w1" && ok "message arrived in w1's pane" || bad "message arrived"
tmux show-options -t '=tt-w1:' set-titles-string | grep -q 'set-titles-string "w1 | Worker One | tt-w1"' && ok "pane title set at startup: role | title | session" || bad "pane title at startup"
tmux set-option -t '=tt-w1:' set-titles-string "stale" && $S -c $T/team.yaml titles >/dev/null && tmux show-options -t '=tt-w1:' set-titles-string | grep -q '"w1 | Worker One | tt-w1"' && ok "titles command repairs a changed title" || bad "titles command"
echo "--- migrate then up w2"
$S -c $T/team.yaml migrate w2 2>&1 | grep -E "moved|REFUSE|skip" | cut -c1-150
$S -c $T/team.yaml up w2 2>&1 | grep -E "start|error" | cut -c1-150
case "$(git -C $T/repo worktree list)" in *"$VOL/$ROOT/team-w2"*) ok "w2 recreated on the volume";; *) bad "w2 recreated on the volume";; esac
[ ! -d $T/repo/.claude/worktrees/team-w2 ] && ok "legacy w2 folder gone" || bad "legacy w2 folder gone"
echo "--- status"; $S -c $T/team.yaml status | cut -c1-150
echo "--- dirty legacy is refused"
$S -c $T/team.yaml down --yes w1 >/dev/null; $S -c $T/team.yaml migrate w1 2>&1 | grep -c "removed 0" | grep -q 1 && true
rm -rf $VOL/$ROOT/team-w1.tmp 2>/dev/null
git -C $T/repo worktree remove --force $VOL/$ROOT/team-w1 && git -C $T/repo worktree add -q --detach $T/repo/.claude/worktrees/team-w1 origin/main && echo scratch > $T/repo/.claude/worktrees/team-w1/untracked.txt
mig=$($S -c $T/team.yaml migrate w1 2>&1); echo "$mig" | grep -E "REFUSE|moved" | cut -c1-140
echo "$mig" | grep -q "REFUSE w1" && [ -f $T/repo/.claude/worktrees/team-w1/untracked.txt ] && ok "dirty worktree refused and untouched" || bad "dirty worktree refused and untouched"
echo "--- unmounted volume"
sed "s#volume: $VOL#volume: /Volumes/NotMounted#" $T/team.yaml > $T/team2.yaml
$S -c $T/team.yaml down --yes w2 >/dev/null
echo '  w3: { title: Worker Three, workdir: { type: worktree }, prompt_text: "w3 prompt" }' >> $T/team2.yaml
rm_out=$($S -c $T/team2.yaml up w3 2>&1); echo "$rm_out" | grep -E "error|skip" | cut -c1-150 | head -2
echo "$rm_out" | grep -q "is not mounted; refusing" && ok "unmounted volume refused with a clear error" || { bad "unmounted volume refused"; echo "<<<$rm_out>>>"; }
[ ! -e /Volumes/NotMounted ] && ok "nothing created at the missing volume" || bad "nothing created at the missing volume"
echo "--- iTerm view layout (generated script only; iTerm itself is not driven)"
v3=$($S -c $T/team.yaml view --print)
echo "$v3" | grep -n 'write text' | head -1 | grep -q "tt-em" && ok "view: primary seat (em) is first" || bad "view: primary seat first"
[ "$(echo "$v3" | grep -c 'write text')" = 3 ] && ok "view: one pane per seat (3)" || bad "view: pane count"
[ "$(echo "$v3" | grep -c 'split vertically')" = 2 ] && [ "$(echo "$v3" | grep -c 'split horizontally')" = 0 ] && ok "view: em | w1 | w2 uses 2 vertical splits, no row stack" || bad "view: 3-seat splits"
for k in w3 w4 w5; do echo "  $k: { title: Worker $k, workdir: { type: worktree }, prompt_text: \"$k\" }" >> $T/team.yaml; done
v6=$($S -c $T/team.yaml view --print)
[ "$(echo "$v6" | grep -c 'write text')" = 6 ] && ok "view: 6 seats, 6 panes" || bad "view: 6-seat pane count"
[ "$(echo "$v6" | grep -c 'split horizontally')" = 2 ] && ok "view: 5 other seats make 3 rows (2 row splits)" || bad "view: row splits"
[ "$(echo "$v6" | grep -c 'split vertically')" = 3 ] && ok "view: 1 left/right split + 2 column splits (odd last row full width)" || bad "view: column splits"
echo "$v6" | grep -q "tell s0 to write text .*tt-em" && ok "view: em is in the left pane (s0)" || bad "view: em left"
sed 's#^storage:#display: { primary: w2 }\nstorage:#' $T/team.yaml > $T/team3.yaml
$S -c $T/team3.yaml view --print | grep "tell s0 to write text" | grep -q "tt-w2" && ok "view: display.primary moves w2 to the left" || bad "view: display.primary"
sed 's#^storage:#display: { primary: nobody }\nstorage:#' $T/team.yaml > $T/team4.yaml
$S -c $T/team4.yaml check 2>&1 | grep -q "not a role id" && ok "view: unknown display.primary rejected" || bad "view: unknown primary"
echo "--- cleanup"
$S -c $T/team.yaml down --yes >/dev/null 2>&1; tmux kill-server 2>/dev/null
for w in team-w1 team-w2; do git -C $T/repo worktree remove --force $VOL/$ROOT/$w 2>/dev/null; git -C $T/repo worktree remove --force $T/repo/.claude/worktrees/$w 2>/dev/null; done
rmdir $VOL/$ROOT 2>/dev/null; [ ! -e $VOL/$ROOT ] && ok "test folder removed from the volume" || bad "test folder removed from the volume ($(ls -A $VOL/$ROOT 2>&1 | head -3))"
rm -rf "$T"
echo "RESULT pass=$pass fail=$fail"
