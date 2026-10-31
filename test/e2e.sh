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
T=$(mktemp -d "${TMPDIR:-/tmp}/team-e2e.XXXX"); T=$(cd "$T" && pwd); mkdir -p $T/bin $T/tmux $T/local
ROOT="Projects/_teamtest-$$"; VOL=${TEST_VOLUME:-}
unset TMUX; export TMUX_TMPDIR=$T/tmux TEAM_STATE_DIR=$T/state
pass=0; fail=0; ok(){ echo "PASS $1"; pass=$((pass+1)); }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
# throwaway repo with a "github" slug the origin URL contains
git init -q --bare $T/local/origin.git; git clone -q $T/local/origin.git $T/repo 2>/dev/null
(cd $T/repo && git commit -q --allow-empty -m init && git branch -M main && git push -q origin main)
# fake claude: a real binary named claude (the process check looks at the process name). It
# prints the file $FAKE_PROMPT if there is one (a stand-in for a permission prompt) and logs every
# byte it reads to $FAKE_KEYLOG. The tty is in line mode, so a byte arrives only with an Enter.
cat > $T/c.c <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(int n,char**v){printf("FAKE-CLAUDE");for(int i=1;i<n;i++)printf(" [%.50s]",v[i]);printf("\n");
char*p=getenv("FAKE_PROMPT"),*k=getenv("FAKE_KEYLOG");FILE*f=p?fopen(p,"r"):0,*kl=k?fopen(k,"a"):0;int c;
if(f){while((c=fgetc(f))!=EOF)putchar(c);fclose(f);}fflush(stdout);
while((c=getchar())!=EOF){putchar(c);fflush(stdout);if(kl){fputc(c,kl);fflush(kl);}}return 0;}
C
cc -o $T/bin/claude $T/c.c || { echo "no compiler"; exit 2; }
printf '#!/bin/sh\nshift\necho "$TEAM_ROLE $*" >> %s/args.log\nexport FAKE_KEYLOG=%s/keys-$TEAM_ROLE.log FAKE_PROMPT=%s/prompt-$TEAM_ROLE.txt\nexec %s/bin/claude "$@"\n' $T $T $T $T > $T/bin/wrap; chmod +x $T/bin/wrap
mkdir -p $T/proj
cat > $T/team.yaml <<Y
team: tt
repo: { path: $T/repo, github: local/origin.git, base: origin/main }
project: { name: TestBoard, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions:
  prefix: tt
  claude: { wrapper: $T/bin/wrap, permission_mode: bypassPermissions }
permissions:
  deny: ["Read(//**/.env)", "Bash(touch tt-deny*)"]
  ask: ["Bash(gh pr merge *)"]
  allow: ["Bash(npm test)"]
prompts: { common: $SRC/roles/common.md }
roles:
  em: { title: Manager, workdir: { type: project, path: $T/proj }, prompt_text: "em prompt" }
  w1: { title: Worker One, model: sonnet, effort: low, permission_mode: default, workdir: { type: worktree }, prompt_text: "w1 prompt",
        permissions: { deny: ["Bash(gh pr merge *)", "Read(//**/.env)"], allow: ["Bash(make *)"] } }
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
grep -qF "em --permission-mode bypassPermissions --settings $T/state/settings/em.json -n tt-em" $T/args.log && ok "em launched with the team mode, its settings file, no --model/--effort (inherit)" || { bad "em args"; cat $T/args.log; }
grep -qF "w1 --model sonnet --effort low --permission-mode default --settings $T/state/settings/w1.json -n tt-w1" $T/args.log && ok "w1 launched with its own mode (default) and its settings file" || { bad "w1 mode/settings args"; cat $T/args.log; }
grep -E "^(em|w1) " $T/args.log | grep -c -- "--effort" | grep -q '^1$' && ok "only w1 got --effort" || bad "only w1 got --effort"
echo "--- generated settings"
# The user's rules, in team-then-role order, without duplicates. Rules the launcher adds itself
# (Edit denies on its own files) are checked separately, so they are left out of these lists.
perms() { ruby -rjson -e 'p = JSON.parse(File.read(ARGV[0]))["permissions"] || {}; %w[deny ask allow].each { |k| l = (p[k] || []).reject { |r| r.start_with?("Edit(//", "Bash(git push ") }; puts "#{k}=#{l.join(" | ")}" }; puts "disable=#{p["disableBypassPermissionsMode"]}"' "$1" 2>&1; }
# rules <file> <deny|ask|allow>: one rule per line
rules() { ruby -rjson -e 'puts((JSON.parse(File.read(ARGV[0]))["permissions"] || {})[ARGV[1]] || [])' "$1" "$2"; }
want_em='deny=Read(//**/.env) | Bash(touch tt-deny*)
ask=Bash(gh pr merge *)
allow=Bash(npm test)
disable='
want_w1='deny=Read(//**/.env) | Bash(touch tt-deny*) | Bash(gh pr merge *)
ask=
allow=Bash(npm test) | Bash(make *)
disable=disable'
[ "$(perms $T/state/settings/em.json)" = "$want_em" ] && ok "em.json: the team rules only" || { bad "em.json rules"; perms $T/state/settings/em.json; }
[ "$(perms $T/state/settings/w1.json)" = "$want_w1" ] && ok "w1.json: team + role merged, duplicate dropped, team ask shadowed by the role deny dropped, bypass disabled for a non-bypass mode" || { bad "w1.json rules"; perms $T/state/settings/w1.json; }
[ "$(stat -f %Lp $T/state/settings/em.json)" = 444 ] && ok "settings file is read-only (0444)" || bad "settings file mode $(stat -f %Lp $T/state/settings/em.json)"
# Edit denies the launcher adds for files that change a seat's next start or its live rules. Paths
# are real paths (the temp folder is under a symlink on macOS).
RT=$(cd $T && pwd -P); RSRC=$(cd $SRC && pwd -P); RW1=$(cd $VOL/$ROOT/team-w1 && pwd -P); RHC=$(cd ~/.claude && pwd -P); RH=$(cd ~ && pwd -P)
missing=""
for p in "$RT/state/settings/**" "$RT/state/launch/**" "$RT/state/prompts/**" "$RT/state/messages.log" "$RT/team.yaml" \
  "$RSRC/roles/common.md" "$RSRC/factory.sh" "$RSRC/lib/**" "$RSRC/roles/**" "$RT/bin/wrap" \
  "$RT/repo/.claude/settings.json" "$RT/repo/.claude/settings.local.json" "$RT/repo/.claude/skills/**" "$RT/repo/.claude/agents/**" "$RT/repo/.claude/commands/**" \
  "$RW1/.claude/settings.json" "$RW1/.claude/settings.local.json" "$RHC/settings.json" "$RH/.claude.json" "$RHC/CLAUDE.md" \
  "$RHC/plugins/**" "$RHC/skills/**" "$RHC/agents/**" "$RHC/commands/**" "$RHC/hooks/**"; do
  rules $T/state/settings/w1.json deny | grep -qxF "Edit(/$p)" || missing="$missing $p"
done
[ -z "$missing" ] && ok "w1.json: Edit deny on every protected path" || { bad "protected paths missing:$missing"; rules $T/state/settings/w1.json deny; }
rules $T/state/settings/w1.json deny | grep -qE "state/notes|Edit\(//$RT/state/\*\*\)|Edit\(//$RHC/\*\*\)" && bad "protected paths are too wide (state notes, whole state dir or whole ~/.claude)" || ok "protected paths leave state/notes and the rest of ~/.claude writable"
# Claude Code puts the worktrees it makes (--worktree, subagents with isolation: worktree) under
# <repo>/.claude/worktrees/, so no deny may cover that folder.
rules $T/state/settings/w1.json deny | grep -E "^Edit\(/$RT/repo/\.claude/(\*\*|worktrees)" && bad "a deny covers <repo>/.claude/worktrees" || ok "no deny covers <repo>/.claude/worktrees (Claude Code's own worktrees stay editable)"
rules $T/state/settings/em.json deny | grep -qxF "Edit(/$RT/proj/.claude/settings.json)" && ok "em.json: protects em's own workdir settings" || bad "em.json: workdir settings deny"
esc=$(TEAM_STATE_DIR='/tmp/sf-e2e-no[such]*dir' ruby $SRC/lib/team_config.rb $T/team.yaml settings em | ruby -rjson -e 'puts JSON.parse(STDIN.read)["permissions"]["deny"]' | grep "sf-e2e-no")
echo "$esc" | grep -qxF 'Edit(//private/tmp/sf-e2e-no\[such\]\*dir/settings/**)' && ok "glob characters in a protected path are escaped" || { bad "glob escaping"; echo "$esc"; }
base_rules='Bash(git push * main)
Bash(git push * main *)
Bash(git push *:main)
Bash(git push *:main *)
Bash(git push *+main)
Bash(git push *+main *)
Bash(git push */main)
Bash(git push */main *)'
[ "$(rules $T/state/settings/em.json ask | grep '^Bash(git push ')" = "$base_rules" ] && ok "ask on any push to the base branch (main, from origin/main): the 8 patterns" || { bad "base-branch ask"; rules $T/state/settings/em.json ask; }
chk=$($S -c $T/team.yaml check 2>&1)
echo "$chk" | grep -qE "^em +Manager .* bypassPermissions " && echo "$chk" | grep -qE "^w1 +Worker One .* default " && ok "check: MODE column per role" || { bad "check MODE column"; echo "$chk"; }
sect() { echo "$chk" | sed -n "/^\[$1\]/,/^\[/p"; }
sect w1 | grep -qF "deny : Read(//**/.env), Bash(touch tt-deny*), Bash(gh pr merge *)" && ok "check: w1's merged deny list" || { bad "check w1 deny"; sect w1; }
sect em | grep -qF "allow rules have no effect in bypassPermissions" && ! sect w1 | grep -qF "no effect in bypassPermissions" && ok "check: bypass note on em only" || { bad "check bypass note"; sect em; }
echo "$chk" | grep -qF "add to" && ok "check: says the rules add to the user's and the repo's own settings" || bad "check: add-to note"
# Each start rewrites the file: a stale or edited one is replaced, not reused.
chmod u+w $T/state/settings/em.json && echo '{"permissions":{}}' > $T/state/settings/em.json && chmod 444 $T/state/settings/em.json
$S -c $T/team.yaml down --yes em >/dev/null; TEAM_VIEW=0 $S -c $T/team.yaml up --no-view em >/dev/null 2>&1
[ "$(perms $T/state/settings/em.json)" = "$want_em" ] && [ "$(stat -f %Lp $T/state/settings/em.json)" = 444 ] && ok "up rewrites a stale settings file" || { bad "up rewrites settings"; perms $T/state/settings/em.json; }
echo "--- say"
TEAM_ROLE=em $S -c $T/team.yaml say w1 "hello w1 from em" && sleep 1
tmux capture-pane -p -t '=tt-w1:' | grep -q "from em\] hello w1" && ok "message arrived in w1's pane" || bad "message arrived"
grep -q "from em\] hello w1" $T/keys-w1.log 2>/dev/null && ok "the stand-in logged the submitted message (the key log works)" || bad "key log of w1"
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
echo "--- say refuses a seat at a permission prompt"
# pp shows a permission prompt at the bottom of its screen and pm an AskUserQuestion menu: both
# texts are copied from Claude Code 2.1.316 (captured 2026-10-30), so a later CLI that words them
# differently shows up as a mismatch with these. pq showed the prompt once, but it has scrolled up
# out of the bottom lines, so pq takes messages.
cat > $T/tp.yaml <<Y
team: tp
repo: { path: $T/repo, github: local/origin.git }
project: { name: TestBoard, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: tp, claude: { wrapper: $T/bin/wrap } }
roles:
  pp: { title: Prompted, workdir: { type: project, path: $T/proj }, prompt_text: "pp" }
  pm: { title: Menu, workdir: { type: project, path: $T/proj }, prompt_text: "pm" }
  pq: { title: Scrolled, workdir: { type: project, path: $T/proj }, prompt_text: "pq" }
Y
fake_prompt='────────────────────────────────────────────────────────────
 Bash command
 Create the SF_ASK_MARKER file
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 touch SF_ASK_MARKER
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 │ Permission rule Bash(touch SF_ASK_MARKER*) requires confirmation for this command.
 /permissions to update rules
 Do you want to proceed?
 ❯ 1. Yes
   2. No
 Esc to cancel · Tab to amend'
printf '%s\n' "$fake_prompt" > $T/prompt-pp.txt
cat > $T/prompt-pm.txt <<'M'
────────────────────────────────────────────────────────────
 ☐ Color
Which color do you prefer, red or blue?
❯ 1. Red
     Choose red.
  2. Blue
     Choose blue.
  3. Type something.
────────────────────────────────────────────────────────────
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
M
{ printf '%s\n' "$fake_prompt"; for i in $(seq 1 25); do echo "later output line $i"; done; } > $T/prompt-pq.txt
TEAM_VIEW=0 $S -c $T/tp.yaml up --no-view >/dev/null 2>&1; sleep 2
sp=$(TEAM_ROLE=em $S -c $T/tp.yaml say pp "routine message" 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$sp" | grep -q "permission prompt" && ok "say to a seat at a permission prompt fails and says why" || { bad "say at a permission prompt (rc=$rc)"; echo "$sp"; }
sleep 1
[ ! -s $T/keys-pp.log ] && ok "the seat at the prompt received no Enter" || { bad "the seat at the prompt received keys"; od -c $T/keys-pp.log | head -3; }
tail -1 $T/state/messages.log | grep -q "	pp	NOT-DELIVERED	routine message" && ok "log records the refused message as NOT-DELIVERED" || { bad "log NOT-DELIVERED"; tail -1 $T/state/messages.log; }
TEAM_ROLE=em $S -c $T/tp.yaml say pm "routine message" >/dev/null 2>&1 && bad "say to a seat at a question menu was delivered" || { sleep 1; [ ! -s $T/keys-pm.log ] && ok "say to a seat at a question menu fails, and the seat received no Enter" || bad "the seat at the menu received keys"; }
TEAM_ROLE=em $S -c $T/tp.yaml say pq "after the prompt scrolled away" >/dev/null 2>&1 && sleep 1 && grep -q "after the prompt scrolled away" $T/keys-pq.log 2>/dev/null && ok "prompt text above the bottom of the screen does not block delivery" || bad "scrolled-away prompt blocked delivery"
$S -c $T/tp.yaml down --yes >/dev/null 2>&1
echo "--- permission validation (check must refuse each file)"
# A minimal valid team file; $1 is the sessions.claude body, $2 extra top-level lines, $3 extra keys for role em.
mk() {
  cat > $T/v.yaml <<Y
team: tv
repo: { path: $T/repo, github: local/origin.git }
project: { name: B, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: tv, claude: { ${1:-} } }
${2:-}
roles:
  em: { title: M, workdir: { type: project, path: $T/proj }, prompt_text: "p" ${3:-} }
Y
}
# reject <what> <expected message> <mk args...>
reject() {
  local what=$1 msg=$2 out rc; shift 2; mk "$@"
  out=$($S -c $T/v.yaml check 2>&1); rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$msg"; then ok "rejects $what"; else bad "rejects $what (rc=$rc)"; echo "$out" | tail -2; fi
}
# accept <what> <mk args...>
accept() {
  local what=$1 out; shift; mk "$@"
  if out=$($S -c $T/v.yaml check 2>&1); then ok "accepts $what"; else bad "accepts $what"; echo "$out" | tail -2; fi
}
rule() { echo "permissions: { $1: [$2] }"; }
reject "an unknown mode" "permission_mode must be one of" "permission_mode: yolo"
reject "an unknown role mode" "permission_mode must be one of" "" "" ", permission_mode: Auto"
reject "a mode with --dangerously-skip-permissions in args" "--dangerously-skip-permissions is reserved" "permission_mode: auto, args: [--dangerously-skip-permissions]"
reject "a role mode with --dangerously-skip-permissions in args" "--dangerously-skip-permissions is reserved" "args: [--dangerously-skip-permissions]" "" ", permission_mode: plan"
reject "a mode with --permission-mode=plan in args" "--permission-mode is reserved" "permission_mode: auto, args: [--permission-mode=plan]"
reject "a mode with --allow-dangerously-skip-permissions in args" "--allow-dangerously-skip-permissions is reserved" "permission_mode: auto, args: [--allow-dangerously-skip-permissions]"
reject "--settings in args" "--settings is reserved" "args: [--settings, x.json]"
reject "--setting-sources in args" "--setting-sources is reserved" "args: [--setting-sources=project]"
reject "--permission-prompt-tool in args" "--permission-prompt-tool is reserved" "args: [--permission-prompt-tool, mcp__x__y]"
reject "a lowercase tool name" "must start with an uppercase letter" "" "$(rule deny '"bash(ls)"')"
reject "an unclosed specifier" "must be Tool or Tool(specifier)" "" "$(rule deny '"Bash(ls"')"
reject "an empty specifier" "empty specifier" "" "$(rule deny '"Bash()"')"
reject "surrounding whitespace" "leading or trailing whitespace" "" "$(rule deny '"Bash(ls) "')"
reject "an empty rule" "must be a non-empty string" "" "$(rule deny '""')"
reject "a single-slash Read path" "single leading /" "" "$(rule deny '"Read(/secrets/**)"')"
reject "a single-slash Edit path in a role" "single leading /" "" "" ", $(rule ask '"Edit(/src/**)"')"
reject "a Write path rule" "never matches" "" "$(rule deny '"Write(x.txt)"')"
reject "a MultiEdit path rule" "never matches" "" "$(rule deny '"MultiEdit(x)"')"
reject "a Glob path rule" "never matches" "" "$(rule deny '"Glob(src/**)"')"
reject "an mcp__ rule with parentheses" "mcp__ rules cannot have" "" "$(rule deny '"mcp__s__t(x)"')"
reject "a tool glob in allow" "tool-name glob" "" "$(rule allow '"*"')"
reject "a server glob in an mcp allow" "tool-name glob" "" "$(rule allow '"mcp__*"')"
reject "Bash(command:...)" "main input field" "" "$(rule deny '"Bash(command:rm *)"')"
reject "Read(file_path : ...)" "main input field" "" "$(rule deny '"Read(file_path : x)"')"
reject "WebFetch(url:...)" "main input field" "" "$(rule deny '"WebFetch(url:https://x.test)"')"
reject "a :* that is not at the end" ":* is only a wildcard at the end" "" "$(rule deny '"Bash(git:* push)"')"
reject "a role ask shadowed by a team deny" "team deny" "" "$(rule deny '"Bash(rm *)"')" ", $(rule ask '"Bash(rm *)"')"
reject "a role allow shadowed by a team ask" "roles.em allow" "" "$(rule ask '"Bash(rm *)"')" ", $(rule allow '"Bash(rm *)"')"
reject "the same rule in deny and allow of one source" "team allow" "" 'permissions: { deny: ["Bash(rm *)"], allow: ["Bash(rm *)"] }'
reject "an unknown key under permissions" "unknown key(s) under permissions: denny" "" "$(rule denny '"Bash"')"
reject "a non-list rule set" "must be a list" "" 'permissions: { deny: "Bash" }'
accept "parentheses inside a specifier" "" "$(rule deny '"Edit(./Finance (2024)/**)"')"
accept "a role deny over a team ask (a tightening)" "" "$(rule ask '"Bash(rm *)"')" ", $(rule deny '"Bash(rm *)"')"
accept "a glob tool name in deny" "" "$(rule deny '"*", "mcp__*"')"
accept "an mcp server-scoped glob in allow" "" "$(rule allow '"mcp__puppeteer__*"')"
accept "a parameter rule on a non-main field" "" "$(rule deny '"Agent(model:opus)", "Bash(command -v *)", "Bash(ls:*)"')"
accept "the manual alias" "permission_mode: manual"
# The wrapper claude runs through is protected like factory.sh: a file, or its whole .app bundle.
mk; ws=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em)
echo "$ws" | grep -q "wrap\|\.app" && bad "no wrapper configured, but a wrapper deny was added" || ok "no wrapper configured: no wrapper deny"
mk "wrapper: $T/Wrap.app/Contents/MacOS/Wrap"; ws=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em)
echo "$ws" | grep -qF "\"Edit(/$RT/Wrap.app/**)\"" && ok "a wrapper inside an .app: Edit deny on the whole bundle" || { bad "wrapper .app deny"; echo "$ws" | grep -i wrap; }
mk "permission_mode: dontAsk" "$(rule ask '"Bash(rm *)"')"
$S -c $T/v.yaml check 2>&1 | grep -qF "ask rules are refused in dontAsk" && ok "check: ask-becomes-deny note under dontAsk" || bad "check: dontAsk note"
mk; sed -i '' 's#github: local/origin.git }#github: local/origin.git, base: main }#' $T/v.yaml
nb=$($S -c $T/v.yaml check 2>&1); TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em | grep -q "git push" && bad "base without a remote still produced push rules" || { echo "$nb" | grep -qF "no base-branch push rules" && ok "repo.base without a remote: no push rules, and check says so" || { bad "check: no base-branch note"; echo "$nb" | tail -3; }; }
mk "args: [--dangerously-skip-permissions]"
lg=$($S -c $T/v.yaml check 2>&1) && echo "$lg" | grep -qE "^em .* bypassPermissions \(args\)" && ok "legacy: --dangerously-skip-permissions in args with no mode still loads; check shows bypassPermissions (args)" || { bad "legacy args file"; echo "$lg" | tail -4; }
echo "--- cleanup"
$S -c $T/team.yaml down --yes >/dev/null 2>&1; tmux kill-server 2>/dev/null
for w in team-w1 team-w2; do git -C $T/repo worktree remove --force $VOL/$ROOT/$w 2>/dev/null; git -C $T/repo worktree remove --force $T/repo/.claude/worktrees/$w 2>/dev/null; done
rmdir $VOL/$ROOT 2>/dev/null; [ ! -e $VOL/$ROOT ] && ok "test folder removed from the volume" || bad "test folder removed from the volume ($(ls -A $VOL/$ROOT 2>&1 | head -3))"
rm -rf "$T"
echo "RESULT pass=$pass fail=$fail"
