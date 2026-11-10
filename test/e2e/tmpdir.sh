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

echo "--- temp folders: an Edit allow on the seat's own folder (#252)"
# In a mode that prompts, a Write in the seat's own temp folder (outside its working directory) would
# wait for a human. The seat gets an Edit allow on that folder only: none on another role's or
# team's folder, none without a tmpdir, and check shows it.
tdz_team() { td_team tz "$TD/tz/w1" "  w2: { title: W, workdir: { type: project, path: $T/proj }, prompt_text: \"p\", tmpdir: \"$TD/tz/w2\" }
  w3: { title: W, workdir: { type: project, path: $T/proj }, prompt_text: \"p\" }"; }
tdz_team
tdz_allow() { TEAM_STATE_DIR=$T/state-tz ruby $SRC/lib/team_config.rb $T/td-tz.yaml settings $1 | ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("permissions","allow").grep(/tmp\/tz/)'; }
a1=$(tdz_allow w1); a3=$(tdz_allow w3)
[ "$a1" = "Edit(/$TD/tz/w1/**)" ] && ok "a seat with a tmpdir gets an Edit allow on everything in its own temp folder" || { bad "own tmpdir allow"; echo "$a1"; }
! echo "$a1" | grep -q 'tz/w2' && [ "$(tdz_allow w2)" = "Edit(/$TD/tz/w2/**)" ] && ok "a seat gets no allow on another role's temp folder in the same team" || { bad "allow on another role's tmpdir"; echo "$a1"; }
[ -z "$a3" ] && ok "a seat without a tmpdir gets no temp folder allow" || { bad "allow without tmpdir"; echo "$a3"; }
sed -i '' 's/^team: tz/team: ty/' $T/td-tz.yaml; sed -i '' "s#$TD/tz/#$TD/ty/#g" $T/td-tz.yaml
! TEAM_STATE_DIR=$T/state-tz ruby $SRC/lib/team_config.rb $T/td-tz.yaml settings w1 | grep -qF "$TD/tz/" && ok "a second team's seat gets no allow on the first team's temp folder" || bad "allow on another team's tmpdir"
tdz_team
out=$(TEAM_STATE_DIR=$T/state-tz $S -c $T/td-tz.yaml check 2>&1)
echo "$out" | grep -F 'added:' | sed -n 1p | grep -qF "Edit allow on its own temp folder ($TD/tz/w1)" && ! echo "$out" | grep -F 'added:' | sed -n 3p | grep -qF "own temp folder" && ok "check shows the temp folder allow for a seat that has one, and not for one that has none" || { bad "check shows the tmpdir allow"; echo "$out" | grep -F 'added:'; }
rm -rf "$TD/tz" "$TD/ty" 2>/dev/null
e2e_end=tmpdir # the last line: test/e2e.sh checks that the file ran to here
