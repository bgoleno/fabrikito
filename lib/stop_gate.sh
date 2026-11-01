#!/usr/bin/env bash
#
# Stop hook that factory.sh puts in the generated settings of a role with gate_on_stop. When the
# seat ends a turn with uncommitted changes in its working tree, it runs the repo's gate. If the
# gate fails, it exits 2, and Claude Code sends the seat back to work with stderr as the reason.
#
#   stop_gate.sh <state dir> <role> <workdir> <gate command> <timeout s> <max blocks>
#
# The hook input (JSON) arrives on stdin: session_id, and stop_hook_active (true when this stop
# ends a turn the hook has already sent back). The working directory is the one the launcher
# configured, not the hook's cwd, which follows Claude's current folder.
#
# A seat also stops for reasons other than "done": to wait for an answer or a review, or with a
# test red on purpose. Every send-back says so, with the limit. After <max blocks> failed gates in
# a row in one turn the stop goes through, with a stopReason saying the gate is still failing, and without running the gate again.
# The next turn starts from zero, so a seat that lives for days is never gated off for good. The
# count is kept in <state>/gate/<role>.count, which seats cannot edit (an Edit deny in their
# settings); a passing gate or a clean tree resets it. Run by hand with no hook input, the script
# runs the gate and reports, but leaves the count alone. Claude Code also ends the loop by itself
# after 8 continuations in a row with no tool call in between (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP).
set -u
state=$1 role=$2 workdir=$3 gate=$4 limit=$5 max=$6
input=$(ruby -rjson -e 'j = (JSON.parse(STDIN.read) rescue {}); j = {} unless j.is_a?(Hash)
  print j["session_id"].to_s.gsub(/[^A-Za-z0-9._-]/, ""), " ", j["stop_hook_active"] == true' 2>/dev/null)
session=${input% *}
active=${input##* }
dir="$state/gate"
log="$dir/$role.log"
count="$dir/$role.count"

# Every git call here runs with core.fsmonitor=false (#104). A repository's fsmonitor is a program
# named in its git config, which git runs whenever it looks at the work tree, and this hook runs
# unattended in every gated seat. fsmonitor is only a speed-up: status gives the same answer
# without it. The setting reaches submodules too. Clean filters stay on, as decided with sec on #104:
# turning them off changes what status reports (a touched LFS file would show as modified), and
# their command, like fsmonitor's, can only come from git config.
g() { git -c core.fsmonitor=false "$@"; }

# The .git (a folder, or the file a worktree has) of the working directory or the nearest folder
# above it, as git's own search would find it; none means not in a repository.
dotgit() {
  local d=$PWD
  while :; do
    if [ -e "$d/.git" ] || [ -L "$d/.git" ]; then echo "$d/.git"; return 0; fi
    [ "$d" = / ] && return 1
    d=$(dirname "$d")
  done
}

cd "$workdir" 2>/dev/null || exit 0
# Outside a repository the stop goes through ungated. But git says "not a git repository" for a
# repository it cannot read too (a corrupt HEAD, a worktree's gitdir gone bad), so a failure with a
# .git in place is not taken for no repository: the tree is gated, as for a failed status (#118).
unreadable=""
if ! git_err=$(g rev-parse --is-inside-work-tree 2>&1 >/dev/null); then
  repo=$(dotgit) || exit 0
  unreadable="git cannot read the repository at $repo: $(printf '%s\n' "$git_err" | head -n 1)"
fi
# The hook writes gate/, the log and the count, and trusts the count: a planted one could let a stop
# through without the gate. up refuses a link at gate/ (#174), but a seat could put one there, or at
# either file, after up, and mkdir -p, > and read all follow it (#194, sec on #174). So a link, or
# anything other than a folder or a regular file, at any of them is refused: no gate runs and
# nothing is written. Fail closed: the seat is sent back, told to report it. In a turn the hook has
# already sent back, the stop goes through with a stopReason instead, as without its count the hook
# cannot end that loop itself. Not atomic with the writes below; only a seat could make the link.
unsafe=""
if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
  unsafe=$dir
else
  for p in "$log" "$count"; do
    if [ -L "$p" ] || { [ -e "$p" ] && [ ! -f "$p" ]; }; then unsafe=$p && break; fi
  done
fi
if [ -n "$unsafe" ]; then
  why="The stop gate did not run: $unsafe is a symlink, or not a regular file or folder, and the hook does not write or read its state through one (#194). Report it to the EM: only a seat could have put it there, and it is removed by its exact path."
  if [ "$active" = true ]; then
    ruby -rjson -e 'puts JSON.generate("continue" => false, "stopReason" => ARGV[0])' "$why"
    exit 0
  fi
  echo "$why" >&2
  exit 2
fi
mkdir -p "$dir"
# Only uncommitted work is gated (untracked files count; ignored ones do not). Committed work is
# gated again when the reviewer runs the gate on the PR. A status that fails (a corrupt index, a
# required clean filter that fails) is not read as a clean tree: the gate runs, so the hook fails
# closed (#104). Nor is a repository git cannot read: there status is not run at all.
status_rc=0
if [ -z "$unreadable" ]; then
  changes=$(g status --porcelain 2>/dev/null)
  status_rc=$?
  if [ "$status_rc" = 0 ] && [ -z "$changes" ]; then
    [ -n "$session" ] && rm -f "$count"
    exit 0
  fi
fi

# Failures so far in this turn: none at the start of a turn, or in another session.
n=0
if [ -n "$session" ] && [ "$active" = true ] && [ -f "$count" ]; then
  read -r was c <"$count"
  case $c in '' | *[!0-9]*) c=0 ;; esac
  [ "$was" = "$session" ] && n=$c
fi
let_through() {
  ruby -rjson -e 'puts JSON.generate("continue" => false, "stopReason" => ARGV[0])' \
    "The gate is still failing after $max tries in a row ($log). The stop goes through: report the failing gate to the EM if you have not."
  exit 0
}
# At the limit in this turn the stop goes through anyway, so the gate is not run again for it.
[ "$n" -ge "$max" ] && let_through

# macOS has no timeout(1). The gate runs in a process group of its own (perl's setpgrp), so on
# timeout the whole group is killed, with everything it started in the background. A program that
# leaves the group by itself (a tmux server daemonizes with setsid) is not reached. While it runs,
# this script's stderr is closed off: bash reports a killed background job ("Terminated: 15") there,
# and Claude would read it as part of the gate's message.
exec 3>&2 2>/dev/null
perl -e 'setpgrp(0, 0); exec @ARGV' bash -c "$gate" </dev/null >"$log" 2>&1 3>&- &
pid=$!
timed_out=0
ticks=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$ticks" -ge $((limit * 10)) ]; then
    timed_out=1
    kill -TERM -- "-$pid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -KILL -- "-$pid" 2>/dev/null
    break
  fi
  sleep 0.1
  ticks=$((ticks + 1))
done
rc=0
wait "$pid" || rc=$?
exec 2>&3 3>&-

if [ "$timed_out" = 0 ] && [ "$rc" = 0 ]; then
  [ -n "$session" ] && rm -f "$count"
  exit 0
fi

n=$((n + 1))
[ -n "$session" ] && printf '%s %s\n' "$session" "$n" >"$count"
{
  if [ "$timed_out" = 1 ]; then
    echo "gate timed out after ${limit}s: $gate"
  else
    echo "gate failed (exit $rc): $gate"
  fi
  [ "$status_rc" = 0 ] || echo "(git status failed in $workdir (exit $status_rc), so the tree was gated as if it had uncommitted changes.)"
  [ -z "$unreadable" ] || echo "($unreadable. So the tree was gated as if it had uncommitted changes.)"
  echo "Last lines of its output (all of it is in $log):"
  tail -n 60 "$log"
  echo
  echo "Fix the cause. Run $gate in $workdir yourself (not lib/stop_gate.sh) and report the command and its output."
  # On every send-back, not only the last: this is the one place a gated seat is told how to stop on
  # purpose (it moved here from the shared prompt, #117). stderr is what Claude reads; the stopReason
  # of a let-through is shown to the user only.
  echo "If you are stopping on purpose (waiting for an answer or a review, or with a test red on purpose)," \
    "say so in your report: the gate lets you stop after it has failed $max times in a row in one turn."
  [ "$n" -eq "$max" ] && echo "This is the last time the gate sends you back in this turn."
} >&2
exit 2
