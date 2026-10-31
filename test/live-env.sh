#!/usr/bin/env bash
#
# A private environment for a live test: anything that starts tmux sessions or claude, such as a
# throwaway team run with factory.sh. It keeps the test off the tmux server you work in, which is
# where a real team runs (#66).
#
#   test/live-env.sh new                 make one; prints its folder (/tmp/sf-live.XXXXXX)
#   test/live-env.sh run <dir> <cmd...>  run cmd in it: TMUX_TMPDIR=<dir>/tmux, TEAM_STATE_DIR=<dir>/state
#                                        (both absolute), TEAM_VIEW=0; TMUX, TEAM_CONFIG/ROLE/SCRIPT unset
#   test/live-env.sh down <dir>          stop its tmux server and remove the folder
#
# For example:
#   d=$(test/live-env.sh new)
#   test/live-env.sh run "$d" ./factory.sh -c /path/to/throwaway.yaml up
#   test/live-env.sh run "$d" tmux ls
#   test/live-env.sh run "$d" ./factory.sh -c /path/to/throwaway.yaml down --yes
#   test/live-env.sh down "$d"
#
# Each call is checked on its own, so it works from a fresh shell each time (as a seat's tool calls
# are). run and down refuse a folder that new did not make, or whose tmux folder resolves to /tmp,
# where tmux keeps the default server. Two things are outside its reach: a command that sets its own
# TMUX_TMPDIR, -L or -S, and worktrees a throwaway team made on a volume (down --yes keeps them).
#
# Why the folder is checked and not just exported: tmux 3.7 uses $TMUX when it is set, and falls back to
# /tmp, silently, when TMUX_TMPDIR is empty or names a folder that does not exist. A typo then reaches
# the default server.
set -euo pipefail
# With CDPATH set, cd prints the folder it goes to, which would end up in the paths worked out below.
unset CDPATH

MARK=.live-env
die() { echo "live-env: $*" >&2; exit 1; }
usage() { sed -n '7,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

# Print environment $1's folder, resolved once and physically (cd -P: as the kernel and rm see it, so
# <link>/.. is the parent of where the link leads), or stop with the reason it is not a private one.
# Only that path is used from here on: its mark, its tmux/ and, in down, rm -rf. Below it nothing may
# be a link: tmux connects through links, and a linked tmux/, tmux-<uid> or socket could reach another
# server, the default one included.
env_dir() {
  local d=$1 r tmp
  [ -n "$d" ] && [ -d "$d" ] || die "$d does not exist (make one with: $0 new)"
  tmp=$(cd -P -- /tmp && pwd -P)
  r=$(cd -P -- "$d" && pwd -P) || die "$d cannot be resolved"
  # down removes the folder, so only one shaped like new's, holding its mark, is accepted
  case $r in "$tmp"/sf-live.??????) ;; *) die "$d was not made by $0 new" ;; esac
  [ -f "$r/$MARK" ] && [ ! -L "$r/$MARK" ] || die "$d was not made by $0 new"
  if [ -L "$r/tmux" ]; then
    [ "$(cd -P -- "$r/tmux" 2>/dev/null && pwd -P)" != "$tmp" ] || die "$r/tmux resolves to $tmp, where tmux keeps the default tmux server"
    die "$r/tmux is a link: refusing, as tmux would follow it to another server"
  fi
  [ -d "$r/tmux" ] || die "$r/tmux does not exist"
  [ -O "$r/tmux" ] || die "$r/tmux is not owned by you"
  own_socket_dir "$r/tmux" >/dev/null
  echo "$r"
}

# Print the socket folder tmux uses under tmux folder $1 (tmux-<uid>), or stop if it could lead
# elsewhere. The folder may not exist yet (no server started).
own_socket_dir() {
  local u=$1/tmux-$(id -u)
  if [ -L "$u" ]; then die "$u is a link: refusing, as tmux would follow it to another server"; fi
  if [ -e "$u" ]; then
    [ -d "$u" ] || die "$u is not a folder"
    [ -O "$u" ] || die "$u is not owned by you"
    [ ! -L "$u/default" ] || die "$u/default is a link: refusing, as tmux would follow it to another server"
  fi
  echo "$u"
}

case ${1:-} in
  new)
    d=$(mktemp -d /tmp/sf-live.XXXXXX)
    mkdir "$d/tmux" "$d/state"
    chmod 700 "$d" "$d/tmux"
    echo "made by test/live-env.sh new; removed by test/live-env.sh down" > "$d/$MARK"
    echo "$d"
    ;;
  run)
    [ $# -ge 3 ] || usage
    d=$2; shift 2
    r=$(env_dir "$d")
    # Absolute, resolved folders: a relative one would point elsewhere once the command changes
    # directory, and tmux would then fall back to /tmp. A seat's own TEAM_CONFIG is dropped too, or
    # factory.sh without -c would start the seat's real team (on this private server).
    s=$(cd -P -- "$r/state" && pwd -P) || die "$r/state does not exist"
    unset TMUX TEAM_CONFIG TEAM_ROLE TEAM_SCRIPT
    export TMUX_TMPDIR=$r/tmux TEAM_STATE_DIR=$s TEAM_VIEW=0
    exec "$@"
    ;;
  down)
    [ $# -eq 2 ] || usage
    d=$2
    r=$(env_dir "$d")
    # Checked again right before the kill (own_socket_dir: a real folder of yours, no links), then -S
    # names that socket outright, so only this environment's own server can be reached.
    u=$(own_socket_dir "$r/tmux")
    if [ -S "$u/default" ]; then tmux -S "$u/default" kill-server 2>/dev/null || true; fi
    rm -rf "$r"
    ;;
  *) usage ;;
esac
