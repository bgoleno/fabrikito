#!/usr/bin/env bash
#
# Stop hook that factory.sh puts in the generated settings of a role with gate_on_stop. When the
# seat ends a turn with uncommitted changes in its working tree, it runs the repo's gate. If the
# gate fails, it exits 2, and Claude Code sends the seat back to work with stderr as the reason.
#
#   stop_gate.sh <state dir> <role> <workdir> <gate command> <timeout s> <max blocks>
#
# The hook input (JSON) arrives on stdin; only session_id is used. The working directory is the one
# the launcher configured, not the hook's cwd, which follows Claude's current folder.
#
# A seat also stops for reasons other than "done": to wait for an answer or a review, or with a
# test red on purpose. So after <max blocks> failed gates in a row in one session the stop goes
# through, with a stopReason saying the gate is still failing. The count is kept in
# <state>/gate/<role>.count, which seats cannot edit (an Edit deny in their settings); a passing
# gate or a clean tree resets it. Claude Code also ends the loop by itself after 8 continuations in
# a row with no tool call in between (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP).
set -u
state=$1 role=$2 workdir=$3 gate=$4 limit=$5 max=$6
session=$(ruby -rjson -e 'puts((JSON.parse(STDIN.read)["session_id"] rescue nil).to_s)' 2>/dev/null)
dir="$state/gate"
log="$dir/$role.log"
count="$dir/$role.count"

cd "$workdir" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
mkdir -p "$dir"
# Only uncommitted work is gated (untracked files count; ignored ones do not). Committed work is
# gated again when the reviewer runs the gate on the PR.
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  rm -f "$count"
  exit 0
fi

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
  rm -f "$count"
  exit 0
fi

# Failures in a row in this session; another session starts from zero.
n=0
if [ -f "$count" ]; then
  read -r was c <"$count"
  [ "$was" = "$session" ] && n=${c:-0}
fi
n=$((n + 1))
printf '%s %s\n' "$session" "$n" >"$count"

if [ "$n" -gt "$max" ]; then
  ruby -rjson -e 'puts JSON.generate("continue" => false, "stopReason" => ARGV[0])' \
    "The gate is still failing after $max tries in a row ($log). The stop goes through: report the failing gate to the EM if you have not."
  exit 0
fi
{
  if [ "$timed_out" = 1 ]; then
    echo "gate timed out after ${limit}s: $gate"
  else
    echo "gate failed (exit $rc): $gate"
  fi
  echo "Last lines of its output (all of it is in $log):"
  tail -n 60 "$log"
  echo
  echo "Fix the cause, run the gate yourself, and report the command and its output."
  if [ "$n" -eq "$max" ]; then
    echo "This is the last time the gate sends you back in this session. If you are stopping on purpose" \
      "(waiting for an answer or a review, or with a test red on purpose), say so in your report."
  fi
} >&2
exit 2
