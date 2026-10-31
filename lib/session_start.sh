#!/usr/bin/env bash
#
# SessionStart hook that factory.sh puts in every seat's generated settings (#5). Claude Code adds what
# it prints to the seat's context at startup, on resume, after /clear and after a compaction, so a
# restarted seat can carry on: its progress note, what to do with it, the branch it is on, recent
# commits and uncommitted files.
#
#   session_start.sh <state dir> <role> <workdir>
#
# The hook input (JSON on stdin) is not needed and is not read. The note, <state>/notes/<role>.md, is
# written by the seat itself; a long one is cut, so it cannot flood the seat's context (Claude Code
# also caps what a hook adds). The script always exits 0: a seat must start even when its working
# directory is gone or is not a repository.
set -u
state=$1 role=$2 workdir=$3
note="$state/notes/$role.md"

# Each git command has its own time limit, well inside the hook's 10s: Claude Code kills a hook
# past its timeout and drops its output, and a slow status (a cold external volume) must not cost the
# seat its note, which is printed first. A repository's fsmonitor program is not run.
limit() { perl -e 'alarm shift; exec @ARGV or exit 127' "$@"; }

report() {
  echo "# Session start: $role"
  echo "## Your progress note ($note)"
  if [ -f "$note" ] && [ -s "$note" ]; then
    # Read as bytes and shown as UTF-8 with invalid bytes replaced, whatever the locale (LC_ALL=C
    # included). Cut at 80 lines or 6000 bytes, whichever comes first, on a character boundary.
    ruby -e '
      path = ARGV[0]
      raw = File.binread(path)
      s = raw.dup.force_encoding("UTF-8").scrub("?")
      lines = s.lines
      out = lines.first(80).join
      out = out.byteslice(0, 6000).scrub("") if out.bytesize > 6000
      cut = out.bytesize < s.bytesize
      print out
      puts unless out.end_with?("\n")
      puts "[note truncated: #{lines.size} lines, #{raw.bytesize} bytes; the whole note is in #{path}. Keep it short.]" if cut
    ' "$note" 2>/dev/null || echo "(could not read $note)"
  else
    echo "(no progress note yet: write one at $note when you take a task)"
  fi
  echo
  # What to do with it. This moved here from the shared prompt (#117), so it is printed on every path,
  # before the working-directory checks that can return early.
  echo "Each session starts with your progress note, your branch, uncommitted files and recent commits in"
  echo "your context. Name the task and next step in your first reply, then follow your kickoff (it may say to wait)."
  echo "If the note and the repository disagree, trust the repository and fix the note."
  echo

  echo "## Working directory: $workdir"
  if [ ! -d "$workdir" ]; then
    echo "$workdir does not exist"
    return
  fi
  if ! git -C "$workdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "$workdir is not a git work tree"
    return
  fi
  branch=$(git -C "$workdir" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    echo "Branch: $branch"
  else
    echo "Branch: (detached at $(git -C "$workdir" rev-parse --short HEAD 2>/dev/null || echo '?'))"
  fi
  changes=$(limit 4 git -C "$workdir" -c core.fsmonitor=false status --short 2>/dev/null); rc=$?
  if [ $rc -ge 128 ]; then
    echo "Uncommitted changes: (git status did not finish within 4s; run it yourself)"
  elif [ -z "$changes" ]; then
    echo "Uncommitted changes: none"
  else
    n=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
    echo "Uncommitted changes ($n, git status --short):"
    printf '%s\n' "$changes" | head -20
    [ "$n" -gt 20 ] && echo "... and $((n - 20)) more"
  fi
  echo "Recent commits (git log --oneline -10):"
  log=$(limit 3 git -C "$workdir" log --oneline -10 2>/dev/null); rc=$?
  if [ $rc -ge 128 ]; then echo "(git log did not finish within 3s)"; else printf "%s\n" "$log" | cut -c1-200; fi
}

# Everything goes through one filter: C0 control characters other than tab and newline, and DEL,
# are dropped, so a note or a commit subject holding a terminal escape (a title or clipboard
# sequence) reaches the seat as plain text. UTF-8 bytes are all 0x80 and above, so they pass.
report | LC_ALL=C tr -d '\000-\010\013-\037\177'
exit 0
