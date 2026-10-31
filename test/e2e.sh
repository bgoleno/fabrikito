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
# Start from a clean environment. Run from a seat, this shell inherits what the seat's launcher
# and claude set there (DISABLE_AUTOUPDATER, TEAM_*, CLAUDE* including CLAUDE_CONFIG_DIR, TMUX*), and the test's tmux server
# and everything it starts would inherit it in turn: the leak check on DISABLE_AUTOUPDATER below
# would fail only when run from a seat, and a stand-in seat could reach the real seat's tmux or
# messaging socket (#75). This is the one list of what is cleared; add any new launcher variable here.
# It runs before anything below exports a TEAM_* variable (TEAM_VIEW=0), or it would clear it.
for v in $(compgen -e); do case $v in DISABLE_AUTOUPDATER|TEAM_*|CLAUDE*|TMUX*) unset "$v" ;; esac; done
export TMUX_TMPDIR=$T/tmux TEAM_STATE_DIR=$T/state
# No run may drive iTerm (#93). A stand-in osascript first on PATH records every call and does
# nothing, and the run fails at the end if it was called: `up` opens a real iTerm window unless told
# not to, every run left its windows on the user's screen, and enough of them used up every pty on
# the machine, so tmux could no longer start the test's own seats. The view is off for the whole run
# (TEAM_VIEW=0), and every up says --no-view too, so dropping either one still opens no window.
printf '#!/bin/sh\necho "osascript $*" >> %s/osascript.log\nexit 1\n' "$T" > $T/bin/osascript; chmod +x $T/bin/osascript
export PATH=$T/bin:$PATH TEAM_VIEW=0
# Stopped early (a gate timeout kills this test's process group, a setup step exits, set -u trips):
# stop the private tmux server, which has left that group, and remove what the test made, as the
# cleanup at the end does. Not every assertion ran, so the exit status is never 0. The exit code is
# what a gate reads (repo.gate, lib/stop_gate.sh): only a run that reaches the end with fail=0 is 0.
finished=
on_exit() {
  local rc=$?
  [ -n "$finished" ] && return
  tmux kill-server 2>/dev/null
  [ -n "${LIVE_D:-}" ] && $SRC/test/live-env.sh down "$LIVE_D" 2>/dev/null
  for w in "$VOL/$ROOT"/*; do [ -d "$w" ] && git -C $T/repo worktree remove --force "$w" 2>/dev/null; done
  rmdir "$VOL/$ROOT" 2>/dev/null; rm -rf "$T"
  echo "ABORTED before the end (exit $rc): pass=${pass:-0} fail=${fail:-0}" >&2
  [ "$rc" -eq 0 ] && rc=1; exit "$rc"
}
trap on_exit EXIT
trap 'exit 143' TERM INT
pass=0; fail=0; ok(){ echo "PASS $1"; pass=$((pass+1)); }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
# The area files (#70) are sourced in the order of AREAS, in this shell, so they share the setup above,
# the count and the exit trap. Each holds a run of sections and relies on the state the areas before it
# leave. A file not listed here would never run, and sourcing a file with a syntax error runs part of it
# and carries on, so either one would lower the count without a failure: both stop the run here.
AREAS="launch settings say say-sender worktrees view delivery config skills warnings gate hooks claude-copy prompts live"
E2E_DIR=$SRC/test/e2e
for e2e_f in "$E2E_DIR"/*.sh; do e2e_a=${e2e_f##*/}; e2e_a=${e2e_a%.sh}; [ "$e2e_a" = lib ] && continue
  case " $AREAS " in *" $e2e_a "*) ;; *) echo "test/e2e/$e2e_a.sh is not in AREAS in test/e2e.sh: add it there, or it never runs" >&2; exit 2 ;; esac
done
for e2e_a in lib $AREAS; do
  [ -f "$E2E_DIR/$e2e_a.sh" ] || { echo "test/e2e/$e2e_a.sh is missing" >&2; exit 2; }
  bash -n "$E2E_DIR/$e2e_a.sh" || { echo "test/e2e/$e2e_a.sh has a syntax error" >&2; exit 2; }
done
# throwaway repo with a "github" slug the origin URL contains
git init -q --bare $T/local/origin.git; git clone -q $T/local/origin.git $T/repo 2>/dev/null
(cd $T/repo && git commit -q --allow-empty -m init && git branch -M main && git push -q origin main)
# Git-ignored files a new worktree needs (#10): repo.copy brings them over from the main checkout,
# then repo.bootstrap (a stand-in that logs where it ran and whether the copy came first) runs there.
mkdir -p $T/repo/conf && echo "SECRET=1" > $T/repo/.env.local && echo '{"dev":true}' > $T/repo/conf/dev.json && printf '.env.local\nconf/\n' >> $T/repo/.git/info/exclude
printf '#!/bin/sh\necho "$TEAM_ROLE $(pwd -P) env=$(test -f .env.local && echo yes || echo no) repo=$TEAM_REPO" >> %s/boot.log\n' $T > $T/bin/boot; chmod +x $T/bin/boot
# fake claude: a real binary named claude (the process check looks at the process name). It
# draws Claude Code 2.1.316's input box as captured on 2026-10-30 (a rule naming the session from
# -n, cursor and no-break space, a plain rule, then a status line and the mode line; an empty box
# shows a dim hint) and redraws it after
# every key. Bracketed paste is on, so a pasted newline stays in the box and only a typed Enter
# submits. Every byte read goes to $FAKE_KEYLOG. Optional files per seat, named by $FAKE_FILES-*:
#   prompt  a dialog, drawn instead of the box     output  lines drawn above the box
#   mode    swallow (input never shows), below (a list under the box), prefill (text left in the box),
#           suggest (a dim suggested prompt in the empty box), sticky (that suggestion stays drawn after
#           any text), mixed (typed text and the dim suggestion), mention (the @-mention list drawn
#           above the box while its last word starts with @, no row highlighted, as after a paste),
#           mentionsel (text "sel @sr" with the list's first row highlighted: Enter completes it)
#           cut (the screen ends at the input row: no bottom rule and no footer, as a pane too
#           short for what is drawn above the box)
# A submitted line that starts with ! is run by /bin/sh the way Claude Code's Bash tool runs a
# command: in a child that leaves the pane's terminal (setsid), so the child has no tty of its own
# and only the stand-in, its parent, holds the pane's tty.
# Its source is test/e2e/fake-claude.c, copied to $T/c.c, where later sections recompile it.
cp "$SRC/test/e2e/fake-claude.c" $T/c.c || { echo "cannot copy test/e2e/fake-claude.c"; exit 2; }
cc -o $T/bin/claude $T/c.c || { echo "no compiler"; exit 2; }
printf '#!/bin/sh\necho "$TEAM_ROLE $1" >> %s/bin.log\nc=$1\nshift\necho "$TEAM_ROLE $*" >> %s/args.log\necho "$TEAM_ROLE DISABLE_AUTOUPDATER=${DISABLE_AUTOUPDATER-unset}" >> %s/env.log\necho "$TEAM_ROLE CLAUDE_CODE_DISABLE_AUTO_MEMORY=${CLAUDE_CODE_DISABLE_AUTO_MEMORY-unset}" >> %s/env.log\nexport FAKE_KEYLOG=%s/keys-$TEAM_ROLE.log FAKE_FILES=%s/fake-$TEAM_ROLE\nexec "$c" "$@"\n' $T $T $T $T $T $T > $T/bin/wrap; chmod +x $T/bin/wrap
mkdir -p $T/proj
cat > $T/team.yaml <<Y
team: tt
repo: { path: $T/repo, github: local/origin.git, base: origin/main, gate: "make check", gate_timeout: 120, gate_max_blocks: 2,
        bootstrap: "$T/bin/boot", copy: [.env.local, conf/dev.json, missing.txt] }
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
  w1: { title: Worker One, model: sonnet, effort: low, permission_mode: default, gate_on_stop: true, workdir: { type: worktree }, prompt_text: "w1 prompt",
        permissions: { deny: ["Bash(gh pr merge *)", "Read(//**/.env)"], allow: ["Bash(make *)"] } }
  w2: { title: Worker Two, auto_memory: true, workdir: { type: worktree }, prompt_text: "w2 prompt" }
Y
export PATH=$T/bin:$PATH
# legacy worktree for w2, internal disk
git -C $T/repo worktree add -q --detach $T/repo/.claude/worktrees/team-w2 origin/main
. "$E2E_DIR/lib.sh"
for e2e_a in $AREAS; do . "$E2E_DIR/$e2e_a.sh"; done
echo "--- iTerm"
[ ! -e $T/osascript.log ] && ok "nothing in this run called osascript, so no iTerm window was opened" || { bad "osascript was called $(wc -l < $T/osascript.log | tr -d ' ') time(s)"; cut -c1-120 $T/osascript.log | head -5; }
echo "--- cleanup"
$S -c $T/team.yaml down --yes >/dev/null 2>&1; tmux kill-server 2>/dev/null
for w in team-w1 team-w2; do git -C $T/repo worktree remove --force $VOL/$ROOT/$w 2>/dev/null; git -C $T/repo worktree remove --force $T/repo/.claude/worktrees/$w 2>/dev/null; done
rmdir $VOL/$ROOT 2>/dev/null; [ ! -e $VOL/$ROOT ] && ok "test folder removed from the volume" || bad "test folder removed from the volume ($(ls -A $VOL/$ROOT 2>&1 | head -3))"
rm -rf "$T"
echo "RESULT pass=$pass fail=$fail"
finished=1; [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
