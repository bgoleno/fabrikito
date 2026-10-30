#!/usr/bin/env bash
#
# Start, message and stop a team of Claude Code sessions, each in its own persistent tmux
# session, each told its role, able to message each other through `say`. The team (roles,
# prompts, session names, claude flags, and where worktrees live) is defined in a YAML file:
# see teams/example.yaml, which documents every key.
#
#   factory.sh [-c team.yaml] <command>
#
#   check                      validate the team file and show where everything will live
#   up [role...]               start the team (default: every role, in file order); skips seats that are up
#   status                     which seats are up, and where each one works
#   say <role|all> <message>   type a message into a seat (this is how seats talk to each other)
#   attach <role>              attach your terminal to a seat (detach: ctrl-b d)
#   migrate [role...]          remove clean worktrees that are not under the configured storage
#                              volume, so `up` recreates them there (stop the seat first)
#   down --yes [role...]       kill seats (worktrees are kept)
#
# The team file is -c, else $TEAM_CONFIG, else teams/team.yaml next to this script.
#
# With `--dangerously-skip-permissions` in the file's claude args there are no permission
# prompts, so the hard rules in the shared prompt are the only guardrail. A seat's role is
# delivered as an appended system prompt (it survives compaction) plus a short first message.
#
# A tmux session is a shell that runs claude, so quitting claude leaves the shell and the
# session alive; `up` after that skips the seat. Run `down` first to start it fresh.
#
# Environment: TEAM_CONFIG (team file), TEAM_STATE_DIR (generated prompts, launchers and the
# message log; default .state/<team>/ next to this script).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF="$HERE/factory.sh"
RB="$HERE/lib/team_config.rb"

CONFIG=${TEAM_CONFIG:-$HERE/teams/team.yaml}
while [ $# -gt 0 ]; do
  case $1 in
    -c | --config)
      [ $# -ge 2 ] || { echo "error: $1 needs a file" >&2; exit 64; }
      CONFIG=$2
      shift 2
      ;;
    *) break ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
command -v ruby >/dev/null || die "ruby not found (it parses the team file; it ships with macOS)"
[ -f "$CONFIG" ] || die "team file not found: $CONFIG (copy teams/example.yaml to teams/team.yaml and edit it, or pass -c <file>)"
CONFIG=$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")
export TEAM_CONFIG=$CONFIG

cfg() { ruby "$RB" "$CONFIG" "$@"; }

# Every command validates the file first: a typo or a missing prompt stops here, not after
# half a team has started.
cfg validate

TEAM=$(cfg get team)
REPO=$(cfg get repo.path)
GITHUB=$(cfg get repo.github)
PROJECT_NAME=$(cfg get project.name)
PROJECT_URL=$(cfg get project.url)
BASE=$(cfg get repo.base)
VOLUME=$(cfg get storage.volume)
WT_ROOT=$(cfg get storage.worktree_root)
PREFIX=$(cfg get sessions.prefix)
WRAPPER=$(cfg get sessions.wrapper)
ROLES=$(cfg ids | tr '\n' ' ')
STATE=${TEAM_STATE_DIR:-$HERE/.state/$TEAM}
LOG="$STATE/messages.log"

title() { cfg role "$1" title; }
session() { cfg role "$1" session; }
workdir() { cfg workdir "$1"; }
wtype() { cfg role "$1" workdir_type; }

check_role() {
  case " $ROLES" in
    *" $1 "*) ;;
    *) die "unknown role '$1' (roles: $ROLES)" ;;
  esac
}
alive() { tmux has-session -t "=$(session "$1")" 2>/dev/null; }

# The worktree volume is proven from the mount table, at the moment a worktree is created, and
# the target folder is proven to be on it. `mkdir -p` under an unmounted /Volumes path would
# quietly create the folder on the internal disk, so nothing is created before this passes.
require_volume() {
  mount | grep -qF " on $VOLUME (" || die "storage volume $VOLUME is not mounted; refusing to put worktrees on another disk"
  mkdir -p "$WT_ROOT" || die "cannot create $WT_ROOT"
  local on t
  on=$(df -P "$WT_ROOT" | awk 'NR==2 { $1=$2=$3=$4=$5=""; sub(/^ +/, ""); print }')
  [ "$on" = "$VOLUME" ] || die "$WT_ROOT is on '$on', not on the storage volume $VOLUME"
  t=$(mktemp "$WT_ROOT/.write-test.XXXXXX") || die "cannot write to $WT_ROOT"
  rm -f "$t"
}

# Registered worktrees of the repo with this folder name that are not at the expected path.
other_worktrees_named() {
  local name=$1 expected=$2 p
  git -C "$REPO" worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r p; do
    if [ "$(basename "$p")" = "$name" ] && [ "$p" != "$expected" ]; then echo "$p"; fi
  done
  return 0
}

# Create the worktree detached at the base ref, but never reuse or alter one that exists: it
# may hold a seat's unfinished work.
ensure_worktree() {
  local id=$1 dir url legacy
  dir=$(workdir "$id")
  if [ -d "$dir" ]; then
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "$dir exists but is not a git worktree"
    return 0
  fi
  legacy=$(other_worktrees_named "$(cfg role "$id" worktree_name)" "$dir")
  if [ -n "$legacy" ]; then
    die "'$id' already has a worktree elsewhere ($legacy). Stop the seat and run: $SELF migrate $id"
  fi
  require_volume
  url=$(git -C "$REPO" remote get-url origin)
  case $url in
    *"$GITHUB"*) ;;
    *) die "origin of $REPO is '$url', expected it to contain '$GITHUB'" ;;
  esac
  git -C "$REPO" fetch --quiet origin "${BASE#origin/}" || echo "warning: fetch failed; using the local $BASE" >&2
  git -C "$REPO" worktree add --detach "$dir" "$BASE" >/dev/null
  echo "  created worktree $dir"
}

cmd_check() {
  local r on="not mounted"
  mount | grep -qF " on $VOLUME (" && on="mounted"
  echo "team file : $CONFIG"
  echo "team      : $TEAM (tmux prefix '$PREFIX')"
  echo "repo      : $GITHUB at $REPO (origin must contain '$GITHUB', base $BASE)"
  echo "project   : $PROJECT_NAME $PROJECT_URL"
  echo "worktrees : $WT_ROOT   [volume $VOLUME: $on]"
  echo "wrapper   : ${WRAPPER:-none (claude runs directly)}"
  echo "state     : $STATE"
  printf '%-5s %-36s %-18s %-12s %-9s %s\n' ROLE SEAT SESSION MODEL EFFORT WORKDIR
  for r in $ROLES; do
    printf '%-5s %-36s %-18s %-12s %-9s %s\n' "$r" "$(title "$r")" "$(session "$r")" "$(cfg role "$r" model)" "$(cfg role "$r" effort)" "$(workdir "$r")"
  done
  echo "(inherit = flag omitted; the seat uses the model and effortLevel in ~/.claude/settings.json)"
  echo "valid."
}

cmd_up() {
  local roles=${*:-$ROLES} r sess dir launch a args_q
  command -v tmux >/dev/null || die "tmux not found"
  command -v claude >/dev/null || die "claude not found"
  for r in $roles; do check_role "$r"; done
  mkdir -p "$STATE/prompts" "$STATE/launch"
  # Roles start in the order given (file order by default).
  for r in $roles; do
    sess=$(session "$r")
    if alive "$r"; then
      echo "skip   $r: session $sess already exists (left alone)"
      continue
    fi
    dir=$(workdir "$r")
    if [ "$(wtype "$r")" = worktree ]; then ensure_worktree "$r"; fi
    [ -d "$dir" ] || die "working directory $dir does not exist"
    args_q=""
    while IFS= read -r a; do args_q="$args_q $(printf '%q' "$a")"; done < <(cfg claude_args "$r")

    TEAM_SCRIPT=$SELF TEAM_LOG=$LOG cfg render "$r" >"$STATE/prompts/$r.md"
    TEAM_SCRIPT=$SELF TEAM_LOG=$LOG cfg kickoff "$r" >"$STATE/prompts/$r.kickoff"
    launch="$STATE/launch/$r.sh"
    {
      echo '#!/usr/bin/env bash'
      printf 'cd %q\n' "$dir"
      echo '# The wrapper holds the macOS privacy grants (Downloads, removable volumes) that a seat'
      echo '# started from tmux has no responsible app for; it passes them to its child. If it is'
      echo '# configured but missing, claude runs directly.'
      printf 'wrapper=%q\n' "$WRAPPER"
      echo 'claude_bin="$(command -v claude)"'
      echo 'if [ -n "$wrapper" ] && [ -x "$wrapper" ]; then run=("$wrapper" "$claude_bin"); else run=("$claude_bin"); fi'
      printf '"${run[@]}"%s -n %q \\\n' "$args_q" "$sess"
      printf '  --append-system-prompt "$(cat %q)" \\\n' "$STATE/prompts/$r.md"
      printf '  "$(cat %q)"\n' "$STATE/prompts/$r.kickoff"
    } >"$launch"
    chmod +x "$launch"

    tmux new-session -d -s "$sess" -c "$dir" -x 220 -y 50 \
      -e "TEAM_ROLE=$r" -e "TEAM_CONFIG=$CONFIG" -e "TEAM_SCRIPT=$SELF"
    tmux send-keys -t "=$sess:" "$launch" Enter
    echo "start  $r: $(title "$r") -> tmux session $sess ($dir)"
    sleep 1
  done
  # A seat started in a folder Claude Code has not seen stops at a trust dialog (and the first
  # bypass-permissions run at a warning) until a human answers once. Say which seats those are.
  sleep 6
  echo
  for r in $roles; do
    alive "$r" || continue
    if pane_blocked "$r"; then
      echo "ATTENTION $r is waiting at a startup prompt: $SELF attach $r, answer it, detach (ctrl-b d)"
    fi
  done
  echo "Attach with: $SELF attach <role>"
}

cmd_status() {
  local r sess where d
  printf '%-5s %-36s %-18s %-6s %s\n' ROLE SEAT SESSION STATE WORKDIR
  for r in $ROLES; do
    sess=$(session "$r")
    d=$(workdir "$r")
    if [ "$(wtype "$r")" = worktree ]; then
      if [ ! -d "$d" ]; then
        where="$d (missing)"
      else
        case $d in "$VOLUME"/*) where="$d" ;; *) where="$d (OFF VOLUME)" ;; esac
      fi
    else
      where=$d
    fi
    printf '%-5s %-36s %-18s %-6s %s\n' "$r" "$(title "$r")" "$sess" "$(alive "$r" && echo up || echo down)" "$where"
  done
}

# True when a claude process is attached to the seat's terminal. The pane's own command name is
# no use for this: the launcher is a bash script, so tmux reports "bash" while claude runs.
has_claude() {
  local tty
  tty=$(tmux display-message -p -t "=$(session "$1"):" '#{pane_tty}')
  ps -t "${tty#/dev/}" -o comm= | grep -qE '(^|/)claude(\.exe)?$'
}

# True when the seat's screen shows one of Claude Code's first-run dialogs.
pane_blocked() {
  tmux capture-pane -p -t "=$(session "$1"):" |
    grep -qE 'Is this a project you created|Yes, I trust this folder|No, exit|Bypass Permissions mode|Enter to confirm'
}

# Deliver one message by bracketed paste (safe for multi-line text), then Enter. If the seat is
# mid-turn the text queues in its input box and is submitted by the Enter all the same.
send_one() {
  local to=$1 text=$2 sess buf
  sess=$(session "$to")
  if ! alive "$to"; then
    echo "not delivered: $to is down ($sess)" >&2
    return 1
  fi
  # Never type into a seat that is not ready to take a message. At a shell, the text would run
  # as a command. At a startup dialog ("trust this folder", "Bypass permissions") the Enter
  # would pick the highlighted default, which is "No, exit".
  if ! has_claude "$to"; then
    echo "not delivered: $to has no claude process running (its pane is at a shell)" >&2
    return 1
  fi
  if pane_blocked "$to"; then
    echo "not delivered: $to is waiting at a startup prompt; attach and answer it first" >&2
    return 1
  fi
  buf="team-$$-$to"
  printf '%s' "$text" | tmux load-buffer -b "$buf" -
  tmux paste-buffer -p -d -b "$buf" -t "=$sess:"
  sleep 0.5
  tmux send-keys -t "=$sess:" Enter
}

cmd_say() {
  local to=${1:-} from=${TEAM_ROLE:-owner} text r rc=0
  [ -n "$to" ] && [ $# -ge 2 ] || die "usage: say <role|all> <message...>"
  shift
  text="[from $from] $*"
  mkdir -p "$STATE"
  if [ "$to" = all ]; then
    for r in $ROLES; do
      [ "$r" = "$from" ] && continue
      alive "$r" || continue
      send_one "$r" "$text" || rc=1
    done
  else
    check_role "$to"
    [ "$to" = "$from" ] && die "a seat cannot message itself"
    send_one "$to" "$text" || rc=1
  fi
  # The log records what happened, not what was attempted: a refused delivery says so.
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$from" "$to" \
    "$([ "$rc" -eq 0 ] && echo delivered || echo NOT-DELIVERED)" "$*" >>"$LOG"
  return "$rc"
}

cmd_attach() {
  local r=${1:-}
  [ -n "$r" ] || r=${ROLES%% *}
  check_role "$r"
  alive "$r" || die "$r is down"
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$(session "$r")"; else tmux attach -t "=$(session "$r")"; fi
}

# Remove worktrees that are registered under a team role's folder name but are not at the
# configured location. Bounded by construction: only a clean worktree, with no branch checked
# out and HEAD already contained in the base ref, is removed, so nothing it holds can be lost
# except ignored files (node_modules, build output), which a fresh install recreates.
cmd_migrate() {
  local roles=${*:-$ROLES} r p dir name moved=0
  for r in $roles; do check_role "$r"; done
  for r in $roles; do
    [ "$(wtype "$r")" = worktree ] || continue
    dir=$(workdir "$r")
    name=$(cfg role "$r" worktree_name)
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if alive "$r"; then echo "skip   $r: seat is up; stop it first ($SELF down --yes $r)"; continue; fi
      if [ ! -d "$p" ]; then echo "skip   $r: $p is registered but missing (run: git -C $REPO worktree prune)"; continue; fi
      if [ -n "$(git -C "$p" status --porcelain)" ]; then echo "REFUSE $r: $p has uncommitted or untracked files"; continue; fi
      if [ -n "$(git -C "$p" branch --show-current)" ]; then echo "REFUSE $r: $p has branch '$(git -C "$p" branch --show-current)' checked out; move that work by hand"; continue; fi
      if ! git -C "$p" merge-base --is-ancestor HEAD "$BASE"; then echo "REFUSE $r: $p HEAD is not contained in $BASE (unpushed commits)"; continue; fi
      git -C "$REPO" worktree remove "$p"
      echo "moved  $r: removed $p; '$SELF up $r' recreates it at $dir"
      moved=$((moved + 1))
    done < <(other_worktrees_named "$name" "$dir")
  done
  echo "removed $moved worktree(s)."
  echo "Other worktrees of $REPO that this team does not manage (left alone):"
  git -C "$REPO" worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r p; do
    [ "$p" = "$REPO" ] && continue
    case $p in "$WT_ROOT"/*) continue ;; esac
    echo "  $p"
  done
}

cmd_down() {
  local yes=0 roles="" a r
  for a in "$@"; do
    if [ "$a" = --yes ]; then yes=1; else roles="$roles $a"; fi
  done
  roles=${roles:-$ROLES}
  for r in $roles; do check_role "$r"; done
  for r in $roles; do
    alive "$r" || continue
    if [ $yes -eq 1 ]; then
      tmux kill-session -t "=$(session "$r")"
      echo "killed $r ($(session "$r"))"
    else
      echo "would kill $r ($(session "$r")); rerun with --yes"
    fi
  done
}

case "${1:-}" in
  check) cmd_check ;;
  up) shift; cmd_up "$@" ;;
  status) cmd_status ;;
  say) shift; cmd_say "$@" ;;
  attach) shift; cmd_attach "$@" ;;
  migrate) shift; cmd_migrate "$@" ;;
  down) shift; cmd_down "$@" ;;
  *) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
