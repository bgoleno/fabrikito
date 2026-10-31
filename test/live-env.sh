#!/usr/bin/env bash
#
# A private environment for a live test: anything that starts tmux sessions or claude, such as a
# throwaway team run with factory.sh. It keeps the test off the tmux server you work in, which is
# where a real team runs (#66).
#
#   test/live-env.sh new                 make one; prints its folder (/tmp/sf-live.XXXXXX)
#   test/live-env.sh run <dir> <cmd...>  run cmd in it: TMUX unset, TMUX_TMPDIR=<dir>/tmux,
#                                        TEAM_STATE_DIR=<dir>/state, TEAM_VIEW=0 (no iTerm tab)
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

MARK=.live-env
die() { echo "live-env: $*" >&2; exit 1; }
usage() { sed -n '7,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

# Print the resolved tmux folder of environment $1, or stop with the reason it is not private.
private_tmux() {
  local d=$1 t tmp
  [ -n "$d" ] && [ -d "$d" ] || die "$d does not exist (make one with: $0 new)"
  tmp=$(cd /tmp && pwd -P)
  # down removes the folder, so only one shaped like new's, holding its mark, is accepted
  case $(cd "$d" && pwd -P) in "$tmp"/sf-live.??????) ;; *) die "$d was not made by $0 new" ;; esac
  [ -f "$d/$MARK" ] || die "$d was not made by $0 new"
  t=$(cd "$d/tmux" 2>/dev/null && pwd -P) || die "$d/tmux does not exist"
  [ "$t" != "$tmp" ] || die "$d/tmux resolves to $tmp, where tmux keeps the default tmux server"
  echo "$t"
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
    private_tmux "$d" >/dev/null
    unset TMUX
    export TMUX_TMPDIR=$d/tmux TEAM_STATE_DIR=$d/state TEAM_VIEW=0
    exec "$@"
    ;;
  down)
    [ $# -eq 2 ] || usage
    d=$2
    t=$(private_tmux "$d")
    # -S names the socket outright, so this can only reach this environment's server.
    tmux -S "$t/tmux-$(id -u)/default" kill-server 2>/dev/null || true
    rm -rf "$d"
    ;;
  *) usage ;;
esac
