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
  local r on="not mounted" d real users
  mount | grep -qF " on $VOLUME (" && on="mounted"
  echo "team file : $CONFIG"
  echo "team      : $TEAM (tmux prefix '$PREFIX')"
  echo "repo      : $GITHUB at $REPO (origin must contain '$GITHUB', base $BASE)"
  echo "project   : $PROJECT_NAME $PROJECT_URL"
  echo "worktrees : $WT_ROOT   [volume $VOLUME: $on]"
  echo "wrapper   : ${WRAPPER:-none (claude runs directly)}"
  local plugin
  plugin=$(cfg get sessions.plugin)
  if [ -n "$plugin" ]; then echo "plugin    : $plugin (skills as /factory:<skill>)"; else echo "plugin    : off (sessions.claude.plugin: false)"; fi
  echo "gate      : $(cfg get repo.gate_summary)"
  hooks_note=$(cfg get hooks.note)
  [ -z "$hooks_note" ] || echo "hooks     : $hooks_note"
  echo "updates   : Claude Code's auto-updater is off in every seat (DISABLE_AUTOUPDATER=1); update by hand, then down and up"
  if resolve_claude; then
    echo "claude    : $CLAUDE_SRC, version $CLAUDE_VERSION; seats run the team's copy $CLAUDE_COPY$([ -x "$CLAUDE_COPY" ] || echo ' (made at the next up)')"
  else
    echo "claude    : $CLAUDE_ERR"
  fi
  # Each copy up has made, with the running seats that use it. Nothing removes them by itself.
  for d in "$STATE"/bin/claude-*; do
    [ -d "$d" ] || continue
    real=$(ruby -e 'print File.realpath(ARGV[0])' "$d/claude" 2>/dev/null)
    users=""
    for r in $ROLES; do
      if alive "$r" && [ "$(seat_exe "$r")" = "$real" ]; then users="$users $r"; fi
    done
    echo "            $d ($(cat "$d/.how" 2>/dev/null || echo '?')):${users:- no running seat}"
  done
  echo "state     : $STATE"
  printf '%-5s %-36s %-18s %-12s %-9s %-24s %-9s %-7s %s\n' ROLE SEAT SESSION MODEL EFFORT MODE MEMORY GATE WORKDIR
  for r in $ROLES; do
    printf '%-5s %-36s %-18s %-12s %-9s %-24s %-9s %-7s %s\n' "$r" "$(title "$r")" "$(session "$r")" "$(cfg role "$r" model)" \
      "$(cfg role "$r" effort)" "$(cfg role "$r" permission_mode)" "$(cfg role "$r" auto_memory)" "$(cfg role "$r" gate)" "$(workdir "$r")"
  done
  echo "(inherit = flag omitted; the seat uses model, effortLevel and permissions.defaultMode from ~/.claude/settings.json)"
  echo "(MEMORY off = Claude Code's auto memory is off in that seat; (inherit) = auto_memory: true, Claude Code's own settings decide)"
  echo
  echo "kickoff (each seat's first message; the label marks it as team configuration, not the owner's voice):"
  for r in $ROLES; do
    TEAM_SCRIPT=$SELF TEAM_LOG=$LOG cfg kickoff "$r" | sed "1s/^/  [$r] /; 2,\$s/^/    /"
  done
  echo
  cfg permissions_report
  cfg warnings
  echo "valid."
}

cmd_up() {
  local want_view=1 started=0 args="" roles r sess dir launch a args_q settings
  for a in "$@"; do
    if [ "$a" = --no-view ]; then want_view=0; else args="$args $a"; fi
  done
  roles=${args:-$ROLES}
  command -v tmux >/dev/null || die "tmux not found"
  resolve_claude || die "$CLAUDE_ERR"
  for r in $roles; do check_role "$r"; done
  for a in $(cfg get state.generated_dirs); do mkdir -p "$STATE/$a"; done
  # Progress notes (#5): seats write them, so up only makes the folder and never touches a note.
  mkdir -p "$(cfg get state.notes_dir)"
  ensure_claude_copy
  # Roles start in the order given (file order by default).
  for r in $roles; do
    sess=$(session "$r")
    if alive "$r"; then
      echo "skip   $r: session $sess already exists (left alone)"
      if [ "$(seat_exe "$r")" = REPLACED ]; then
        echo "ATTENTION $r runs a claude executable that has been replaced under it; restart it: $SELF down --yes $r, then $SELF up $r"
      fi
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
      echo '# The user config folder the seat uses is the one its protected-path rules were built for.'
      if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        printf 'export CLAUDE_CONFIG_DIR=%q\n' "$(cfg get claude.config_dir)"
      else
        echo 'unset CLAUDE_CONFIG_DIR'
      fi
      echo '# The auto-updater would reinstall claude under this running seat, after which macOS can no'
      echo '# longer tell which process it is and its privacy grants stop working (#50). Update by hand.'
      echo 'export DISABLE_AUTOUPDATER=1'
      if [ "$(cfg role "$r" auto_memory)" = off ]; then
        echo '# Auto memory is one folder for every worktree of the repo, loaded into every session there,'
        echo '# so a seat would write unreviewed notes for all of them (#71). On with auto_memory: true.'
        echo 'export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1'
      else
        # On: the seat must not inherit the variable from the tmux server's environment (a team
        # started from inside a seat, where it is set), or check's (inherit) would not be true.
        echo 'unset CLAUDE_CODE_DISABLE_AUTO_MEMORY'
      fi
      printf 'claude_bin=%q\n' "$CLAUDE_COPY"
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
    if [ "$(box_state "$r" | cut -f1)" != empty ]; then
      echo "ATTENTION $r is not at its input box (a startup dialog?): $SELF attach $r, answer it, detach (ctrl-b d)"
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
  # EXE: the claude executable a running seat runs, or REPLACED (restart it: see seat_exe).
  printf '%-5s %-36s %-18s %-6s %s  %s\n' ROLE SEAT SESSION STATE WORKDIR EXE
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
    printf '%-5s %-36s %-18s %-6s %s  %s\n' "$r" "$(title "$r")" "$sess" "$(alive "$r" && echo up || echo down)" "$where" \
      "$(if alive "$r"; then seat_exe "$r"; else echo -; fi)"
  done
}

# The claude executable seats run: the team's own copy of the shared install, made by up (#50).
# Claude Code's updater, in any session on the machine, replaces the shared file (even with the same
# version), and macOS then cannot identify a seat still running the old file, so the privacy grants
# it runs under (the worktree volume) stop working. A copy that only up writes is never replaced
# under a running seat. Sets CLAUDE_SRC (the shared file), CLAUDE_VERSION and CLAUDE_COPY, or
# CLAUDE_ERR and returns 1.
resolve_claude() {
  local c
  CLAUDE_ERR=""
  if ! c=$(command -v claude); then
    CLAUDE_ERR="claude not found on PATH (or caught in the middle of a reinstall); retry up"
    return 1
  fi
  if ! CLAUDE_SRC=$(ruby -e 'print File.realpath(ARGV[0])' "$c" 2>/dev/null) || [ ! -x "$CLAUDE_SRC" ]; then
    CLAUDE_ERR="$c does not lead to an executable (Claude Code may be in the middle of a reinstall); retry up"
    return 1
  fi
  CLAUDE_VERSION=$("$CLAUDE_SRC" --version 2>/dev/null | awk 'NR == 1 { print $1 }')
  if ! [[ $CLAUDE_VERSION =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    CLAUDE_ERR="could not read the version of $CLAUDE_SRC; retry up"
    return 1
  fi
  CLAUDE_COPY="$STATE/bin/claude-$CLAUDE_VERSION/claude"
}

# Make the copy if it is not there yet: an APFS clone (cp -c: a file of its own that shares the
# original's blocks) where the state folder is on the same file system, else a plain copy. It is
# checked before it is moved into place, so a seat never runs a partial copy. Any failure stops up:
# falling back to the shared file would bring the problem back without a sign.
ensure_claude_copy() {
  local dir tmp how
  [ -x "$CLAUDE_COPY" ] && return 0
  dir=$(dirname "$CLAUDE_COPY")
  tmp="$dir/.claude.partial.$$"
  mkdir -p "$dir" 2>/dev/null || die "could not copy claude to $dir (cannot create the folder)"
  how=clone
  if ! cp -c "$CLAUDE_SRC" "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    how=copy
    cp "$CLAUDE_SRC" "$tmp" 2>/dev/null || { rm -f "$tmp"; die "could not copy $CLAUDE_SRC to $dir (no space, or no permission?)"; }
  fi
  if [ "$(stat -f %z "$tmp")" != "$(stat -f %z "$CLAUDE_SRC")" ] ||
    [ "$("$tmp" --version 2>/dev/null | awk 'NR == 1 { print $1 }')" != "$CLAUDE_VERSION" ]; then
    rm -f "$tmp"
    die "the copy of claude in $dir does not match $CLAUDE_SRC; retry up"
  fi
  chmod 0555 "$tmp"
  # Another up may have made the copy meanwhile, and its seat may already run it: never replace it.
  # macOS mv -n exits 0 even when it does not move, so the temp file still being there is the sign.
  mv -n "$tmp" "$CLAUDE_COPY" || { rm -f "$tmp"; die "could not copy claude to $CLAUDE_COPY"; }
  if [ -e "$tmp" ]; then
    rm -f "$tmp"
    [ -x "$CLAUDE_COPY" ] || die "$CLAUDE_COPY exists but is not a runnable copy of claude; remove that exact file, then retry up"
    return 0
  fi
  echo "$how" >"$dir/.how"
  echo "  copied claude $CLAUDE_VERSION to $CLAUDE_COPY ($how)"
}

# The executable a running seat's claude process runs (its real path), REPLACED when the file at
# that path is no longer the one it runs (another file put in its place, or its folder gone), "-"
# when no claude runs in the pane, "?" when it cannot be told. lsof keeps printing the old path
# after a replacement, so the device and inode are what is compared.
seat_exe() {
  local tty pid line
  tty=$(tmux display-message -p -t "=$(session "$1"):" '#{pane_tty}' 2>/dev/null) || { echo "?"; return; }
  pid=$(ps -t "${tty#/dev/}" -o pid=,comm= | awk '$2 ~ /(^|\/)claude(\.exe)?$/ { print $1; exit }')
  [ -n "$pid" ] || { echo "-"; return; }
  # "<device, hex> <inode> <path>" of the claude executable it runs; stat gives the device in decimal.
  line=$(lsof -a -p "$pid" -d txt -FDin 2>/dev/null |
    awk '/^D/ { d = substr($0, 2) } /^i/ { i = substr($0, 2) } /^n/ { n = substr($0, 2); if (n ~ /(^|\/)claude(\.exe)?$/) { print d " " i " " n; exit } }')
  [ -n "$line" ] || { echo "?"; return; }
  set -- $line
  if [ "$(stat -f '%d %i' "${line#* * }" 2>/dev/null)" = "$(printf '%d' "$1" 2>/dev/null) $2" ]; then echo "${line#* * }"; else echo REPLACED; fi
}

# True when a claude process is attached to the seat's terminal. The pane's own command name is
# no use for this: the launcher is a bash script, so tmux reports "bash" while claude runs.
has_claude() {
  local tty
  tty=$(tmux display-message -p -t "=$(session "$1"):" '#{pane_tty}')
  ps -t "${tty#/dev/}" -o comm= | grep -qE '(^|/)claude(\.exe)?$'
}

# The state of a seat's input box. `say` types into a
# seat only when its screen ends with Claude Code's input box; everything else fails closed, so a
# dialog say has never seen is refused like a known one. The box, as Claude Code 2.1.316 draws it
# (captured 2026-10-30; test/e2e.sh's stand-in draws the same):
#   ──── <session> ───   a rule: U+2500 as wide as the pane, with the session name (claude -n) in it
#   ❯ <text>             the input: ❯ and a no-break space in column 0; more lines indented two spaces
#   ──────────────────   a plain rule
#     <footer>           0 to 8 lines indented two spaces: status line(s), the mode line, notes
# An empty box may show one dim line after the ❯: a hint ('Try "…"', "Press up to edit queued
# messages") or a suggested next prompt. A dialog (permission prompt, menu, trust or held-message
# dialog) replaces the box. A box taller than a full one scrolls: see box_full_rows. Printed as
# "<state><TAB><dim characters in the box><TAB><rows the box shows><TAB><text>". States:
#   empty       the box holds nothing, or only one line drawn entirely dim
#   text        the box holds text: typed by someone, or left by a message that was not sent
#   copy-mode   someone is scrolling the pane (capture-pane would still show the box)
#   unreadable  tmux could not read the pane
#   diff-notice the diff panel's notice pushed the end of the input box off a short pane (#95)
#   unknown     the screen does not end with the input box
box_state() {
  local sess screen
  sess="=$(session "$1"):"
  screen=$(tmux display-message -p -t "$sess" '#{pane_in_mode}' 2>/dev/null) || { printf 'unreadable\t0\t0\t\n'; return; }
  [ "$screen" = 0 ] || { printf 'copy-mode\t0\t0\t\n'; return; }
  screen=$(tmux capture-pane -e -p -t "$sess" 2>/dev/null) || { printf 'unreadable\t0\t0\t\n'; return; }
  printf '%s\n' "$screen" | LC_ALL=C awk -v name="$(session "$1")" '
    function plain(s) { gsub(/\033\[[0-9;]*m/, "", s); sub(/[ \t]+$/, "", s); return s }
    function rule(s) { return s ~ /^(─)+$/ && length(s) >= 60 }   # 20 or more, 3 bytes each
    function top(s) {                                              # a rule, or one naming this seat
      if (rule(s)) return 1
      if (s !~ /^(─)+ [^ ].* (─)+$/) return 0
      sub(/^(─)+ /, "", s); sub(/ (─)+$/, "", s); return s == name
    }
    # Counts the visible characters of s drawn dim (into dimc) and not dim (normc, spaces aside),
    # from the first one after the cursor and no-break space when skip is set. SGR 2 turns dim on, 0
    # and 22 turn it off; the colour forms 38/48/58;5;n and ;2;r;g;b are skipped, so a colour
    # index of 2 is not read as dim.
    function scan(s, skip,    c, np, ps, i, v) {
      if (skip) { i = index(s, "❯\302\240"); s = i ? substr(s, i + 5) : "" }
      while (s != "") {
        if (match(s, /^\033\[[0-9;]*m/)) {
          np = split(substr(s, 3, RLENGTH - 3), ps, ";"); if (np == 0) { isdim = 0 }
          for (i = 1; i <= np; i++) {
            v = ps[i] + 0
            if (v == 38 || v == 48 || v == 58) { i += (ps[i + 1] == 5) ? 2 : 4 }
            else if (v == 0) isdim = 0
            else if (v == 2) isdim = 1
            else if (v == 22) isdim = 0
          }
          s = substr(s, RLENGTH + 1); continue
        }
        c = substr(s, 1, 1); s = substr(s, 2)
        if (c == " " || c == "\t") continue
        if (isdim) dimc++; else normc++
      }
    }
    # The notice of the diff panel (#95), measured on 2.1.316: with the diff panel open (it opens by
    # itself once a seat has changes to show in a pane 110 columns wide or more, and the choice is
    # kept), a pane narrower than 110 columns draws this box above the input box:
    #   ╭──────…──✕─╮
    #   │ Resize your terminal to at least 110 columns to show the diff panel   │
    #   ╰──────…────╯
    # With 14 rows or more the whole input box still shows under it, and the screen reads as usual;
    # but at 14 and 15 a message of two rows or more no longer fits (qa, #109), so the advice is 16.
    # With 13 or fewer, the screen ends at the input row: no bottom rule and no footer, so nothing
    # shows where the box ends, and say cannot deliver safely. True for exactly that screen: the last
    # row is the input row (❯ in column 0) under the top rule of this seat, with the notice right above.
    # It only changes the wording of the refusal; the screen is refused either way.
    function cutnotice() {
      return n >= 5 && line[n] ~ /^❯(\302\240|$)/ && top(line[n - 1]) && line[n - 2] ~ /^╰(─)+╯$/ &&
        line[n - 3] ~ /^│ Resize your terminal to at least [0-9]+ columns to show the diff panel +│$/ &&
        line[n - 4] ~ /^╭(─)+✕─╮$/
    }
    { raw[NR] = $0; p = plain($0); if (p != "") { n++; line[n] = p; at[n] = NR } }
    END {
      j = n
      for (f = 0; j > 0 && !rule(line[j]); j--) {
        if (++f > 8 || line[j] !~ /^  [^ ]/ || line[j] ~ /❯|Enter to|Esc to/) { print (cutnotice() ? "diff-notice" : "unknown") "\t0\t0\t"; exit }
      }
      if (j < 1) { print (cutnotice() ? "diff-notice" : "unknown") "\t0\t0\t"; exit }
      for (k = j - 1; k > 0 && line[k] !~ /^❯/; k--) {
        if (j - k > 60 || line[k] !~ /^  /) { print "unknown\t0\t0\t"; exit }
      }
      if (k < 2 || line[k] !~ /^❯(\302\240|$)/ || !top(line[k - 1])) { print "unknown\t0\t0\t"; exit }
      text = substr(line[k], 4); sub(/^\302\240/, "", text)
      for (i = k + 1; i < j; i++) text = text " " substr(line[i], 3)
      # One line drawn entirely dim comes from Claude Code itself: a hint (Try "…", Press up to
      # edit queued messages) or a suggested next prompt. People and pastes cannot draw dim text, so
      # it counts as empty. Anything else is text. The middle field counts dim characters, which
      # must be 0 once our message is in the box.
      isdim = 0; dimc = 0; normc = 0
      scan(raw[at[k]], 1); for (i = k + 1; i < j; i++) scan(raw[at[i]], 0)
      rows = at[j] - at[k]                          # screen rows, a blank line in the text included
      if (text == "" || (k + 1 == j && normc == 0 && dimc > 0))
        print "empty\t" dimc "\t" rows "\t"
      else
        print "text\t" dimc "\t" rows "\t" text
    }'
}

# Why a message must not be typed into the seat now ($2 is its box state), or nothing.
box_refusal() {
  case ${2%%	*} in
    empty) ;;
    text) echo "the input box of $1 is not empty (someone typing, or an earlier message that was not sent): attach $1 and clear it ($SELF attach $1)" ;;
    copy-mode) echo "$1's pane is in copy mode (someone is scrolling): leave it with q ($SELF attach $1)" ;;
    unreadable) echo "could not read $1's screen" ;;
    diff-notice) echo "$1 shows Claude Code's diff panel notice (\"Resize your terminal to at least 110 columns to show the diff panel\") in a pane too short to show the input box under it: make the pane 110 columns wide or more (the panel then docks beside the transcript), or give it 16 rows or more, or close the diff panel in $1 ($SELF attach $1)" ;;
    *) echo "screen not recognised as ready (a permission prompt, a menu, a dialog?): attach $1 ($SELF attach $1)" ;;
  esac
}

# The most rows the input box of seat $1 shows before it scrolls. Claude Code 2.1.316 (measured
# 2026-10-30 in panes of 12 to 70 rows) grows the box to floor((pane rows - 10) / 2) rows, never
# fewer than 3, then scrolls to keep the cursor, at the end of a pasted message, in view: the first
# visible row then starts with the prompt, mid-message, and nothing marks that rows are hidden. A
# paste of more than 800 characters, or of 4 or more lines, is shown as "[Pasted text #N ...]"
# instead, so only messages below both edges scroll.
box_full_rows() {
  local h
  h=$(tmux display-message -p -t "=$(session "$1"):" '#{pane_height}' 2>/dev/null) || return 1
  h=$(( (h - 10) / 2 )); [ "$h" -lt 3 ] && h=3; echo "$h"
}

# Whether box state $2 of seat $1 shows just message $3, after its paste: text with nothing drawn
# dim, such as a suggestion left next to it, that starts with the message's "[from <role>]" (or is
# the placeholder Claude Code shows for a long paste), or else shows the message's end in a full,
# scrolled box. For the end: the visible text, all whitespace removed, is a suffix of the message,
# likewise, of at least 40 characters (whitespace is where they may differ: the box wraps at spaces
# and box_state joins rows with one), and the box shows as many rows as it can. A box only scrolls
# once full, so a shorter box that does not start with the label holds something else. Text before
# the message would show at the top and text after it at the end, so neither passes, except one gap:
# a draft typed in the moment between the empty-box check and the paste, scrolled out of view by a
# tall message, would go out with it (the README says so).
box_has_message() {
  local state dim rows vis full m v
  IFS='	' read -r state dim rows vis <<EOF
$2
EOF
  [ "$state" = text ] && [ "$dim" = 0 ] || return 1
  case $vis in "${3%%]*}]"* | "[Pasted text #"*) return 0 ;; esac
  full=$(box_full_rows "$1") && [ "$rows" = "$full" ] || return 1
  m=$(printf '%s' "$3" | LC_ALL=C tr -d '[:space:]'); v=$(printf '%s' "$vis" | LC_ALL=C tr -d '[:space:]')
  [ "${#v}" -ge 40 ] && [ "${m%"$v"}" != "$m" ]
}

# Deliver one message by bracketed paste (safe for multi-line text), then Enter. If the seat is
# mid-turn the text queues in its input box and is submitted by the Enter all the same.
send_one() {
  local to=$1 text=$2 sess buf st why
  sess=$(session "$to")
  if ! alive "$to"; then
    echo "not delivered: $to is down ($sess)" >&2
    return 1
  fi
  # Never type into a seat that is not ready to take a message. At a shell, the text would run
  # as a command. At a dialog the Enter would pick the highlighted answer.
  if ! has_claude "$to"; then
    echo "not delivered: $to has no claude process running (its pane is at a shell)" >&2
    return 1
  fi
  why=$(box_refusal "$to" "$(box_state "$to")")
  if [ -n "$why" ]; then
    echo "not delivered: $why" >&2
    return 1
  fi
  buf="team-$$-$to"
  printf '%s' "$text" | tmux load-buffer -b "$buf" -
  tmux paste-buffer -p -d -b "$buf" -t "=$sess:"
  sleep 0.5
  # Enter only when the box now holds just this message (box_has_message), so the Enter can only
  # submit the message. Otherwise a dialog came up, or the paste went nowhere. Still open: a dialog that appears between the first check and
  # the paste (the paste then lands in it; this check sees no box and sends no Enter), and one
  # that appears after this check, before the Enter.
  st=$(box_state "$to")
  if ! box_has_message "$to" "$st" "$text"; then
    why=$(box_refusal "$to" "$st")
    echo "not delivered: the input box of $to does not show the message after the paste${why:+ ($why)}; text left in input box: it goes out with the next Enter" >&2
    return 1
  fi
  tmux send-keys -t "=$sess:" Enter
}

# One messages.log field, escaped so a record stays on one line and the terminal reading the log
# with tail cannot be driven by the message (an ESC or CSI sequence could retitle it or hide lines;
# a bidi override could reorder how the line shows): backslash becomes \\, newline \n, CR \r, tab
# \t, and every other C0 control, DEL, C1 control (U+0080-U+009F) and bidi embedding, override or
# isolate (U+202A-U+202E, U+2066-U+2069) is written as its UTF-8 bytes in \xHH form. This goes by
# code point, not by byte: the check mark is E2 9C 93, and 0x9C alone is a C1 control. Text that is
# not valid UTF-8 has every byte from 0x80 up escaped instead, so a stray 0x9B cannot act as CSI.
# Reversible: printf '%b' gives back the original. --disable-gems: RubyGems is not needed, and its
# loading has failed in an unreadable working directory. If ruby fails, a fixed marker is logged
# rather than an empty field.
log_field() {
  ruby --disable-gems -e '
    s = ARGV[0].dup.force_encoding("UTF-8")
    re = s.valid_encoding? ? /[\\\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/ : (s = s.b; /[\\\x00-\x1f\x7f-\xff]/n)
    esc = { "\\" => "\\\\", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }
    print s.gsub(re) { |c| esc[c] || c.bytes.map { |b| format("\\x%02X", b) }.join }' -- "$1" || printf '%s' '<log_field failed>'
}

# The role of the seat this process runs inside, or nothing when it runs outside every seat. Used
# when TEAM_ROLE is unset (a cleared or rebuilt environment: env -i, a sanitising script), so that
# say from inside a seat is not labelled [from owner] (#41). It walks this process's ancestors and
# compares each one's controlling tty with the seats' pane ttys. The ancestors are walked, not only
# this process, because Claude Code's Bash tool runs commands in a child that has left the pane's
# terminal: that child and its descendants have no tty, but the claude process above them still
# holds its pane's tty. A pane that is not a seat's (the owner's own tmux pane) matches no seat.
# This catches mislabelling by accident only; a process that leaves both the pane's tty and its
# ancestry (setsid, then its parent exits) is not caught, and labels are not authenticated (#29).
# Fails (status 1) when ps cannot read this process, so the caller refuses instead of guessing.
caller_seat() {
  local pid=$$ ppid tty ttys="" panes sess name n=0 r
  while [ "$pid" -gt 1 ] && [ $n -lt 100 ]; do
    read -r ppid tty < <(ps -o ppid=,tty= -p "$pid" 2>/dev/null) || ppid=""
    if [ -z "$ppid" ]; then [ $n -eq 0 ] && return 1; break; fi
    case $tty in ""|"?"|"??") ;; *) ttys="$ttys ${tty#/dev/} " ;; esac
    pid=$ppid; n=$((n + 1))
  done
  [ -n "$ttys" ] || return 0
  # The tty first: a session name may hold spaces, and read gives the last field the rest of the line.
  panes=$(tmux list-panes -a -F '#{pane_tty} #{session_name}' 2>/dev/null) || return 0
  for r in $ROLES; do
    sess=$(session "$r")
    while read -r tty name; do
      [ "$name" = "$sess" ] || continue
      case $ttys in *" ${tty#/dev/} "*) echo "$r"; return 0 ;; esac
    done <<<"$panes"
  done
}

cmd_say() {
  local to=${1:-} from=${TEAM_ROLE:-} text r rc=0
  [ -n "$to" ] && [ $# -ge 2 ] || die "usage: say <role|all> <message...>"
  # Inside a seat, a message without TEAM_ROLE goes out under that seat's role, never as the owner's.
  if [ -z "$from" ]; then
    from=$(caller_seat) || die "say: cannot tell whether this runs inside a seat (ps failed); set TEAM_ROLE"
    from=${from:-owner}
  fi
  # [from launcher] marks the kickoff as team configuration; say never sends with it.
  [ "$from" = launcher ] && die "the sender 'launcher' is reserved for the kickoff (TEAM_ROLE=launcher)"
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
  # The log records what happened, not what was attempted: a refused delivery says so. One line
  # per say (all included), in the format the README documents under "The message log". $to is a
  # role id or all; $from comes from TEAM_ROLE, which nothing validates, so it is escaped too.
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(log_field "$from")" "$to" \
    "$([ "$rc" -eq 0 ] && echo delivered || echo NOT-DELIVERED)" "$(log_field "$*")" >>"$LOG"
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
