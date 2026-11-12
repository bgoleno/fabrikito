# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# up and the other commands on the default tmux server; test/live-env.sh (#66); test/e2e.sh's own exit
# trap and cleanup, which may stop no server but the run's (#306, test/e2e-exit-trap.sh).
echo "--- live tests: up refuses the default tmux server for a throwaway team; test/live-env.sh (#66)"
# Every up below runs with a stand-in tmux first on PATH that logs its arguments and fails, so no case
# can reach a real tmux server, the user's default one included, even when the refusal is missing.
mkdir -p $T/notmux $T/ltproj
printf '#!/bin/sh\necho "$*" >> %s/notmux.log\nexit 1\n' $T > $T/notmux/tmux; chmod +x $T/notmux/tmux
printf 'team: lt\nrepo: { path: %s/repo, github: local/origin.git }\nproject: { name: B, url: "https://github.com/users/x/projects/9" }\nstorage: { volume: %s, root: %s }\nsessions: { prefix: lt, claude: { wrapper: %s/bin/wrap } }\nroles:\n  x: { title: X, workdir: { type: project, path: %s/ltproj }, prompt_text: "x" }\n' $T $VOL $ROOT $T $T > $T/lt.yaml
DEFSOCK=/tmp/tmux-$(id -u)/default
# lt <env assignments...>: up for lt.yaml through the stand-in tmux; sets out, rc and calls (stand-in calls)
lt() {
  : > $T/notmux.log
  out=$(env -u TMUX -u TMUX_TMPDIR "PATH=$T/notmux:$PATH" TEAM_STATE_DIR=$T/ltstate TEAM_VIEW=0 "$@" 2>&1); rc=$?
  calls=$(wc -l < $T/notmux.log | tr -d ' ')
}
refused_default() { [ $rc -ne 0 ] && [ "$calls" = 0 ] && echo "$out" | grep -qF "default tmux server" && echo "$out" | grep -qF -- "--default-socket"; }
lt $S -c $T/lt.yaml up --no-view
refused_default && echo "$out" | grep -qF "$T/lt.yaml" && ok "up refuses a team file outside teams/ on the default tmux server (TMUX and TMUX_TMPDIR unset), before any tmux call" || { bad "up on the default server, unset (rc=$rc, tmux calls=$calls)"; echo "$out"; }
lt TMUX_TMPDIR=/tmp $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses TMUX_TMPDIR=/tmp (the default socket's folder)" || { bad "up with TMUX_TMPDIR=/tmp (rc=$rc, calls=$calls)"; echo "$out"; }
lt TMUX_TMPDIR=/private/tmp/ $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses another spelling of /tmp (/private/tmp/)" || { bad "up with TMUX_TMPDIR=/private/tmp/ (rc=$rc, calls=$calls)"; echo "$out"; }
lt TMUX_TMPDIR= $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses an empty TMUX_TMPDIR (tmux then uses /tmp)" || { bad "up with an empty TMUX_TMPDIR (rc=$rc, calls=$calls)"; echo "$out"; }
lt TMUX_TMPDIR=$T/no-such-dir $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses a TMUX_TMPDIR that does not exist (tmux falls back to /tmp)" || { bad "up with a missing TMUX_TMPDIR (rc=$rc, calls=$calls)"; echo "$out"; }
lt TMUX_TMPDIR=$T/tmux TMUX=$DEFSOCK,1,0 $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses TMUX naming the default socket, even with a private TMUX_TMPDIR (tmux follows TMUX)" || { bad "up with TMUX on the default socket (rc=$rc, calls=$calls)"; echo "$out"; }
# Links in the socket path: tmux connects through them, so up must judge where they lead.
if [ -d /tmp/tmux-$(id -u) ]; then
  mkdir -p $T/lnk1; ln -s /tmp/tmux-$(id -u) $T/lnk1/tmux-$(id -u)
  lt TMUX_TMPDIR=$T/lnk1 $S -c $T/lt.yaml up --no-view
  refused_default && ok "up refuses a private TMUX_TMPDIR whose tmux-<uid> links to the default one" || { bad "up with a linked tmux-<uid> (rc=$rc, calls=$calls)"; echo "$out"; }
else
  ok "up and a linked tmux-<uid>: no /tmp/tmux-$(id -u) here, so not checked"
fi
mkdir -p -m 700 $T/lnk2/tmux-$(id -u); ln -s $DEFSOCK $T/lnk2/tmux-$(id -u)/default
lt TMUX_TMPDIR=$T/lnk2 $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses a private TMUX_TMPDIR whose socket links to the default one" || { bad "up with a linked socket (rc=$rc, calls=$calls)"; echo "$out"; }
ln -s $DEFSOCK $T/lnk3
lt TMUX_TMPDIR=$T/tmux TMUX=$T/lnk3,1,0 $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses TMUX naming a link to the default socket" || { bad "up with TMUX through a link (rc=$rc, calls=$calls)"; echo "$out"; }
lt TMUX_TMPDIR=$T/tmux $S -c $T/lt.yaml up --no-view
[ "$calls" -gt 0 ] && ! echo "$out" | grep -qF "default tmux server" && ok "up goes ahead on a private TMUX_TMPDIR" || { bad "up on a private server was refused (rc=$rc, calls=$calls)"; echo "$out"; }
lt CDPATH=/ TMUX_TMPDIR=tmp sh -c 'cd / && exec "$@"' sh $S -c $T/lt.yaml up --no-view
refused_default && ok "up refuses a relative TMUX_TMPDIR that resolves to /tmp, with CDPATH set" || { bad "up with CDPATH and a relative TMUX_TMPDIR (rc=$rc, calls=$calls)"; echo "$out"; }
lt $S -c $T/lt.yaml up --no-view --default-socket
[ "$calls" -gt 0 ] && ! echo "$out" | grep -qF "default tmux server" && ok "up --default-socket goes ahead on the default server" || { bad "up --default-socket (rc=$rc, calls=$calls)"; echo "$out"; }
# a team file in teams/ next to fabrikito: an install under $T (links to lib, roles and plugin), so nothing is written in the checkout
# fabrikito is copied, not linked: a link to the file is the real install (#263), so a linked file would make $SRC the install.
mkdir -p $T/inst/teams; cp $SRC/fabrikito $T/inst/fabrikito; for p in lib roles plugin; do ln -s $SRC/$p $T/inst/$p; done; cp $T/lt.yaml $T/inst/teams/lt.yaml
lt $T/inst/fabrikito -c $T/inst/teams/lt.yaml up --no-view
[ "$calls" -gt 0 ] && ! echo "$out" | grep -qF "default tmux server" && ok "up goes ahead on the default server for a team file in teams/" || { bad "up for a team file in teams/ (rc=$rc, calls=$calls)"; echo "$out"; }
# The same rule for down (with and without --yes), say, attach and view (#105). A team of two
# stand-in seats (fw-fa, fw-fb) runs on the e2e's private server. A copy of its team file outside
# teams/ is then used with TMUX and TMUX_TMPDIR unset, so the launcher takes the default server, and
# a stand-in tmux first on PATH logs each call and passes it to the private server: a command that
# is not refused reaches those seats, and never the user's real default server. Each must be refused
# before any tmux call, and the seats must be as they were: the same sessions, started at the same
# time with the same pane process, and no key typed into either. down --yes comes last, so a red run
# kills them last.
PRIV=$T/tmux/tmux-$(id -u)/default
printf 'team: fw\nrepo: { path: %s/repo, github: local/origin.git }\nproject: { name: B, url: "https://github.com/users/x/projects/9" }\nstorage: { volume: %s, root: %s }\nsessions: { prefix: fw, claude: { wrapper: %s/bin/wrap } }\nroles:\n  fa: { title: FA, workdir: { type: project, path: %s/proj }, prompt_text: "fa" }\n  fb: { title: FB, workdir: { type: project, path: %s/proj }, prompt_text: "fb" }\n' $T $VOL $ROOT $T $T $T > $T/fw.yaml
TEAM_STATE_DIR=$T/fwstate TEAM_VIEW=0 $S -c $T/fw.yaml up --no-view >/dev/null 2>&1
mkdir -p $T/fwdtmux; printf '#!/bin/sh\necho "$*" >> %s/fwd.log\nexec %s -S %s "$@"\n' $T "$(command -v tmux)" $PRIV > $T/fwdtmux/tmux; chmod +x $T/fwdtmux/tmux
# The copy names its seats differently, so a titles call that is not refused would relabel them.
cp $T/fw.yaml $T/copy.yaml && sed -i '' 's/title: FA,/title: COPY-A,/; s/title: FB,/title: COPY-B,/' $T/copy.yaml
seats() { tmux -S $PRIV list-sessions -F '#{session_name} #{session_created} #{pane_pid}' 2>/dev/null | grep '^fw-' | sort; }
keys() { cat $T/keys-fa.log $T/keys-fb.log 2>/dev/null | cksum; }
ttl() { for s in fw-fa fw-fb; do tmux -S $PRIV show-options -v -t "=$s:" set-titles-string 2>/dev/null; done; }
# fw <command...>: runs it on the stand-in default server; sets out, rc and calls (tmux calls made)
fw() { : > $T/fwd.log; out=$(env -u TMUX -u TMUX_TMPDIR "PATH=$T/fwdtmux:$PATH" TEAM_STATE_DIR=$T/fwstate TEAM_ROLE=fa "$@" 2>&1 </dev/null); rc=$?; calls=$(wc -l < $T/fwd.log | tr -d ' '); }
before=$(seats); kb=$(keys); tb=$(ttl)
echo "$before" | grep -q '^fw-fa ' && echo "$before" | grep -q '^fw-fb ' || bad "test setup: fw-fa and fw-fb did not start on the e2e's tmux server"
echo "$tb" | grep -qxF "fa | FA | fw-fa" || bad "test setup: fw-fa's title is not set ($tb)"
for c in "down" "down fb" "say fb hello-from-a-copy" "say all hello-from-a-copy" "attach fa" "attach" "view" "view --print" "titles" "down --yes fb" "down --yes"; do
  fw $S -c $T/copy.yaml $c
  refused_default && echo "$out" | grep -qF "$T/copy.yaml" && [ "$(seats)" = "$before" ] && [ "$(keys)" = "$kb" ] && [ "$(ttl)" = "$tb" ] \
    && ok "$c, with a copy of the team file on the default server: refused before any tmux call, every seat as it was (titles too)" || { bad "$c with a copy on the default server (rc=$rc, tmux calls=$calls)"; echo "$out" | head -3; }
done
# The owner's real team file (in teams/) works on the default server as before, and --default-socket
# lets a team that is meant to run there through. None of these kills a seat or opens iTerm.
cp $T/fw.yaml $T/inst/teams/fw.yaml
# A command acts only on sessions its own team file started, on any server, and fw.yaml started these.
# So each team file used below is first handed the two seats, the way the owner hands a session to a
# team file that was moved (tmux set-environment ... TEAM_CONFIG), and fw.yaml gets them back at the end.
fw_hand() { local s; for s in fw-fa fw-fb; do tmux -S $PRIV set-environment -t "=$s" TEAM_CONFIG "$1"; done; }
fw_hand $T/inst/teams/fw.yaml
fw $T/inst/fabrikito -c $T/inst/teams/fw.yaml down
[ "$calls" -gt 0 ] && echo "$out" | grep -qF "would kill fa (fw-fa)" && [ "$(seats)" = "$before" ] && ok "down for a team file in teams/ goes ahead on the default server (would kill, nothing killed)" || { bad "down for a team file in teams/ (rc=$rc, calls=$calls)"; echo "$out"; }
fw $T/inst/fabrikito -c $T/inst/teams/fw.yaml attach fa
[ "$calls" -gt 0 ] && ! echo "$out" | grep -qF "default tmux server" && ok "attach for a team file in teams/ goes ahead on the default server" || { bad "attach for a team file in teams/ (rc=$rc, calls=$calls)"; echo "$out"; }
# --default-socket lets a team file onto the default server; it does not make another file's seats its own.
fw $S -c $T/copy.yaml down --default-socket
[ $rc -ne 0 ] && ! echo "$out" | grep -qF "would kill" && echo "$out" | grep -qF "fw-fa" && echo "$out" | grep -qF "$T/inst/teams/fw.yaml" && [ "$(seats)" = "$before" ] && [ "$(keys)" = "$kb" ] \
  && ok "down --default-socket with a copy of the team file lists none of the seats another team file holds as its own to stop, and names that file" || { bad "down --default-socket with a copy, seats held by another file (rc=$rc)"; echo "$out" | head -3; }
fw_hand $T/copy.yaml
fw $S -c $T/copy.yaml down --default-socket
[ "$calls" -gt 0 ] && echo "$out" | grep -qF "would kill fa (fw-fa)" && [ "$(seats)" = "$before" ] && ok "down --default-socket goes ahead on the default server" || { bad "down --default-socket (rc=$rc, calls=$calls)"; echo "$out"; }
fw $S -c $T/copy.yaml attach --default-socket fa
[ "$calls" -gt 0 ] && ! echo "$out" | grep -qF "default tmux server" && ok "attach --default-socket goes ahead on the default server" || { bad "attach --default-socket (rc=$rc, calls=$calls)"; echo "$out"; }
fw $S -c $T/copy.yaml view --print --default-socket
[ $rc = 0 ] && echo "$out" | grep -qF "fw-fa" && ok "view --print --default-socket goes ahead on the default server" || { bad "view --print --default-socket (rc=$rc)"; echo "$out" | head -3; }
fw $S -c $T/copy.yaml say --default-socket fb hello-from-the-default-socket
! echo "$out" | grep -qF "default tmux server" && [ "$calls" -gt 0 ] && ok "say --default-socket goes ahead on the default server" || { bad "say --default-socket (rc=$rc, calls=$calls)"; echo "$out"; }
fw_hand $T/inst/teams/fw.yaml
fw $T/inst/fabrikito -c $T/inst/teams/fw.yaml titles
[ $rc = 0 ] && echo "$out" | grep -qF "set the terminal title of 2 running seat(s)" && [ "$(ttl)" = "$tb" ] && ok "titles for a team file in teams/ goes ahead on the default server" || { bad "titles for a team file in teams/ (rc=$rc, calls=$calls)"; echo "$out"; }
fw_hand $T/copy.yaml
fw $S -c $T/copy.yaml titles --default-socket
[ $rc = 0 ] && ttl | grep -qxF "fa | COPY-A | fw-fa" && ok "titles --default-socket goes ahead on the default server (the copy's titles are set)" || { bad "titles --default-socket (rc=$rc, calls=$calls)"; echo "$out"; ttl; }
fw_hand $T/fw.yaml
TEAM_STATE_DIR=$T/fwstate $S -c $T/fw.yaml down --yes >/dev/null 2>&1
# test/live-env.sh: new makes a private environment, run runs a command in it, down removes it.
LE=$SRC/test/live-env.sh
le=$(env -u TMUX $LE new 2>&1); rc=$?
[ $rc = 0 ] && [ -d "$le/tmux" ] && [ -d "$le/state" ] && [ -f "$le/.live-env" ] && [ "$(stat -f %Lp "$le")" = 700 ] && ok "live-env new: a private folder (0700) with tmux/ and state/" || { bad "live-env new (rc=$rc)"; echo "$le"; }
lereal=$(cd "$le" 2>/dev/null && pwd -P)
got=$(TMUX=$DEFSOCK,1,0 TMUX_TMPDIR=/tmp TEAM_STATE_DIR=/somewhere $LE run "$le" sh -c 'printf "%s|%s|%s|%s" "${TMUX-unset}" "$TMUX_TMPDIR" "$TEAM_STATE_DIR" "$TEAM_VIEW"' 2>&1)
[ "$got" = "unset|$lereal/tmux|$lereal/state|0" ] && ok "live-env run: TMUX unset, TMUX_TMPDIR and TEAM_STATE_DIR (resolved) in the environment, TEAM_VIEW=0, whatever the caller had" || bad "live-env run environment: $got"
# A seat has its real team in TEAM_CONFIG, which fabrikito uses when -c is missing: run must drop it.
# Its role gives way to the driver label live-test (#115).
got=$(TEAM_CONFIG=$T/team.yaml TEAM_ROLE=em TEAM_SCRIPT=$S $LE run "$le" sh -c 'printf "%s|%s|%s" "${TEAM_CONFIG-unset}" "${TEAM_ROLE-unset}" "${TEAM_SCRIPT-unset}"' 2>&1)
[ "$got" = "unset|live-test|unset" ] && ok "live-env run: TEAM_CONFIG and TEAM_SCRIPT of the calling seat are unset, and TEAM_ROLE is live-test" || bad "live-env run seat variables: $got"
# A relative folder must reach the command as an absolute one, or a command that changes directory sends tmux to /tmp.
got=$(cd "$(dirname "$le")" && $LE run "$(basename "$le")" sh -c 'cd / && printf "%s|%s" "$TMUX_TMPDIR" "$TEAM_STATE_DIR"' 2>&1)
[ "$got" = "$lereal/tmux|$lereal/state" ] && ok "live-env run: a relative folder is exported as its absolute, resolved path" || bad "live-env run with a relative folder: $got"
got=$($LE run "$le" tmux new-session -d -s le-probe 2>&1 && $LE run "$le" tmux display-message -p -t '=le-probe:' '#{socket_path}' 2>&1)
[ "$got" = "$(cd "$le/tmux" && pwd -P)/tmux-$(id -u)/default" ] && ok "live-env run: tmux uses the private socket" || bad "live-env socket: $got"
# refusals: the command must not run at all
leref() { rm -f $T/le-ran; out=$($LE run "$1" touch $T/le-ran 2>&1); rc=$?; [ $rc -ne 0 ] && [ ! -e $T/le-ran ] && echo "$out" | grep -qF -- "$2"; }
leref $T/le-missing "does not exist" && ok "live-env run refuses a folder that does not exist" || { bad "live-env missing folder (rc=$rc)"; echo "$out"; }
mkdir -p $T/le-plain/tmux $T/le-plain/state
leref $T/le-plain "not made by" && ok "live-env run refuses a folder that live-env new did not make" || { bad "live-env plain folder (rc=$rc)"; echo "$out"; }
le2=$(env -u TMUX $LE new 2>/dev/null); [ -d "$le2/tmux" ] || { le2=$T/le2-none; mkdir -p $le2/tmux; }   # never act on an empty path
rmdir "$le2/tmux"; ln -s /tmp "$le2/tmux"
leref "$le2" "default tmux server" && ok "live-env run refuses a folder whose tmux/ resolves to /tmp (the default socket)" || { bad "live-env tmux -> /tmp (rc=$rc)"; echo "$out"; }
out=$($LE down $T/le-plain 2>&1); rc=$?
[ $rc -ne 0 ] && [ -d $T/le-plain/tmux ] && ok "live-env down refuses a folder that live-env new did not make, and leaves it" || { bad "live-env down on a plain folder (rc=$rc)"; echo "$out"; }
out=$($LE down "$le2" 2>&1); rc=$?
[ $rc -ne 0 ] && [ -L "$le2/tmux" ] && ok "live-env down refuses a folder whose tmux/ resolves to /tmp, and leaves it" || { bad "live-env down with tmux -> /tmp (rc=$rc)"; echo "$out"; }
rm "$le2/tmux"; mkdir "$le2/tmux"; $LE down "$le2" >/dev/null 2>&1
# down must not follow a link inside the folder: tmux -S would reach whatever server it points at, and
# a link to /tmp/tmux-<uid> would stop the default one. The links here point at $le's private server only.
le3=$(env -u TMUX $LE new 2>/dev/null); [ -d "$le3/tmux" ] || { le3=$T/le3-none; mkdir -p $le3/tmux; }   # never act on an empty path
ledir="$(cd "$le/tmux" && pwd -P)/tmux-$(id -u)"
ln -s "$ledir" "$le3/tmux/tmux-$(id -u)"
out=$($LE down "$le3" 2>&1); rc=$?
[ $rc -ne 0 ] && [ -d "$le3" ] && tmux -S "$ledir/default" has-session -t '=le-probe' 2>/dev/null && ok "live-env down refuses a folder whose tmux-<uid> is a link, and the server it points at keeps running" || { bad "live-env down with a linked tmux-<uid> (rc=$rc)"; echo "$out"; }
rm "$le3/tmux/tmux-$(id -u)"; mkdir -m 700 "$le3/tmux/tmux-$(id -u)"; ln -s "$ledir/default" "$le3/tmux/tmux-$(id -u)/default"
leref "$le3" "is a link" && ok "live-env run refuses a folder whose socket is a link (the command does not run)" || { bad "live-env run with a linked socket (rc=$rc)"; echo "$out"; }
out=$($LE down "$le3" 2>&1); rc=$?
[ $rc -ne 0 ] && [ -d "$le3" ] && tmux -S "$ledir/default" has-session -t '=le-probe' 2>/dev/null && ok "live-env down refuses a folder whose socket is a link, and the server it points at keeps running" || { bad "live-env down with a linked socket (rc=$rc)"; echo "$out"; }
rm -f "$le3/tmux/tmux-$(id -u)/default"; $LE down "$le3" >/dev/null 2>&1
# ... and a tmux/ that links into another environment's tmux/ (the socket folder then looks like its own)
le5=$(env -u TMUX $LE new 2>/dev/null); [ -d "$le5/tmux" ] || { le5=$T/le5-none; mkdir -p $le5/tmux; }   # never act on an empty path
rmdir "$le5/tmux"; ln -s "$le/tmux" "$le5/tmux"
out=$($LE down "$le5" 2>&1); rc=$?
[ $rc -ne 0 ] && [ -d "$le5" ] && tmux -S "$ledir/default" has-session -t '=le-probe' 2>/dev/null && ok "live-env down refuses a folder whose tmux/ links into another one, and that server keeps running" || { bad "live-env down with tmux/ linked elsewhere (rc=$rc)"; echo "$out"; }
rm "$le5/tmux"; mkdir "$le5/tmux"; $LE down "$le5" >/dev/null 2>&1
# The folder is resolved physically, once: <link>/.. is the parent of where the link leads (as the
# kernel and rm see it), not the folder that holds the link (as a logical cd sees it).
le4=$(env -u TMUX $LE new 2>/dev/null); [ -d "$le4/tmux" ] || { le4=$T/le4-none; mkdir -p $le4/tmux; }   # never act on an empty path
ln -s "$le4/tmux" $T/le4link
out=$($LE down "$T/le4link/.." 2>&1); rc=$?
[ $rc = 0 ] && [ ! -e "$le4" ] && [ -d $T ] && [ -L $T/le4link ] && ok "live-env down resolves <link>/.. physically: it removes the folder the link leads into, and nothing else" || { bad "live-env down with <link>/.. (rc=$rc)"; echo "$out"; }
rm -f $T/le4link; [ -e "$le4" ] && $LE down "$le4" >/dev/null 2>&1
srvsock="$(cd "$le/tmux" && pwd -P)/tmux-$(id -u)/default"
out=$($LE down "$le" 2>&1); rc=$?
[ $rc = 0 ] && [ ! -e "$le" ] && [ ! -e "$le2" ] && ! tmux -S "$srvsock" has-session 2>/dev/null && ok "live-env down stops the private server and removes the folder" || { bad "live-env down (rc=$rc)"; echo "$out"; ls -la "$le" 2>&1 | head -3; }
# test/e2e.sh refuses a TMPDIR too long for tmux's socket, before it makes anything (#249). The stand-in
# mktemp first on PATH fails and logs: without the refusal, this nested run stops at once instead of
# running the whole test again, and the log shows it got past the check.
E2L=$T/$(printf 'x%.0s' $(seq 1 110)); mkdir -p $E2L $T/nomktemp
printf '#!/bin/sh\necho "$*" >> %s/nomktemp.log\nexit 1\n' $T > $T/nomktemp/mktemp; chmod +x $T/nomktemp/mktemp
out=$(PATH=$T/nomktemp:$PATH TMPDIR=$E2L TEST_VOLUME=$VOL $SRC/test/e2e.sh 2>&1); rc=$?
[ $rc = 64 ] && echo "$out" | grep -qF "TMPDIR is too long" && echo "$out" | grep -qF "takes at most $e2e_max" && [ ! -e $T/nomktemp.log ] && [ -z "$(ls -A $E2L)" ] \
  && ok "test/e2e.sh refuses a TMPDIR too long for tmux's socket, says the longest it takes, and makes nothing" || { bad "test/e2e.sh with a TMPDIR too long (rc=$rc)"; echo "$out" | tail -3; }
# The exit trap and the cleanup of test/e2e.sh itself (#306), by test/e2e-exit-trap.sh: nested runs of
# test/e2e.sh with stub areas, and a stand-in tmux first on PATH that records and runs nothing, so none of
# them can reach a real tmux server. It is a script of its own so that it can run alone, on old code too.
out=$($SRC/test/e2e-exit-trap.sh 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qE '^e2e-exit-trap: [1-9][0-9]* checks, 0 failed$' \
  && ok "test/e2e-exit-trap.sh: the exit trap and the cleanup of test/e2e.sh reach no tmux server but the run's own, and a child that exits early cleans up nothing" || { bad "test/e2e-exit-trap.sh (rc=$rc)"; echo "$out"; }
e2e_end=live # the last line: test/e2e.sh checks that the file ran to here
