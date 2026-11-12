# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# The iTerm view script (generated only). Appends w3 to w5 to team.yaml, which later areas see.
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
# The view attaches on the tmux server the launcher checked. A pane of the view is a new shell in iTerm,
# with its own environment: a bare `tmux attach` there would pick its server from that, not from what view
# (and its refusal of the default server) saw. So each attach command names the socket outright.
vsock="$(cd $T && pwd -P)/tmux/tmux-$(id -u)/default"
[ "$(echo "$v6" | grep -c 'write text')" = 6 ] && [ "$(echo "$v6" | grep -cF "write text \"tmux -S '$vsock' attach -t '=tt-")" = 6 ] \
  && ok "view: every attach command names the socket of the server view runs against (TMUX_TMPDIR)" || { bad "view: attach commands do not name the server's socket"; echo "$v6" | grep 'write text' | head -2; }
mkdir -p $T/vsk
vt=$(TMUX="$T/vsk/other,4242,0" $S -c $T/team.yaml view --print)
[ "$(echo "$vt" | grep -c 'write text')" = 6 ] && [ "$(echo "$vt" | grep -cF "write text \"tmux -S '$(cd $T && pwd -P)/vsk/other' attach -t '=tt-")" = 6 ] \
  && ok "view: with TMUX set, every attach command names the socket TMUX names" || { bad "view: attach commands with TMUX set"; echo "$vt" | grep 'write text' | head -2; }
# The socket's path is quoted for the shell the pane runs and for the AppleScript string it is written in:
# read back the way iTerm and then the shell would, it is one word, the path as it is.
vq="$T/vsk/it's \"q\" \\ \$(touch $T/vsk/ran)"
vt=$(TMUX="$vq,4242,0" $S -c $T/team.yaml view --print | grep -m1 'write text')
vcmd=$(printf '%s' "$vt" | ruby -e 's = STDIN.read; m = s.match(/write text "((?:[^"\\]|\\.)*)"\s*\z/m); print(m ? m[1].gsub(/\\(.)/m) { $1 } : "no string")')
( eval "set -- $vcmd"; [ $# = 6 ] && [ "$1 $2 $4 $5" = "tmux -S attach -t" ] && [ "$3" = "$(cd $T && pwd -P)/vsk/it's \"q\" \\ \$(touch $T/vsk/ran)" ] ) 2>/dev/null && [ ! -e $T/vsk/ran ] \
  && ok "view: a socket path with quotes, a backslash and a command substitution is one quoted word in the attach command" || { bad "view: quoting of the socket path"; printf '%s\n' "$vt"; }
e2e_end=view # the last line: test/e2e.sh checks that the file ran to here
