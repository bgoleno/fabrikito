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
#   up [--no-view] [role...]   start the team (default: every role, in file order); skips seats that are up,
#                              then opens the iTerm tab (see `view`) unless --no-view or display.iterm is false
#   titles                     set each running seat's terminal title to "<role> | <title> | <session>" (up and
#                              view do this too); it is what iTerm shows in each pane's header
#   view                       open a new iTerm tab with every running seat in a pane: the primary seat
#                              (display.primary, default the first role) on the left at full height, the others
#                              in rows on the right; the window is sized to its screen (display.window)
#   status                     which seats are up, and where each one works
#   say <role|all> <message>   type a message into a seat (this is how seats talk to each other)
#   attach <role>              attach your terminal to a seat (detach: ctrl-b d)
#   migrate [role...]          remove clean worktrees that are not under the configured storage
#                              volume, so `up` recreates them there (stop the seat first)
#   down --yes [role...]       kill seats (worktrees are kept)
#
# The team file is -c, else $TEAM_CONFIG, else teams/team.yaml next to this script.
#
# Each seat starts with a generated settings file (--settings): the team's and its role's
# permission rules, plus Edit denies on the files that would change its next start. Deny and ask
# rules hold in every permission mode, bypassPermissions included; they match command text, so
# they guard against accidents, not against a determined process. A seat's role is delivered as an
# appended system prompt (it survives compaction) plus a short first message.
#
# A tmux session is a shell that runs claude, so quitting claude leaves the shell and the
# session alive; `up` after that skips the seat. Run `down` first to start it fresh.
#
# Environment: TEAM_CONFIG (team file), TEAM_STATE_DIR (generated prompts, launchers, settings
# and the message log; default .state/<team>/ next to this script).
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
VIEW_ITERM=$(cfg get display.iterm)
VIEW_PRIMARY=$(cfg get display.primary)
VIEW_WINDOW=$(cfg get display.window)
ROLES=$(cfg ids | tr '\n' ' ')
STATE=$(cfg get state.dir)
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
  printf '%-5s %-36s %-18s %-12s %-9s %-24s %s\n' ROLE SEAT SESSION MODEL EFFORT MODE WORKDIR
  for r in $ROLES; do
    printf '%-5s %-36s %-18s %-12s %-9s %-24s %s\n' "$r" "$(title "$r")" "$(session "$r")" "$(cfg role "$r" model)" \
      "$(cfg role "$r" effort)" "$(cfg role "$r" permission_mode)" "$(workdir "$r")"
  done
  echo "(inherit = flag omitted; the seat uses model, effortLevel and permissions.defaultMode from ~/.claude/settings.json)"
  echo
  cfg permissions_report
  echo "valid."
}

cmd_up() {
  local want_view=1 started=0 args="" roles r sess dir launch a args_q settings
  for a in "$@"; do
    if [ "$a" = --no-view ]; then want_view=0; else args="$args $a"; fi
  done
  roles=${args:-$ROLES}
  command -v tmux >/dev/null || die "tmux not found"
  command -v claude >/dev/null || die "claude not found"
  for r in $roles; do check_role "$r"; done
  for a in $(cfg get state.generated_dirs); do mkdir -p "$STATE/$a"; done
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

    # Rewritten on every start and left read-only. The old file is removed by its exact path.
    settings="$STATE/settings/$r.json"
    rm -f "$settings"
    cfg settings "$r" >"$settings" || die "could not write $settings"
    chmod 0444 "$settings"

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
      printf '"${run[@]}"%s --settings %q -n %q \\\n' "$args_q" "$settings" "$sess"
      printf '  --append-system-prompt "$(cat %q)" \\\n' "$STATE/prompts/$r.md"
      printf '  "$(cat %q)"\n' "$STATE/prompts/$r.kickoff"
    } >"$launch"
    chmod +x "$launch"

    tmux new-session -d -s "$sess" -c "$dir" -x 220 -y 50 \
      -e "TEAM_ROLE=$r" -e "TEAM_CONFIG=$CONFIG" -e "TEAM_SCRIPT=$SELF"
    apply_title "$r"
    tmux send-keys -t "=$sess:" "$launch" Enter
    echo "start  $r: $(title "$r") -> tmux session $sess ($dir)"
    started=$((started + 1))
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
  # Show the team: one iTerm tab with every running seat. A failure here never fails `up`.
  if [ "$started" -gt 0 ] && [ "$want_view" = 1 ] && [ "$VIEW_ITERM" = true ] && [ "${TEAM_VIEW:-1}" != 0 ]; then
    cmd_view || echo "warning: could not open the iTerm view (the seats are running; try: $SELF view)" >&2
  fi
}

# Make tmux set the terminal title for this seat while a client is attached, so a pane header (iTerm
# shows it) says which seat it is: "<role> | <title> | <session>". A session option, so it holds
# wherever the seat is attached. '#' starts a tmux format, hence the doubling.
apply_title() {
  local r=$1 sess str
  sess=$(session "$r")
  str="$r | $(title "$r") | $sess"
  tmux set-option -t "=$sess:" set-titles on
  tmux set-option -t "=$sess:" set-titles-string "${str//#/##}"
}

cmd_titles() {
  local r n=0
  for r in $ROLES; do
    alive "$r" || continue
    apply_title "$r"
    n=$((n + 1))
  done
  echo "set the terminal title of $n running seat(s)"
}

# Run osascript with a time limit. A macOS Automation permission prompt would otherwise leave it
# waiting forever, and `up` with it.
run_osa() {
  local out p i rc=0
  out=$(mktemp "${TMPDIR:-/tmp}/factory-osa.XXXXXX")
  osascript "$@" >"$out" 2>&1 &
  p=$!
  for i in $(seq 1 60); do
    kill -0 "$p" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$p" 2>/dev/null; then
    kill "$p" 2>/dev/null
    rm -f "$out"
    echo "osascript timed out after 30s (is a macOS Automation permission prompt waiting for iTerm?)" >&2
    return 1
  fi
  wait "$p" || rc=$?
  cat "$out"
  rm -f "$out"
  return "$rc"
}

# The AppleScript that builds the tab. Arguments: role ids, the primary first.
#   left:  the primary seat, the full height of the tab
#   right: one row per two of the other seats, rows stacked; with an odd number of seats the last
#          row is one pane across the full width
# Splits are created first and the attach commands typed afterwards, so a pane is not resized
# while its tmux client is starting. iTerm keeps same-direction splits at equal sizes.
view_script() {
  local first=$1 n r rows i a b
  shift
  n=$#
  rows=$(((n + 1) / 2))
  echo 'tell application "iTerm2"'
  echo '  if (count of windows) = 0 then'
  echo '    set w to (create window with default profile)'
  echo '  else'
  echo '    set w to current window'
  echo '    tell w to create tab with default profile'
  echo '  end if'
  echo '  tell w'
  echo '    set s0 to current session of current tab'
  if [ "$n" -gt 0 ]; then
    echo '    tell s0 to set r1 to (split vertically with default profile)'
    r=2
    while [ "$r" -le "$rows" ]; do
      echo "    tell r$((r - 1)) to set r$r to (split horizontally with default profile)"
      r=$((r + 1))
    done
    r=1
    i=1
    while [ "$i" -le "$n" ]; do
      [ $((i + 1)) -le "$n" ] && echo "    tell r$r to set c$r to (split vertically with default profile)"
      i=$((i + 2))
      r=$((r + 1))
    done
  fi
  echo "    tell s0 to write text \"$(attach_cmd "$first")\""
  r=1
  i=1
  while [ "$i" -le "$n" ]; do
    a=${!i}
    echo "    tell r$r to write text \"$(attach_cmd "$a")\""
    if [ $((i + 1)) -le "$n" ]; then
      b=$((i + 1))
      echo "    tell c$r to write text \"$(attach_cmd "${!b}")\""
    fi
    i=$((i + 2))
    r=$((r + 1))
  done
  echo '    select s0'
  echo '  end tell'
  echo '  activate'
  echo '  return id of w'
  echo 'end tell'
}

# Quoted for the user's shell: a bare =name would be expanded by zsh.
attach_cmd() { printf "tmux attach -t '=%s'" "$(session "$1")"; }

# Resize the iTerm window to the usable area of the screen it is on (not the menu bar or Dock).
# Finder's desktop bounds are no use: with two displays they describe one rectangle spanning both.
size_window() {
  local wid=$1 b l t r bt cx cy sb
  b=$(run_osa -e "tell application \"iTerm2\" to get bounds of window id $wid") || return 1
  IFS=', ' read -r l t r bt <<EOF2
$b
EOF2
  cx=$(((l + r) / 2))
  cy=$(((t + bt) / 2))
  sb=$(osascript -l JavaScript "$HERE/lib/screen_bounds.js" "$cx" "$cy") || return 1
  set -- $sb
  run_osa -e "tell application \"iTerm2\" to set bounds of window id $wid to {$1, $2, $3, $4}" >/dev/null
}

cmd_view() {
  local print=0 list="" ordered r wid
  [ "${1:-}" = --print ] && print=1
  # --print shows the layout for every role in the file, up or not (used by the tests)
  for r in $ROLES; do
    if [ $print -eq 1 ] || alive "$r"; then list="$list $r"; fi
  done
  [ -n "$list" ] || die "no seats are running; start them with: $SELF up"
  # Seats started before titles existed get theirs now (print mode touches nothing).
  if [ $print -eq 0 ]; then for r in $list; do apply_title "$r"; done; fi
  ordered=""
  case "$list " in *" $VIEW_PRIMARY "*) ordered=$VIEW_PRIMARY ;; esac
  for r in $list; do [ "$r" = "$ordered" ] || ordered="$ordered $r"; done
  # shellcheck disable=SC2086
  set -- $ordered
  if [ $print -eq 1 ]; then
    view_script "$@"
    return 0
  fi
  command -v osascript >/dev/null || die "osascript not found (the iTerm view is macOS only)"
  wid=$(run_osa -e "$(view_script "$@")") || { echo "$wid" >&2; return 1; }
  echo "opened an iTerm tab with $# seat(s): $ordered"
  if [ "$VIEW_WINDOW" = full ]; then
    size_window "$wid" || echo "warning: could not resize the iTerm window" >&2
  fi
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

# True when the bottom of the seat's screen shows a permission prompt or a menu, where the Enter
# that `say` sends would pick the highlighted answer. Only the last 15 non-blank lines are read, so
# a transcript that quotes such text further up does not block delivery for good. A false match
# fails safe: the message is not delivered.
pane_at_prompt() {
  tmux capture-pane -p -t "=$(session "$1"):" | awk 'NF' | tail -n 15 |
    grep -qE 'Do you want to (proceed|make this edit|create|allow)|❯ *[0-9]+\. |Enter to select'
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
  if pane_at_prompt "$to"; then
    echo "not delivered: $to is waiting at a permission prompt or menu; answer it yourself ($SELF attach $to)" >&2
    return 1
  fi
  buf="team-$$-$to"
  printf '%s' "$text" | tmux load-buffer -b "$buf" -
  tmux paste-buffer -p -d -b "$buf" -t "=$sess:"
  sleep 0.5
  # A prompt can appear while the text is pasted: check again, and leave the Enter unsent if one
  # has. Still open: a prompt that appears after this check, and digits in a message picking an
  # option of a menu.
  if pane_at_prompt "$to"; then
    echo "not delivered: $to showed a permission prompt or menu while the message was pasted; it is in the input box, not sent ($SELF attach $to)" >&2
    return 1
  fi
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
  view) shift; cmd_view "$@" ;;
  titles) cmd_titles ;;
  say) shift; cmd_say "$@" ;;
  attach) shift; cmd_attach "$@" ;;
  migrate) shift; cmd_migrate "$@" ;;
  down) shift; cmd_down "$@" ;;
  *) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
