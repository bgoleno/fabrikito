# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# roles.<id>.tmpdir (#241): the path refused at load time, check's view of it, two teams' same-named seats on
# one tmux server, a role without the key, an unmounted volume, links. Leaves nothing running or on the volume.
echo "--- temp folders: the path in the team file"
TD=$VOL/$ROOT/tmp # also removed by the exit trap in test/e2e.sh
reject "a tmpdir outside storage.volume" "must be a folder inside storage.volume" "" "" ", tmpdir: /elsewhere/tv/em"
reject "a tmpdir in a folder that only starts like the volume" "must be a folder inside storage.volume" "" "" ", tmpdir: $VOL-other/tv/em"
reject "a tmpdir that .. leads off the volume" "must be a folder inside storage.volume" "" "" ", tmpdir: $VOL/../tv/em"
reject "a tmpdir under ~ when the volume is not there" "must be a folder inside storage.volume" "" "" ", tmpdir: ~/tv/em"
reject "a tmpdir that is the volume itself" "must be a folder inside storage.volume" "" "" ", tmpdir: $VOL"
reject "a relative tmpdir" "roles.em.tmpdir must be an absolute path" "" "" ", tmpdir: tmp/tv/em"
reject "a tmpdir that is not a string" "roles.em.tmpdir must be an absolute path" "" "" ", tmpdir: 5"
reject "an empty tmpdir" "roles.em.tmpdir must be an absolute path" "" "" ", tmpdir: "
reject "a tmpdir that does not name the team" "must name the team and the role as folders" "" "" ", tmpdir: $TD/em"
reject "a tmpdir that does not name the role" "must name the team and the role as folders" "" "" ", tmpdir: $TD/tv"
reject "a tmpdir with the names only inside a longer folder name" "must name the team and the role as folders" "" "" ", tmpdir: $TD/xtv/emx"
# up refuses it too, before any seat starts, and makes nothing.
# Not under $T: a run's TMPDIR may be on TEST_VOLUME, and then that path is inside the volume.
mk "" "" ", tmpdir: /tmp/sf-e2e-out-$$/tv/em"
out=$(TEAM_STATE_DIR=$T/state-td0 $S -c $T/v.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "must be a folder inside storage.volume" && [ ! -e /tmp/sf-e2e-out-$$ ] && ! tmux has-session -t '=tv-em' 2>/dev/null && ok "up refuses a tmpdir outside storage.volume, and makes and starts nothing" || { bad "up with a tmpdir outside storage.volume (rc=$rc)"; echo "$out" | tail -2; }
# check shows the folder and inherit, per role, and makes nothing.
mk "" "" ", tmpdir: $TD/tv/em"
echo '  w2: { title: W, workdir: { type: project, path: '$T'/proj }, prompt_text: "p" }' >> $T/v.yaml
out=$($S -c $T/v.yaml check 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -qxF "  em    $TD/tv/em" && echo "$out" | grep -qxF "  w2    (inherit)" && [ ! -e $TD ] && ok "check shows a role's temp folder, says (inherit) for a role without the key, and makes nothing" || { bad "check's temp folders (rc=$rc)"; echo "$out" | grep -A4 "^temp files"; ls -la $TD 2>&1; }

echo "--- temp folders: two teams on one tmux server"
# The team files differ only in their name and folders. Their w1 seats share a role name, as the two
# teams that collided did. The server's global environment says something else again, which is what a
# seat without the key inherits and a seat with it must not.
td_team() { # td_team <team> <w1's tmpdir> [line of more roles]
  cat > $T/td-$1.yaml <<Y
team: $1
repo: { path: $T/repo, github: local/origin.git }
project: { name: B, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: $1 }
roles:
  w1: { title: W, workdir: { type: project, path: $T/proj }, prompt_text: "p", tmpdir: "$2" }
${3:-}
Y
}
# Run in the seat, by the stand-in, as a command in the Bash tool is run: what the seat sees, and where
# mktemp puts a file. Waits for the third line, because the keys take a moment to reach the seat.
td_ask() { # td_ask <session> <output file>
  local i
  tmux send-keys -t "=$1:" -l "!{ echo \"\$TMPDIR\"; echo \"\$CLAUDE_CODE_TMPDIR\"; mktemp \"\$TMPDIR/x.XXXXXX\"; } > $2 2>&1"; tmux send-keys -t "=$1:" Enter
  for i in $(seq 1 100); do [ -f "$2" ] && [ "$(wc -l < "$2")" -ge 3 ] && return 0; sleep 0.1; done
  return 1
}
td_line() { sed -n "$2p" "$1"; }
# Only the entries a seat's mktemp left: <tmpdir> also holds claude/.
td_files() { find "$1" -maxdepth 1 -type f | LC_ALL=C sort; }
TA=$TD/ta/w1; TB=$TD/tb/w1; TG=$T/global-tmp
mkdir -p $TG/claude
td_team ta "$TA" '  w2: { title: X, workdir: { type: project, path: '$T'/proj }, prompt_text: "p" }'
td_team tb "$TB"
# A server to hold the global values while the two teams start, whichever sessions earlier areas left.
tmux new-session -d -s td-hold
td_tmpdir_was=$(tmux show-environment -g TMPDIR 2>/dev/null)
tmux set-environment -g TMPDIR $TG; tmux set-environment -g CLAUDE_CODE_TMPDIR $TG/claude
TEAM_STATE_DIR=$T/state-ta $S -c $T/td-ta.yaml up --no-view >$T/td-ta.out 2>&1; rca=$?
TEAM_STATE_DIR=$T/state-tb $S -c $T/td-tb.yaml up --no-view >$T/td-tb.out 2>&1; rcb=$?
[ $rca -eq 0 ] && [ $rcb -eq 0 ] && tmux has-session -t '=ta-w1' && tmux has-session -t '=ta-w2' && tmux has-session -t '=tb-w1' && ok "two teams with a role of one name and different tmpdir values start on one tmux server" || { bad "two teams start (rc=$rca,$rcb)"; tail -3 $T/td-ta.out $T/td-tb.out; }
grep -qxF "export TMPDIR=$TA" $T/state-ta/launch/w1.sh && grep -qxF "export CLAUDE_CODE_TMPDIR=$TA/claude" $T/state-ta/launch/w1.sh && ok "tmpdir: the launch script exports TMPDIR and CLAUDE_CODE_TMPDIR from the one key" || { bad "tmpdir: launch script"; cat $T/state-ta/launch/w1.sh; }
[ "$(stat -f %Lp $TA)" = 700 ] && [ "$(stat -f %Lp $TA/claude)" = 700 ] && ok "up makes the temp folder and its claude/ owner-only" || { bad "mode of the temp folder"; ls -ld $TA $TA/claude; }
[ -z "$(find $TA $TB -name '.write-test*')" ] && ok "up leaves no write-test file in a temp folder" || { bad "a write-test file was left"; ls -la $TA $TB; }
td_ask ta-w1 $T/td-ta-w1.out; td_ask tb-w1 $T/td-tb-w1.out; td_ask ta-w2 $T/td-ta-w2.out
[ "$(td_line $T/td-ta-w1.out 1)" = "$TA" ] && [ "$(td_line $T/td-ta-w1.out 2)" = "$TA/claude" ] && ok "a seat with tmpdir has both variables as set, whatever the tmux server's global environment says" || { bad "the variables in ta's w1"; cat $T/td-ta-w1.out; }
[ "$(td_line $T/td-tb-w1.out 1)" = "$TB" ] && [ "$(td_line $T/td-tb-w1.out 2)" = "$TB/claude" ] && ok "the other team's same-named seat has its own values" || { bad "the variables in tb's w1"; cat $T/td-tb-w1.out; }
fa=$(td_line $T/td-ta-w1.out 3); fb=$(td_line $T/td-tb-w1.out 3)
[ "$(td_files $TA)" = "$fa" ] && [ "$(dirname "$fa")" = "$TA" ] && ok "mktemp in a seat creates its file in that seat's temp folder" || { bad "mktemp in ta's w1"; ls -la $TA; cat $T/td-ta-w1.out; }
[ "$(td_files $TB)" = "$fb" ] && [ "$fa" != "$fb" ] && ok "a file written by one team's seat does not land in the other team's same-named seat's folder" || { bad "two teams' folders"; ls -la $TA $TB; }
# A role with no key: nothing in its launch script about temp files, and the inherited values in the seat.
! grep -qE "TMPDIR" $T/state-ta/launch/w2.sh && [ "$(td_line $T/td-ta-w2.out 1)" = "$TG" ] && [ "$(td_line $T/td-ta-w2.out 2)" = "$TG/claude" ] && [ "$(dirname "$(td_line $T/td-ta-w2.out 3)")" = "$TG" ] && ok "a role without the key inherits its temp settings, as before" || { bad "the seat without the key"; grep -n TMPDIR $T/state-ta/launch/w2.sh; cat $T/td-ta-w2.out; }
out=$(TEAM_STATE_DIR=$T/state-ta $S -c $T/td-ta.yaml check 2>&1)
echo "$out" | grep -qxF "  w1    $TA" && echo "$out" | grep -qxF "  w2    (inherit)" && ok "check shows the running team's folders" || { bad "check on the running team"; echo "$out" | grep -A3 "^temp files"; }
# up on a running seat leaves it alone: what it would do to the folder waits for the seat's next start.
chmod 755 $TA
out=$(TEAM_STATE_DIR=$T/state-ta $S -c $T/td-ta.yaml up --no-view w1 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -qF "skip   w1" && [ "$(stat -f %Lp $TA)" = 755 ] && ok "up skips a running seat without touching its temp folder" || { bad "up on a running seat (rc=$rc)"; echo "$out" | tail -2; ls -ld $TA; }
TEAM_STATE_DIR=$T/state-ta $S -c $T/td-ta.yaml down --yes >/dev/null 2>&1; TEAM_STATE_DIR=$T/state-tb $S -c $T/td-tb.yaml down --yes >/dev/null 2>&1
tmux set-environment -gu CLAUDE_CODE_TMPDIR
case $td_tmpdir_was in TMPDIR=*) tmux set-environment -g TMPDIR "${td_tmpdir_was#TMPDIR=}" ;; *) tmux set-environment -gu TMPDIR ;; esac
tmux kill-session -t '=td-hold'
# An existing folder gets the mode too, once the seat starts again.
out=$(TEAM_STATE_DIR=$T/state-ta $S -c $T/td-ta.yaml up --no-view w1 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(stat -f %Lp $TA)" = 700 ] && [ "$(td_files $TA)" = "$fa" ] && ok "up gives an existing temp folder the mode, and keeps what is in it" || { bad "up on an existing temp folder (rc=$rc)"; echo "$out" | tail -2; ls -la $TA; }
TEAM_STATE_DIR=$T/state-ta $S -c $T/td-ta.yaml down --yes >/dev/null 2>&1

echo "--- temp folders: where the path really leads"
# The mount point of a volume that is not mounted: a plain folder, so a mkdir -p there would work and
# land on whatever disk holds the folder. That is the failure the mount check is for.
mkdir -p $T/td-unmounted
sed "s#volume: $VOL#volume: $T/td-unmounted#; s#tmpdir: \"$TA\"#tmpdir: \"$T/td-unmounted/tmp/ta/w1\"#" $T/td-ta.yaml > $T/td-un.yaml
out=$(TEAM_STATE_DIR=$T/state-tu $S -c $T/td-un.yaml up --no-view w1 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "is not mounted; refusing to put temp files on another disk" && [ -z "$(ls -A $T/td-unmounted)" ] && ! tmux has-session -t '=ta-w1' 2>/dev/null && ok "up refuses a tmpdir on a volume that is not mounted, creates no folder under the mount point and starts no seat" || { bad "up with the volume not mounted (rc=$rc)"; echo "$out" | tail -2; ls -la $T/td-unmounted; }
out=$(TEAM_STATE_DIR=$T/state-tu $S -c $T/td-un.yaml up --no-view w2 2>&1); rc=$?
[ $rc -eq 0 ] && tmux has-session -t '=ta-w2' 2>/dev/null && ok "a role without the key still starts with the volume not mounted" || { bad "up of a role without the key, volume not mounted (rc=$rc)"; echo "$out" | tail -2; }
TEAM_STATE_DIR=$T/state-tu $S -c $T/td-un.yaml down --yes w2 >/dev/null 2>&1
out=$($S -c $T/td-un.yaml check 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -qF "not mounted" && echo "$out" | grep -qxF "  w1    $T/td-unmounted/tmp/ta/w1" && [ -z "$(ls -A $T/td-unmounted)" ] && ok "check on an unmounted volume shows the folder, says not mounted and creates nothing" || { bad "check with the volume not mounted (rc=$rc)"; echo "$out" | tail -2; }
# A symlink on the volume that leads off it. /tmp is on another volume than any TEST_VOLUME that is a
# real mount. A check of the path as written passes this; a mkdir -p would write through the link.
TOFF=sf-e2e-off-$$
mkdir -p $TD && ln -s /tmp $TD/lnk
td_team ta "$TD/lnk/$TOFF/ta/w1"
out=$($S -c $T/td-ta.yaml check 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "not on the storage volume" && ok "check refuses a tmpdir that a symlink leads off the volume" || { bad "check with a symlink off the volume (rc=$rc)"; echo "$out" | tail -2; }
out=$(TEAM_STATE_DIR=$T/state-tu $S -c $T/td-ta.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "not on the storage volume" && [ ! -e /tmp/$TOFF ] && ! tmux has-session -t '=ta-w1' 2>/dev/null && ok "up refuses a tmpdir that a symlink leads off the volume, and writes nothing through it" || { bad "up with a symlink off the volume (rc=$rc)"; echo "$out" | tail -2; rm -rf "/tmp/$TOFF"; }
rm $TD/lnk
# A link at the folder or at its claude/, even one that stays on the volume: mkdir -p and chmod follow it.
TL=$TD/ta/w1; rm -rf "$TL"; mkdir -p $TD/keep $TD/ta; chmod 755 $TD/keep
ln -s $TD/keep $TL
td_team ta "$TL"
out=$(TEAM_STATE_DIR=$T/state-tu $S -c $T/td-ta.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "$TL is not a real folder" && [ "$(stat -f %Lp $TD/keep)" = 755 ] && [ ! -e $TD/keep/claude ] && ok "up refuses a symlink at the temp folder and leaves what it points at alone" || { bad "up with a link at the temp folder (rc=$rc)"; echo "$out" | tail -2; }
rm $TL; mkdir -p $TL; ln -s $TD/keep $TL/claude
out=$(TEAM_STATE_DIR=$T/state-tu $S -c $T/td-ta.yaml up --no-view 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "$TL/claude is not a real folder" && [ "$(stat -f %Lp $TD/keep)" = 755 ] && ok "up refuses a symlink at the temp folder's claude/ and leaves what it points at alone" || { bad "up with a link at claude/ (rc=$rc)"; echo "$out" | tail -2; }
out=$($S -c $T/td-ta.yaml check 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -qF "$TL/claude is not a real folder" && ok "check refuses a symlink at the temp folder's claude/" || { bad "check with a link at claude/ (rc=$rc)"; echo "$out" | tail -2; }
rm $TL/claude; rm -rf "$TD"; ! tmux has-session -t '=ta-w1' 2>/dev/null || tmux kill-session -t '=ta-w1'

echo "--- temp folders: repo.bootstrap runs with the role's TMPDIR"
# An install writes temp files, and with the caller's TMPDIR they could land on the internal disk (#253).
# A role with tmpdir gets its folder as TMPDIR for the bootstrap; a role without keeps the caller's.
# The caller's TMPDIR here is a folder of its own, so a file in the role's folder cannot be the caller's.
printf '#!/bin/sh\necho "tmpdir=${TMPDIR-unset}" >> "$1"\n[ -z "$TMPDIR" ] || touch "$TMPDIR/boot-made"\n' > $T/bin/boot-tmp; chmod +x $T/bin/boot-tmp
mkdir -p $T/calltmp; rm -f $T/boot-tmp.log
REPO_EXTRA="bootstrap: \"$T/bin/boot-tmp $T/boot-tmp.log\"" mk "wrapper: $T/bin/wrap"
echo "  w9: { title: T, workdir: { type: worktree }, prompt_text: \"p\", tmpdir: \"$TD/tv/w9\" }" >> $T/v.yaml
echo "  w10: { title: N, workdir: { type: worktree }, prompt_text: \"p\" }" >> $T/v.yaml
out=$(env TMPDIR=$T/calltmp TEAM_STATE_DIR=$T/state-bt $S -c $T/v.yaml up --no-view w9 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(cat $T/boot-tmp.log 2>/dev/null)" = "tmpdir=$TD/tv/w9" ] && [ -e $TD/tv/w9/boot-made ] && [ ! -e $T/calltmp/boot-made ] \
  && ok "repo.bootstrap of a role with tmpdir runs with that folder as TMPDIR, and its temp file lands there" || { bad "bootstrap TMPDIR for a role with tmpdir (rc=$rc)"; cat $T/boot-tmp.log 2>&1; echo "$out" | tail -3; }
TEAM_STATE_DIR=$T/state-bt $S -c $T/v.yaml down --yes w9 >/dev/null 2>&1; git -C $T/repo worktree remove --force $VOL/$ROOT/team-w9 2>/dev/null
rm -f $T/boot-tmp.log
out=$(env TMPDIR=$T/calltmp TEAM_STATE_DIR=$T/state-bt $S -c $T/v.yaml up --no-view w10 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(cat $T/boot-tmp.log 2>/dev/null)" = "tmpdir=$T/calltmp" ] && [ -e $T/calltmp/boot-made ] \
  && ok "repo.bootstrap of a role without tmpdir still runs with the caller's TMPDIR" || { bad "bootstrap TMPDIR for a role without tmpdir (rc=$rc)"; cat $T/boot-tmp.log 2>&1; echo "$out" | tail -3; }
TEAM_STATE_DIR=$T/state-bt $S -c $T/v.yaml down --yes w10 >/dev/null 2>&1; git -C $T/repo worktree remove --force $VOL/$ROOT/team-w10 2>/dev/null
rm -rf "$TD" $T/calltmp; ! tmux has-session -t '=tv-w9' 2>/dev/null || tmux kill-session -t '=tv-w9'; ! tmux has-session -t '=tv-w10' 2>/dev/null || tmux kill-session -t '=tv-w10'

echo "--- temp folders: the rest of the issue"
# A bare mktemp was seen to ignore TMPDIR on macOS: each one in fabrikito that makes a file has a template.
m=$(grep -n '\$(mktemp' $S | grep -vE '\$\(mktemp "[^"]*\.X{6,}"')
[ -z "$m" ] && grep -q '\$(mktemp' $S && ok "every mktemp in fabrikito has an explicit template" || { bad "a mktemp in fabrikito with no template"; echo "$m"; }
tp=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/team.yaml render em)
echo "$tp" | grep -qF 'mktemp "$TMPDIR/name.XXXXXX"' && echo "$tp" | grep -qF "EPERM there" && echo "$tp" | grep -qF "never work" && ok "a seat's prompt says where temp files go and that EPERM is reported, not worked around" || { bad "the prompt on temp files"; echo "$tp" | grep -n -i "temp\|EPERM"; }

echo "--- two team files with one session prefix: a command acts only on its own team's sessions"
# Two team files that share sessions.prefix give the same session names on one tmux server. up stores
# in each session it starts the real path of its state folder and the team's repository, and every
# command that reaches a seat compares them with its own: a session whose state folder or repository
# is another one is another team's. The second file's up does not take such a seat for its own, its
# down stops none, and its say, flush, titles, attach and view leave them alone, each naming the
# session, the value that differs and the file that started the session. The path of the team file
# does not decide: two copies of one file with one state folder are one team (a team pinned to a
# release). Where a file lies makes no difference on a private server, so all are in the scratch
# folder. oa is started by the first file only.
own_team() { # own_team <file> <team name> <first word of its seats' titles> [<repo.github>]
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<Y
team: $2
repo: { path: $T/repo, github: ${4:-local/origin.git} }
project: { name: B, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: ow, claude: { wrapper: $T/bin/wrap } }
roles:
  oa: { title: $3 A, workdir: { type: project, path: $T/proj }, prompt_text: "oa" }
  ob: { title: $3 B, workdir: { type: project, path: $T/proj }, prompt_text: "ob" }
Y
}
OA=$T/own/a/team.yaml; OB=$T/own/b/team.yaml
own_team $OA toa Seat; own_team $OB tob Other
oa() { TEAM_STATE_DIR=$T/own/sa "$@"; }; ob() { TEAM_STATE_DIR=$T/own/sb "$@"; }
oa $S -c $OA up --no-view oa >/dev/null 2>&1
own_seat() { tmux list-sessions -F '#{session_name} #{session_created} #{pane_pid}' 2>/dev/null | grep '^ow-'; tmux show-options -v -t '=ow-oa:' set-titles-string 2>/dev/null; cat $T/keys-oa.log 2>/dev/null | cksum; }
own_before=$(own_seat)
echo "$own_before" | grep -q '^ow-oa ' && ! echo "$own_before" | grep -q '^ow-ob ' || bad "test setup: the first team's oa did not start alone ($own_before)"
own_real=$(cd $T/own && pwd -P)
# own_refused <what> <command...>: the command, run as the team of $own_run, fails, names the session and
# the file that started it ($own_file), and every ow- seat is as it was (same sessions and pane processes,
# same title, no key typed into oa). own_last is what the command printed.
own_run=ob; own_file=$OA
own_refused() { local what=$1 out rc; shift
  out=$($own_run env TEAM_ROLE=ob "$@" 2>&1 </dev/null); rc=$?; own_last=$out
  if [ $rc -ne 0 ] && echo "$out" | grep -qF "ow-oa" && echo "$out" | grep -qF "$own_file" && [ "$(own_seat)" = "$own_before" ]; then ok "$what"
  else bad "$what (rc=$rc)"; echo "$out" | tail -3; own_seat; fi; }
own_refused "up for a second team file with the first one's prefix fails, naming the session and the file that started it" $S -c $OB up --no-view
[ ! -e $T/own/sb/settings ] && ! tmux has-session -t '=ow-ob' 2>/dev/null && ok "that up makes nothing in its state folder and starts none of its own seats" || { bad "the refused up made or started something"; ls $T/own/sb 2>&1; }
echo "$own_last" | grep -qF "its state folder is $own_real/sa, this team's is $own_real/sb" && ! echo "$own_last" | grep -qF "its repository is" \
  && ok "the refusal names the value that differs, the session's and this team's: the state folder, and not the repository, which is the same" || { bad "the refusal does not name the state folder as the value that differs"; echo "$own_last" | tail -2; }
# One role named, and the view on: nothing of the second file's is started beside the first one's seat
# (the view, which shows every running seat, would refuse only after the seat was started).
own_refused "up <role> for a second team file, for a role whose session is free, starts nothing beside the first one's seat" env TEAM_VIEW=1 $S -c $OB up ob
if tmux has-session -t '=ow-ob' 2>/dev/null; then tmux kill-session -t '=ow-ob'; sleep 1; fi
own_refused "say from the second team file puts nothing into the first one's seat" $S -c $OB say oa "from the other file OWN-MARK"
grep -q "NOT-DELIVERED" $T/own/sb/messages.log 2>/dev/null && ! tmux capture-pane -p -t '=ow-oa:' | grep -q "OWN-MARK" && ok "that say is logged NOT-DELIVERED in its own team's log, and nothing shows in the seat" || { bad "the refused say"; cat $T/own/sb/messages.log 2>&1 | tail -2; }
own_refused "say all from the second team file puts nothing into the first one's seat" $S -c $OB say all "to all from the other file OWN-MARK"
own_refused "flush from the second team file sends no key to the first one's seat" $S -c $OB flush oa
own_refused "titles from the second team file leaves the first one's seat's title" $S -c $OB titles
own_refused "attach from the second team file does not attach to the first one's seat" $S -c $OB attach oa
own_n=$(cat $T/osascript.log 2>/dev/null | wc -l | tr -d ' ')
own_refused "view from the second team file opens no view of the first one's seat" env TEAM_VIEW=1 $S -c $OB view
[ "$(cat $T/osascript.log 2>/dev/null | wc -l | tr -d ' ')" = "$own_n" ] || bad "the refused view called osascript"
own_refused "down without --yes from the second team file lists none of the first one's seats as its own" $S -c $OB down
own_refused "down --yes from the second team file stops none of the first one's seats" $S -c $OB down --yes
# --default-socket lets a team file outside teams/ reach the default server. It says nothing about whose
# the seats there are: with it, another team's file still stops nothing and delivers nothing.
own_refused "down --default-socket --yes from the second team file stops none of the first one's seats" $S -c $OB down --default-socket --yes
echo "$own_last" | grep -qF "its state folder is $own_real/sa" || bad "down --default-socket --yes does not name the value that differs"
own_refused "say --default-socket from the second team file puts nothing into the first one's seat" $S -c $OB say --default-socket oa "with the flag OWN-MARK"
echo "$own_last" | grep -qF "its state folder is $own_real/sa" && ! tmux capture-pane -p -t '=ow-oa:' | grep -q "OWN-MARK" || bad "say --default-socket does not name the value that differs, or its text shows in the seat"
# status only reads, so it is not refused: it says under its table that the session is another team's.
own_out=$(ob $S -c $OB status 2>&1)
echo "$own_out" | grep -q "^NOTICE oa: session ow-oa is another team's" && ! echo "$own_out" | grep -q "^NOTICE ob" && ! oa $S -c $OA status 2>&1 | grep -q "^NOTICE" \
  && ok "status from the second team file has a notice that the session with its seat's name is another team's, and the first file's status has none" || { bad "status and another team's session"; echo "$own_out" | tail -3; }
# A say run inside the first team's seat with the second team's file and no TEAM_ROLE gets no label from
# that session: it is not the second team's oa, whatever its name (this types into oa, so it comes after
# the cases that compare its keys).
own_n=$(cat $T/own/sb/messages.log 2>/dev/null | wc -l | tr -d ' ')
tmux send-keys -t '=ow-oa:' -l "!env -u TEAM_ROLE TEAM_STATE_DIR=$T/own/sb $S -c $OB say ob 'from inside OWN-IN' > $T/own-in.out 2>&1"; tmux send-keys -t '=ow-oa:' Enter
for own_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ "$(cat $T/own/sb/messages.log 2>/dev/null | wc -l | tr -d ' ')" -gt "$own_n" ] && break; sleep 0.5; done; sleep 1
[ "$(tail -n +$((own_n + 1)) $T/own/sb/messages.log | cut -f2-4)" = "?	ob	NOT-DELIVERED" ] && grep -q "another team's" $T/own-in.out \
  && ok "say with TEAM_ROLE unset inside another team's session that has a seat's name is refused, not labelled as that seat" || { bad "say from inside another team's session with a seat's name"; tail -n +$((own_n + 1)) $T/own/sb/messages.log | cut -c1-200; cat $T/own-in.out 2>&1 | tail -2; }
# The first file still reaches its own seat: by its path, and by another spelling of it (a link to its folder).
ln -s $T/own/a $T/own/alink
oa env TEAM_ROLE=ob $S -c $OA say oa "from its own file OWN-OK-1" >/dev/null 2>&1; rc1=$?
oa env TEAM_ROLE=ob $S -c $T/own/alink/team.yaml say oa "through a link OWN-OK-2" >/dev/null 2>&1; rc2=$?; sleep 1
[ $rc1 = 0 ] && [ $rc2 = 0 ] && keytext $T/keys-oa.log | grep -q "OWN-OK-1" && keytext $T/keys-oa.log | grep -q "OWN-OK-2" && ok "the team file that started a seat still reaches it, by its path and through a link to its folder" || { bad "say from the seat's own team file (rc=$rc1,$rc2)"; }
# A state folder that was moved while the seat ran: the refusal gives the command that hands the session
# over, with the value that decides, and that works.
own_out=$(ob env TEAM_ROLE=ob $S -c $OB say oa "x" 2>&1)
echo "$own_out" | grep -qF "tmux set-environment -t '=ow-oa' TEAM_STATE_REAL $own_real/sb" && tmux set-environment -t '=ow-oa' TEAM_STATE_REAL $own_real/sb \
  && ob env TEAM_ROLE=ob $S -c $OB say oa "after the handover OWN-OK-3" >/dev/null 2>&1 && sleep 1 && keytext $T/keys-oa.log | grep -q "OWN-OK-3" \
  && ok "the refusal names the tmux command that hands a session over, with the value that differs, and after it the team reaches the seat" || { bad "handing a session over to another team"; echo "$own_out" | tail -2; }
ob $S -c $OB down --yes >/dev/null 2>&1
! tmux has-session -t '=ow-oa' 2>/dev/null && ok "down --yes from the team a session belongs to stops it" || { bad "down from the owning team left the seat"; tmux kill-session -t '=ow-oa' 2>/dev/null; }

echo "--- two copies of one team file with one state folder are one team (a team pinned to a release)"
# A pinned team runs from one copy of its team file per release checkout, all with one state folder, and
# its upgrade stops and starts each seat with the new copy while the old copy's seats run. The second
# copy is the team: its say reaches a seat the first started, its down <role> and up <role> restart it
# beside the first copy's other seat, and the seats of both message each other.
P1=$T/own/p1/team.yaml; P2=$T/own/p2/team.yaml
own_team $P1 top Seat; own_team $P2 top Seat
op() { TEAM_STATE_DIR=$T/own/sp "$@"; }
op $S -c $P1 up --no-view >/dev/null 2>&1; sleep 1
tmux has-session -t '=ow-oa' 2>/dev/null && tmux has-session -t '=ow-ob' 2>/dev/null || bad "test setup: the first copy's two seats did not start"
op env TEAM_ROLE=ob $S -c $P2 say oa "new copy to old seat PIN-1" >/dev/null 2>&1; rc1=$?; sleep 1
[ $rc1 = 0 ] && keytext $T/keys-oa.log | grep -q "PIN-1" && ok "say from a second copy of the team file, with the same state folder, reaches a seat the first copy started" || bad "say from the second copy to the first copy's seat (rc=$rc1)"
own_pid=$(tmux list-sessions -F '#{session_name} #{pane_pid}' | grep '^ow-ob ')
own_out=$(op $S -c $P2 down --yes oa 2>&1); rc1=$?; tmux has-session -t '=ow-oa' 2>/dev/null; rc2=$?
own_out="$own_out
$(op $S -c $P2 up --no-view oa 2>&1)"; rc3=$?; sleep 1
[ $rc1 = 0 ] && [ $rc2 != 0 ] && [ $rc3 = 0 ] && [ "$(tmux show-environment -t '=ow-oa' TEAM_CONFIG 2>/dev/null)" = "TEAM_CONFIG=$P2" ] && [ "$(tmux list-sessions -F '#{session_name} #{pane_pid}' | grep '^ow-ob ')" = "$own_pid" ] \
  && ok "down <role> and up <role> from the second copy stop and start a seat the first copy started, beside the first copy's other seat" || { bad "the second copy's down and up of one seat (rc=$rc1,$rc2,$rc3)"; echo "$own_out" | tail -4; }
op env TEAM_ROLE=ob $S -c $P1 say oa "old copy to new seat PIN-2" >/dev/null 2>&1; rc1=$?
op env TEAM_ROLE=oa $S -c $P2 say ob "new copy to old seat PIN-3" >/dev/null 2>&1; rc2=$?; sleep 1
[ $rc1 = 0 ] && [ $rc2 = 0 ] && keytext $T/keys-oa.log | grep -q "PIN-2" && keytext $T/keys-ob.log | grep -q "PIN-3" && ok "say goes through in both directions between the seats the two copies started" || bad "say between the two copies' seats (rc=$rc1,$rc2)"
# A team file copied for another project, with team: and the prefix left as they were: the same state
# folder and session names, another repository. It is another team: its up starts nothing (ob is down,
# so there is a seat it would start), its down stops nothing and its say delivers nothing.
G=$T/own/g/team.yaml; own_team $G top Seat local/other.git
op $S -c $P1 down --yes ob >/dev/null 2>&1; sleep 1
own_before=$(own_seat); own_run=op; own_file=$P2
echo "$own_before" | grep -q '^ow-oa ' && ! echo "$own_before" | grep -q '^ow-ob ' || bad "test setup: oa alone was to be running for the copied file's cases ($own_before)"
own_refused "up for a team file with the first one's state folder and prefix and another repository fails and starts nothing" $S -c $G up --no-view
echo "$own_last" | grep -qF "its repository is local/origin.git, this team's is local/other.git" && ! echo "$own_last" | grep -qF "its state folder is" \
  && ok "that refusal names the value that differs: the repository, and not the state folder, which is the same" || { bad "the refusal does not name the repository as the value that differs"; echo "$own_last" | tail -2; }
own_refused "down --yes for a team file with the first one's state folder and another repository stops nothing" $S -c $G down --yes
own_refused "say for a team file with the first one's state folder and another repository delivers nothing" $S -c $G say oa "from the copied file OWN-MARK-G"
tmux capture-pane -p -t '=ow-oa:' | grep -q "OWN-MARK-G" && bad "the copied file's say shows in the seat"
op $S -c $P2 down --yes >/dev/null 2>&1
! tmux has-session -t '=ow-oa' 2>/dev/null || { bad "the pinned team's down left a seat"; tmux kill-session -t '=ow-oa' 2>/dev/null; }
e2e_end=tmpdir # the last line: test/e2e.sh checks that the file ran to here
