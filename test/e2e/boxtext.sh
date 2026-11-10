# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# say and a box that holds text (#212): the refusal is logged with its class and no text, a repeat of a
# refused text is refused as a repeat, one notice per seat shows in status, the records go when the box
# is seen empty (the resend after the remedy is not blocked), and `flush` submits a fragment say itself
# left, and nothing else. Its own team (tx), on the same tmux server and state.
echo "--- say: a box that holds text (#212)"
roles=""
for r in em n1 n2 n3 bl f1 f2 f3 f4 f5 fsh sec; do roles="$roles  $r: { title: Seat $r, workdir: { type: project, path: $T/proj }, prompt_text: \"$r prompt\" }
"; done
cat > $T/tx.yaml <<Y
team: tx
repo: { path: $T/repo, github: local/origin.git }
project: { name: TestBoard, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: tx, claude: { wrapper: $T/bin/wrap } }
roles:
$roles
Y
for r in n1 n2 n3; do echo prefill > $T/fake-$r-mode.txt; done
echo below > $T/fake-bl-mode.txt
TEAM_VIEW=0 $S -c $T/tx.yaml up --no-view >/dev/null 2>&1; sleep 2
RL=$T/state/say-refusals.log; : > $RL
# txsay <to> <message>: a say from em; sets out and rc.
txsay() { out=$(TEAM_ROLE=em $S -c $T/tx.yaml say "$1" "$2" 2>&1); rc=$?; sleep 0.5; }
touch $T/keys-n1.log; kn=$(wc -c < $T/keys-n1.log)
txsay n1 "BOXSENT first text"
[ $rc -ne 0 ] && echo "$out" | grep -qF "input box" && ! echo "$out" | grep -qF "exact text" \
  && [ "$(tail -1 $RL | cut -f2-4)" = "em	n1	box-text" ] && ! grep -qF BOXSENT $RL \
  && tail -1 $T/state/messages.log | grep -q "	n1	NOT-DELIVERED	BOXSENT first text$" \
  && ok "a refusal for a box that holds text is logged with its class, sender and receiver, and no text, besides the NOT-DELIVERED line" || { bad "the box-text refusal is logged with a reason (rc=$rc)"; echo "$out"; cat $RL; }
echo "$out" | grep -qF "flush n1" && ! echo "$out" | grep -qF "and clear it" \
  && ok "the refusal names the remedy, flush, and no longer tells a seat to clear another's box" || { bad "the refusal's remedy"; echo "$out"; }
txsay n1 "BOXSENT first text"
[ $rc -ne 0 ] && echo "$out" | grep -qF "exact text" && echo "$out" | grep -qF "do not resend" && echo "$out" | grep -qF "do not loop" \
  && [ "$(tail -1 $RL | cut -f2-4)" = "em	n1	box-text-repeat" ] \
  && ok "a repeat of the refused text within the window is refused as a repeat, saying so, and logged as that class" || { bad "the repeat of a refused text"; echo "$out"; cat $RL; }
txsay n1 "BOXSENT another text"
[ $rc -ne 0 ] && ! echo "$out" | grep -qF "exact text" && [ "$(tail -1 $RL | cut -f4)" = "box-text" ] \
  && ok "a different text to the same seat is refused for the box, not as a repeat" || { bad "a different text is not a repeat"; echo "$out"; cat $RL; }
# One notice per seat, in status, however many sends are refused: below the threshold there is none.
ns=$($S -c $T/tx.yaml status 2>&1 | grep -c '^NOTICE n1')
[ "$ns" = 1 ] && ok "after 3 refusals status shows a notice for n1" || { bad "no notice after 3 refusals (count=$ns)"; $S -c $T/tx.yaml status 2>&1 | tail -3; }
for i in 1 2 3 4; do txsay n1 "BOXSENT more $i"; done
st=$($S -c $T/tx.yaml status 2>&1)
[ "$(echo "$st" | grep -c '^NOTICE n1')" = 1 ] && echo "$st" | grep '^NOTICE n1' | grep -qF "as of the last refusal" && ! echo "$st" | grep -q '^NOTICE n[23]' \
  && ok "after 7 refusals there is still one notice for n1 (not one per send), it says as of the last refusal, and no other seat has one" || { bad "one notice per seat"; echo "$st" | tail -4; }
txsay n2 "BOXSENT n2 once"
[ "$($S -c $T/tx.yaml status 2>&1 | grep -c '^NOTICE n2')" = 0 ] && ok "one refusal to n2 shows no notice" || bad "a notice after one refusal"
[ "$(wc -c < $T/keys-n1.log)" = "$kn" ] && ok "no key reached the seat whose box held text, through all the refusals" || bad "keys reached n1"
# Other refusals are not counted: a seat with a list below its box (not recognised as ready).
txsay bl "BOXSENT bl"; txsay bl "BOXSENT bl"
[ $rc -ne 0 ] && echo "$out" | grep -qF "not recognised" && ! echo "$out" | grep -qF "exact text" && [ ! -e $T/state/say/box-bl ] && ! cut -f3 $RL | grep -qx bl \
  && ok "a refusal that is not a box with text (a screen not recognised) is neither counted nor treated as a repeat" || { bad "other refusals stay as they were"; echo "$out"; cat $RL; }
# The records are private: the hash is in a 600 file in a 700 folder, and in no log.
[ "$(stat -f %Lp $T/state/say)" = 700 ] && [ "$(stat -f %Lp $T/state/say/box-n1)" = 600 ] && ! grep -qiE '^hash=|hash=[0-9a-f]{16}' $T/state/messages.log $RL \
  && ok "the refusal records are mode 600 in a mode 700 folder, and the hash is in no log" || { bad "the refusal records are private"; ls -l $T/state/say | head; }
# A link put at a record's name is replaced, never written through.
echo keep > $T/linktarget; rm -f $T/state/say/box-n3; ln -s $T/linktarget $T/state/say/box-n3
txsay n3 "BOXSENT n3"
[ "$(cat $T/linktarget)" = keep ] && [ ! -L $T/state/say/box-n3 ] && ok "a link at a refusal record's name is replaced by the record, not written through" || { bad "a link at the record's name"; cat $T/linktarget; }
# The records go when the box is seen empty: the resend after the remedy is not blocked (tl on #212).
# n2 holds a draft; the owner clears it; the very same text goes at once.
txsay n2 "BOXSENT n2 twice"; txsay n2 "BOXSENT n2 twice"
echo "$out" | grep -qF "exact text" && ok "the same text to n2 twice is refused as a repeat" || { bad "n2's repeat"; echo "$out"; }
tmux send-keys -t '=tx-n2:' C-u; sleep 0.5
txsay n2 "BOXSENT n2 twice"
[ $rc -eq 0 ] && tmux capture-pane -p -t '=tx-n2:' | grep -qF "❯ [from em] BOXSENT n2 twice" && [ ! -e $T/state/say/box-n2 ] \
  && ok "after the box is cleared, the same text goes at once, and its refusal record is gone" || { bad "the resend after the remedy"; echo "$out"; ls $T/state/say; }
[ ! -e $T/state/say/paste-n2 ] && ok "a delivered message leaves no paste record" || bad "a paste record after a delivery"
# flush: a fragment say itself left. The record is what say writes before a paste (white box here: the
# stand-in cannot be made to lose half a paste); the box text is typed in, since flush goes by its text.
frag() { # frag <role> <box text> <record label> <record body>
  tmux send-keys -t "=tx-$1:" C-u; sleep 0.3
  [ -z "$2" ] || tmux send-keys -t "=tx-$1:" -l "$2"; sleep 0.4
  mkdir -p -m 700 $T/state/say; printf '%s\n%s\n%s\n%s' qa "$(date +%s)" "$3" "$4" > $T/state/say/paste-$1
}
flushed() { touch $T/keys-$1.log; kk=$(wc -c < $T/keys-$1.log); fo=$(TEAM_ROLE=em $S -c $T/tx.yaml flush "$1" 2>&1); frc=$?; sleep 0.7; }
frag f1 "[from qa]" "[from qa] " "qa verdict PR 305: ready"
flushed f1
[ $frc -eq 0 ] && echo "$fo" | grep -qF "a fragment of a message from qa" && echo "$fo" | grep -qF "ask qa to resend" \
  && tmux capture-pane -p -t '=tx-f1:' | grep -qF "❯ [from qa]" && [ ! -e $T/state/say/paste-f1 ] && tail -1 $T/state/messages.log | grep -q "	em	f1	FLUSHED	\[flush\]$" \
  && [ "$(tail -c +$((kk + 1)) $T/keys-f1.log | od -An -c | tr -d ' \n')" = '\r' ] \
  && ok "flush submits a label left alone, with one Enter, says it was a fragment from qa, drops the record, logs [flush]" || { bad "flush of a label alone (rc=$frc)"; echo "$fo"; tail -2 $T/state/messages.log; }
frag f2 "[from qa] qa verdict PR" "[from qa] " "qa verdict PR 305: ready, see the comment for the head and the gate"
flushed f2
[ $frc -eq 0 ] && echo "$fo" | grep -qF "a fragment of a message from qa" && tmux capture-pane -p -t '=tx-f2:' | grep -qF "❯ [from qa] qa verdict PR" \
  && ok "flush submits the start of a recorded message (the 23 characters of the field-test case)" || { bad "flush of a fragment (rc=$frc)"; echo "$fo"; }
frag f3 "[from qa] qa verdict PR 305: ready" "[from qa] " "qa verdict PR 305: ready"
flushed f3
[ $frc -eq 0 ] && echo "$fo" | grep -qF "the whole message from qa" && ok "flush submits a whole recorded message and says so" || { bad "flush of the whole record (rc=$frc)"; echo "$fo"; }
frag f4 "my own words, typed by someone" "[from qa] " "qa verdict PR 305: ready"
flushed f4
[ $frc -ne 0 ] && echo "$fo" | grep -qF "not touched" && tmux capture-pane -p -t '=tx-f4:' | grep -qF "my own words, typed by someone" \
  && [ "$(wc -c < $T/keys-f4.log)" = "$kk" ] && tail -1 $T/state/messages.log | grep -q "	f4	NOT-FLUSHED	\[flush\]$" \
  && ok "flush refuses text someone typed: the box is unchanged, no key reached the seat, and the line says NOT-FLUSHED" || { bad "flush of typed text (rc=$frc)"; echo "$fo"; }
rm -f $T/state/say/paste-f5; tmux send-keys -t '=tx-f5:' -l "[from qa] qa verdict PR"; sleep 0.4
flushed f5
[ $frc -ne 0 ] && echo "$fo" | grep -qF "no record" && tmux capture-pane -p -t '=tx-f5:' | grep -qF "[from qa] qa verdict PR" && [ "$(wc -c < $T/keys-f5.log)" = "$kk" ] \
  && ok "flush refuses a box say has no record of leaving text in, and touches nothing" || { bad "flush without a record (rc=$frc)"; echo "$fo"; }
tmux kill-session -t '=tx-fsh' 2>/dev/null; tmux new-session -d -s tx-fsh 'sleep 600'
printf '%s\n%s\n%s\n%s' qa "$(date +%s)" "[from qa] " "x" > $T/state/say/paste-fsh
fo=$(TEAM_ROLE=em $S -c $T/tx.yaml flush fsh 2>&1); frc=$?
[ $frc -ne 0 ] && echo "$fo" | grep -qF "no claude process" && ok "flush refuses a seat whose pane is at a shell, as say does" || { bad "flush at a shell (rc=$frc)"; echo "$fo"; }
tmux kill-session -t '=tx-fsh' 2>/dev/null
# The box changes between flush's check and its Enter: a tmux stand-in changes the box on the second read.
frag f5 "[from qa]" "[from qa] " "qa verdict PR"
mkdir -p $T/fshim && printf '#!/bin/sh\nn=$(cat %s/fshim.n 2>/dev/null || echo 0)\nif [ "$1" = capture-pane ]; then n=$((n+1)); echo $n > %s/fshim.n; [ $n = 2 ] && %s send-keys -t "=tx-f5:" -l " typed in between"; fi\nexec %s "$@"\n' $T $T "$(command -v tmux)" "$(command -v tmux)" > $T/fshim/tmux && chmod +x $T/fshim/tmux
rm -f $T/fshim.n; touch $T/keys-f5.log; kk=$(wc -c < $T/keys-f5.log)
fo=$(PATH=$T/fshim:$PATH TEAM_ROLE=em $S -c $T/tx.yaml flush f5 2>&1); frc=$?; sleep 0.5
[ $frc -ne 0 ] && echo "$fo" | grep -qF "changed between" && ! tail -c +$((kk + 1)) $T/keys-f5.log | LC_ALL=C grep -q $'\r' \
  && ok "flush sends no Enter when the box changed between its check and the Enter" || { bad "flush with the box changing (rc=$frc)"; echo "$fo"; tail -c +$((kk + 1)) $T/keys-f5.log | od -c | head -3; }
# The resend limit is per text (tl on #292): two senders interleaved, or one sender alternating two texts,
# do not hide each other's repeats.
txsayas() { out=$(TEAM_ROLE=$1 $S -c $T/tx.yaml say "$2" "$3" 2>&1); rc=$?; sleep 0.5; }
txsayas em n1 "INTERLEAVED text X"; txsayas f1 n1 "INTERLEAVED text Y"; txsayas em n1 "INTERLEAVED text X"
[ $rc -ne 0 ] && echo "$out" | grep -qF "exact text" && [ "$(tail -1 $RL | cut -f2-4)" = "em	n1	box-text-repeat" ] \
  && ok "a resend is refused as a repeat although another sender's text was refused in between" || { bad "interleaved senders (rc=$rc)"; echo "$out"; tail -3 $RL; }
txsayas em n1 "ALTERNATE text A"; txsayas em n1 "ALTERNATE text B"; txsayas em n1 "ALTERNATE text A"
[ $rc -ne 0 ] && echo "$out" | grep -qF "exact text" && [ "$(tail -1 $RL | cut -f4)" = "box-text-repeat" ] \
  && ok "a resend is refused as a repeat when one sender alternates two texts" || { bad "alternating texts (rc=$rc)"; echo "$out"; tail -3 $RL; }
# A link to a folder at a record's name: nothing is moved into the folder, and the refusal goes out as before.
mkdir -p $T/linkdir; rm -rf $T/state/say/box-n3; ln -s $T/linkdir $T/state/say/box-n3
txsayas em n3 "FOLDERLINK text"
[ $rc -ne 0 ] && echo "$out" | grep -qF "input box" && [ -z "$(ls -A $T/linkdir)" ] && [ -z "$(find $T/state/say -name '.put.*')" ] \
  && ok "a link to a folder at a record's name receives nothing, leaves no temporary file, and the refusal goes out as before" || { bad "a link to a folder at a record's name (rc=$rc)"; echo "$out"; ls -A $T/linkdir; ls -a $T/state/say; }
rm -f $T/state/say/box-n3
# A message to or from sec leaves no body and no hash in say's state (sec on #292): the box holds text, the
# say is refused, and neither the record nor the box state holds the sentinel or a hash of it.
echo prefill > $T/fake-sec-mode.txt
tmux kill-session -t '=tx-sec:' 2>/dev/null; TEAM_VIEW=0 $S -c $T/tx.yaml up --no-view >/dev/null 2>&1; sleep 2
txsay sec "SECSENTINEL-292 body"; txsay sec "SECSENTINEL-292 body"
[ $rc -ne 0 ] && ! echo "$out" | grep -qF "exact text" && [ "$(tail -1 $RL | cut -f4)" = "box-text" ] \
  && ! grep -rqF SECSENTINEL $T/state/say $RL && ! grep -q '^hash=.' $T/state/say/box-sec 2>/dev/null \
  && ok "a say to sec that is refused for the box leaves no body and no hash in say's state, and is not refused as a repeat" || { bad "a refused say to sec leaves nothing (rc=$rc)"; echo "$out"; ls $T/state/say; cat $T/state/say/box-sec 2>/dev/null; }
$S -c $T/tx.yaml down --yes >/dev/null 2>&1
e2e_end=boxtext # the last line: test/e2e.sh checks that the file ran to here
