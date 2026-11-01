# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# say delivers only to a seat showing its input box. Its own team (tp) on the same tmux server and state.
echo "--- say delivers only to a seat showing its input box"
# The stand-in draws Claude Code 2.1.316's input box unless a seat has a dialog file, which it draws
# instead (a dialog replaces the box). pp, pm, pd and ph show dialogs copied from 2.1.316 screens
# captured on 2026-10-30 (permission prompt, question menu, folder trust, held message), so a later
# CLI that draws them differently shows up as a mismatch here. pu shows an invented select list
# with no numbers and no key hint: any dialog say does not know must fail closed too.
roles=""
# em is a seat here too: say takes its sender from TEAM_ROLE=em, which must be a role of the team (#89).
for r in em pp pm pd ph pu pb pf ps pg px pk pq po pn pz ta tb tc td te tn to pv pw py sa sb sc sd se sf; do roles="$roles  $r: { title: Seat $r, workdir: { type: project, path: $T/proj }, prompt_text: \"$r\" }
"; done
cat > $T/tp.yaml <<Y
team: tp
repo: { path: $T/repo, github: local/origin.git }
project: { name: TestBoard, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: tp, claude: { wrapper: $T/bin/wrap } }
roles:
$roles
Y
fake_prompt='────────────────────────────────────────────────────────────
 Bash command
 Create the SF_ASK_MARKER file
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 touch SF_ASK_MARKER
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 │ Permission rule Bash(touch SF_ASK_MARKER*) requires confirmation for this command.
 /permissions to update rules
 Do you want to proceed?
 ❯ 1. Yes
   2. No
 Esc to cancel · Tab to amend'
printf '%s\n' "$fake_prompt" > $T/fake-pp-prompt.txt
cat > $T/fake-pm-prompt.txt <<'M'
────────────────────────────────────────────────────────────
 ☐ Color
Which color do you prefer, red or blue?
❯ 1. Red
     Choose red.
  2. Blue
     Choose blue.
  3. Type something.
────────────────────────────────────────────────────────────
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
M
cat > $T/fake-pd-prompt.txt <<'M'
────────────────────────────────────────────────────────────
 Accessing workspace:
 /tmp/some/folder
 Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source project, or work from your team). If not, take a moment to review what's in this
 folder first.
 Claude Code'll be able to read, edit, and execute files here.
 Security guide
 ❯ No, exit
   Yes, I trust this folder
 Enter to confirm · Esc to cancel
M
cat > $T/fake-ph-prompt.txt <<'M'
────────────────────────────────────────────────────────────
 Held message from another session
 Another Claude session sent a message: from uds:/tmp/cc-socks/1234.sock [verified pid 1234] (peer claims name: other)
 The sending session's permission mode class doesn't match this session's, so it wasn't delivered automatically.
 Message body (this is what will be delivered):
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 probe from other
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 ❯ Deny - drop it and tell the sender it was declined
   Deliver this message to Claude
M
cat > $T/fake-pu-prompt.txt <<'M'
────────────────────────────────────────────────────────────
 Pick what happens next
 ❯ Leave it as it is
   Change it
M
echo tall > $T/fake-ta-mode.txt; echo tall > $T/fake-te-mode.txt; echo tall-nolabel > $T/fake-tn-mode.txt; echo tall-otherlabel > $T/fake-to-mode.txt; echo tall-dim > $T/fake-tb-mode.txt; echo tall-typed > $T/fake-tc-mode.txt; echo tall-short > $T/fake-td-mode.txt
echo below > $T/fake-pb-mode.txt; echo prefill > $T/fake-pf-mode.txt; echo swallow > $T/fake-ps-mode.txt
echo suggest > $T/fake-pg-mode.txt; echo mixed > $T/fake-px-mode.txt; echo sticky > $T/fake-pk-mode.txt
echo mention > $T/fake-pn-mode.txt; echo mentionsel > $T/fake-pz-mode.txt
# The diff panel notice (#95), byte for byte as Claude Code 2.1.316 drew it in an 89-column pane on
# 2026-10-31, then the reset its next row starts with. pv: above a whole input box. pw: the same,
# in a pane too short for the box under it (the screen ends at the input row). py: above a dialog.
notice=$(printf '\033[2m\342\225\255%s\033[0m\033[38;5;246m\342\234\225\033[2m\033[39m\342\224\200\342\225\256\n\342\224\202\033[0m \033[38;5;246mResize your terminal to at least 110 columns to show the diff panel\033[39m%19s\033[2m\342\224\202\n\342\225\260%s\342\225\257\n\033[0m' \
  "$(printf '\342\224\200%.0s' $(seq 85))" "" "$(printf '\342\224\200%.0s' $(seq 87))")
printf '%s\n' "$notice" > $T/fake-pv-output.txt; cp $T/fake-pv-output.txt $T/fake-pw-output.txt; echo cut > $T/fake-pw-mode.txt
# sa, sb, sc (#84): see "Short panes" below. sa draws the notice only while it is under 110 columns.
cp $T/fake-pv-output.txt $T/fake-sa-output.txt; echo small > $T/fake-sa-mode.txt; echo small-clean > $T/fake-sb-mode.txt; echo tall > $T/fake-sc-mode.txt; echo small-slow > $T/fake-sd-mode.txt; echo small-clean > $T/fake-se-mode.txt; echo small-typed > $T/fake-sf-mode.txt
printf '%s\n%s\n' "$notice" "$fake_prompt" > $T/fake-py-prompt.txt
{ printf '%s\n' "$fake_prompt"; for i in $(seq 1 5); do echo "later output line $i"; done; } > $T/fake-pq-output.txt
cat > $T/fake-po-output.txt <<'M'
⏺ The permission prompt asked "Do you want to proceed?" and the cursor sat on "❯ 1. Yes".
  The key hint read "Esc to cancel · Tab to amend", and the trust dialog offered "No, exit".
 Do you want to proceed?
 ❯ 1. Yes
 Esc to cancel · Tab to amend
M
TEAM_VIEW=0 $S -c $T/tp.yaml up --no-view >/dev/null 2>&1; sleep 2
# refused <role> <expected reason> <what>: say fails with that reason, the log says NOT-DELIVERED,
# and no Enter reached the seat during the call.
refused() {
  local out rc n
  touch $T/keys-$1.log; n=$(wc -c < $T/keys-$1.log)
  out=$(TEAM_ROLE=em $S -c $T/tp.yaml say "$1" "routine message to $1" 2>&1); rc=$?; sleep 1
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$2" && tail -1 $T/state/messages.log | grep -q "	$1	NOT-DELIVERED	" &&
    ! tail -c +$((n + 1)) $T/keys-$1.log | LC_ALL=C grep -q $'\r'; then ok "say refuses $3"; else bad "say refuses $3 (rc=$rc)"; echo "$out"; fi
}
# delivered <role> <what>: the message was submitted (the stand-in's transcript echoes a submitted
# message after "❯ " with a plain space; its input box uses a no-break space).
delivered() {
  TEAM_ROLE=em $S -c $T/tp.yaml say "$1" "hello $1 ($2)" >/dev/null 2>&1; sleep 1
  tmux capture-pane -p -t "=tp-$1:" | grep -qF "❯ [from em] hello $1 ($2)" && ok "say delivers $2" || { bad "say delivers $2"; tail -1 $T/state/messages.log; }
}
refused pp "screen not recognised as ready" "a seat at a permission prompt"
[ ! -s $T/keys-pp.log ] && ok "the seat at the prompt received no keys at all" || bad "keys reached the seat at the prompt"
tmux capture-pane -p -t '=tp-pp:' | grep -q "routine message" && bad "the refused message was left on pp's screen" || ok "a refused message leaves nothing on the seat's screen"
refused pm "screen not recognised as ready" "a seat at a question menu"
refused pd "screen not recognised as ready" "a seat at the folder-trust dialog"
refused ph "screen not recognised as ready" "a seat at the held-message dialog"
refused pu "screen not recognised as ready" "a seat at an unknown select list (no numbers, no key hint, no input box)"
refused pb "screen not recognised as ready" "a seat with a list below its input box"
refused pf "input box" "a seat whose input box holds text (an unsent draft)"
refused ps "text left in input box" "a seat whose input box does not show the pasted text"
delivered pg "a seat whose empty box shows a dim suggested prompt"
refused px "input box" "a seat whose box holds typed text next to a dim suggestion"
refused pk "text left in input box" "a seat whose box keeps dim text next to the pasted message"
delivered pq "prompt text in the transcript above the box"
delivered po "the seat's own output quoting prompt lines"
TEAM_ROLE=em $S -c $T/tp.yaml say po "qa result: it asked 'Do you want to proceed?' with '❯ 1. Yes' and 'Esc to cancel · Tab to amend'" >/dev/null 2>&1; sleep 1
delivered po "the message after one that quotes prompt text"
# The @-mention list (#77). Claude Code 2.1.316 draws it above the box, and after a paste no row is
# highlighted, so Enter submits the message as pasted; it completes the mention only when a row was
# picked with the arrow keys, which leaves text in the box, and say refuses that before pasting.
printf '%s' 'probe @src' | tmux load-buffer -b mn -; tmux paste-buffer -p -d -b mn -t '=tp-pn:'; sleep 1
tmux capture-pane -p -t '=tp-pn:' | grep -qF '    + src/beta.txt' && ok "stand-in: a pasted message ending in an @ word opens the mention list above the box" || bad "stand-in: no mention list after the paste"
tmux send-keys -t '=tp-pn:' C-u; sleep 1
TEAM_ROLE=em $S -c $T/tp.yaml say pn "see @src" >/dev/null 2>&1; sleep 1
mn=$(tmux capture-pane -p -t '=tp-pn:')
echo "$mn" | grep -qF "❯ [from em] see @src" && ! echo "$mn" | grep -qF "see @src/" && tail -1 $T/state/messages.log | grep -q "	pn	delivered	see @src$" &&
  ok "say delivers a message ending in an @ word whole (the mention list above the box is not read as footer)" || { bad "say to a seat with the mention list"; echo "$mn" | tail -8; tail -1 $T/state/messages.log; }
refused pz "input box" "a seat whose box holds text with a highlighted @-mention row (Enter would complete it)"
# The notice alone is no reason to refuse: with the whole box under it, say delivers. Only when it
# pushes the end of the box off the pane does say refuse, and then it says why and what clears it.
tmux capture-pane -p -t '=tp-pv:' | grep -qF "Resize your terminal to at least 110 columns to show the diff panel" && ok "stand-in: pv draws the diff panel notice above its box" || bad "stand-in: no notice on pv"
delivered pv "a seat with the diff panel notice above its whole input box"
refused pw "diff panel notice" "a seat whose diff panel notice pushed the end of its input box off a short pane, naming the notice"
nout=$(TEAM_ROLE=em $S -c $T/tp.yaml say pw "notice wording check" 2>&1)
echo "$nout" | grep -qF "110 columns wide or more" && echo "$nout" | grep -qF "16 rows or more" && echo "$nout" | grep -qF "close the diff panel" &&
  ok "the refusal says how to clear the notice (110 columns, 16 rows, or close the panel)" || { bad "notice refusal wording"; echo "$nout"; }
refused py "screen not recognised as ready" "a seat at a permission prompt under the diff panel notice"
tmux copy-mode -t '=tp-pq:'; refused pq "copy mode" "a seat whose pane is in copy mode"; tmux send-keys -t '=tp-pq:' -X cancel
# When tmux cannot read the seat's screen, say cannot tell what is up: it refuses.
mkdir -p $T/shim && printf '#!/bin/sh\n[ "$1" = capture-pane ] && exit 1\nexec %s "$@"\n' "$(command -v tmux)" > $T/shim/tmux && chmod +x $T/shim/tmux
before=$(wc -c < $T/keys-pq.log)
cf=$(PATH=$T/shim:$PATH TEAM_ROLE=em $S -c $T/tp.yaml say pq "capture fails" 2>&1); rc=$?; sleep 1
[ $rc -ne 0 ] && echo "$cf" | grep -q "could not read" && [ "$(wc -c < $T/keys-pq.log)" = "$before" ] && tail -1 $T/state/messages.log | grep -q "	pq	NOT-DELIVERED	capture fails" && ok "a failed screen capture refuses delivery, logs NOT-DELIVERED, sends no keys" || { bad "failed capture (rc=$rc)"; echo "$cf"; tail -1 $T/state/messages.log; }
# A message taller than the input box (#47). Claude Code 2.1.316 scrolls a full box and shows only
# the end of the text; below 801 characters and 4 lines it is not collapsed to a placeholder. ta..te
# model that box in a 110x16 pane, which shows 3 rows: the smallest pane say does not resize (#84),
# so the scrolled box is still what it reads there.
for r in ta tb tc td te tn to; do tmux resize-window -t "=tp-$r:" -x 110 -y 16; tmux send-keys -t "=tp-$r:" C-l; done; sleep 1
msg() { local m="" i=0; while [ ${#m} -lt $1 ]; do i=$((i+1)); m="$m w$(printf %03d $i)"; done; m=${m# }; printf '%s' "${m:0:$1}"; }
# tall <role> <ok|refused> <message> <what>: say's exit status, and whether an Enter followed the paste.
tall() {
  local rc
  touch $T/keys-$1.log
  TEAM_ROLE=em $S -c $T/tp.yaml say "$1" "$3" >$T/tall.out 2>&1; rc=$?; sleep 1
  if [ "$2" = ok ]; then
    [ $rc -eq 0 ] && [ "$(tail -c 7 $T/keys-$1.log | od -An -c | tr -d ' \n')" = '033[201~\r' ] && ok "say delivers $4" || { bad "say delivers $4 (rc=$rc)"; cat $T/tall.out; tmux send-keys -t "=tp-$1:" C-u; sleep 0.5; }
  else
    [ $rc -ne 0 ] && [ "$(tail -c 6 $T/keys-$1.log | od -An -c | tr -d ' \n')" = '033[201~' ] && ok "say refuses $4" || { bad "say refuses $4 (rc=$rc)"; cat $T/tall.out; }
  fi
}
tall ta ok "$(msg 490)" "a message taller than the box (500 characters, 5 rows in a 3-row box)"
# The edge counts the message alone: its label is a paste of its own (#150).
tall ta ok "$(msg 800)" "a tall message at the 800-character edge (shown as text)"
tall ta ok "$(msg 801)" "a message one past the edge (801 characters, a placeholder)"
tall ta ok "$(msg 140)"$'\n'"$(msg 140)"$'\n'"$(msg 140)" "a tall message of 3 lines (shown as text)"
tall ta ok "$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)" "a message of 4 lines (a placeholder)"
# Each refusal after the paste names its own cause (#84), not the generic "not empty" one.
why() { grep -qF "$1" $T/tall.out && ok "the refusal says why: $2" || { bad "refusal reason: $2"; cat $T/tall.out; }; }
tall tb refused "$(msg 490)" "a tall message with dim text after it"; why "dim text" "dim text was drawn next to the message"
tall tc refused "$(msg 490)" "a tall message with text typed after it"; why "does not end with the message" "the box does not end with the message"
# A placeholder passes only as the whole box (tl on #132): text typed after a long or 4-line paste
# would go out with it. The box is cleared first, so each refusal is the one after its own paste.
tmux send-keys -t '=tp-tc:' C-u; sleep 0.5
tall tc refused "$(msg 900)" "a 900-character message (a placeholder) with text typed after it"; why "not just the message" "the box holds more than the placeholder"
tmux send-keys -t '=tp-tc:' C-u; sleep 0.5
tall tc refused "$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)" "a 4-line message (a placeholder) with text typed after it"; why "not just the message" "the box holds more than the placeholder"
tmux send-keys -t '=tp-tc:' C-u; sleep 0.5
tall td refused "$(msg 490)" "the end of a tall message in a box that is not full"; why "shows 2 of its 3 rows" "the box shows 2 of its 3 rows"
# A full box whose visible end matches but is under 40 characters is too little to go on: refused.
tall te refused "$(msg 110)"$'\n'"ok"$'\n'"go" "a tall message whose visible end is under 40 characters"; why "under the 40 say needs" "too little of the message's end is visible"
# The label outside the paste (#150). Claude Code hands a collapsed paste to the seat inside
# <pasted_content> tags, and a label in there made seats doubt the sender (fs1's live runs on #150).
# So say pastes "[from <role>] " on its own, then the message: a paste that short is never collapsed,
# and the box shows "[from em] [Pasted text #N +K lines]". It is pasted, not typed: typed keys could
# answer a dialog (tl on #150). The Enter goes only to the label and one placeholder as the whole box.
m4="$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)"
# pastes <role> <offset>: the pastes in the seat's key log after byte <offset>, one per line, each
# shown with inspect, and " +Enter" when an Enter followed it.
pastes() { tail -c +$(($2 + 1)) $T/keys-$1.log | ruby -e 'STDIN.binmode.read.scan(/\e\[200~(.*?)\e\[201~(\r?)/m) { |t, e| puts t.inspect + (e == "\r" ? " +Enter" : "") }'; }
# lastsub <role>: the last message the stand-in submitted (its transcript shows "❯ " with a plain space).
lastsub() { tmux capture-pane -p -S -60 -t "=tp-$1:" | grep '^❯ ' | tail -1; }
# label_first <role> <offset> <label> <what>: two pastes after <offset>, the label alone and then the
# message, and an Enter after the second only.
label_first() {
  local p; p=$(pastes "$1" "$2")
  [ "$(printf '%s\n' "$p" | wc -l | tr -d ' ')" = 2 ] && [ "$(printf '%s\n' "$p" | head -1)" = "\"$3\"" ] &&
    printf '%s\n' "$p" | tail -1 | grep -q '^"w001.* +Enter$' && ok "$4" || { bad "$4"; printf '%s\n' "$p" | cut -c1-120; }
}
k=$(wc -c < $T/keys-ta.log)
tall ta ok "$m4" "a 4-line message (a placeholder) with its label"
label_first ta "$k" "[from em] " "the label is pasted on its own, then the message, then Enter"
lastsub ta | grep -qE '^❯ \[from em\] \[Pasted text #[0-9]+ \+3 lines\]$' && ok "the seat receives the label as its own text, before the placeholder" || { bad "label before the placeholder"; lastsub ta; }
# A line over 800 characters collapses with no "+K lines" (qa on #132).
k=$(wc -c < $T/keys-ta.log)
tall ta ok "$(msg 900)" "a 900-character line (a placeholder with no line count) with its label"
label_first ta "$k" "[from em] " "the label of the 900-character line is pasted on its own"
lastsub ta | grep -qE '^❯ \[from em\] \[Pasted text #[0-9]+\]$' && ok "the seat receives the label, then the one-line placeholder" || { bad "label before the one-line placeholder"; lastsub ta; }
# [from owner] (TEAM_ROLE unset, outside every seat) and [from live-test] go in the same way.
for who in owner live-test; do
  k=$(wc -c < $T/keys-ta.log)
  if [ $who = owner ]; then env -u TEAM_ROLE $S -c $T/tp.yaml say ta "$m4" >$T/tall.out 2>&1; else TEAM_ROLE=live-test $S -c $T/tp.yaml say ta "$m4" >$T/tall.out 2>&1; fi
  rc=$?; sleep 1
  [ $rc = 0 ] && lastsub ta | grep -qE "^❯ \[from $who\] \[Pasted text #[0-9]+ \+3 lines\]$" && ok "say delivers a 4-line message as [from $who]" || { bad "say as $who (rc=$rc)"; cat $T/tall.out; lastsub ta; }
  label_first ta "$k" "[from $who] " "the [from $who] label is pasted on its own too"
done
# A placeholder whose label did not reach the box (tn), or under another role's label (to), is
# not this message: refused, no Enter.
tall tn refused "$m4" "a 4-line message whose label is missing from the box (a placeholder alone)"; why "not just the message" "the box holds a placeholder without the label"
tall to refused "$m4" "a 4-line message whose box shows another role's label before the placeholder"; why "not just the message" "the box holds another label"
tmux send-keys -t '=tp-tn:' C-u; tmux send-keys -t '=tp-to:' C-u; sleep 0.5
# A paste that fails (fshim: the paste-buffer call number $T/fshim.fail, from 0, fails). The first:
# nothing reached the box; say says it could not paste. The second: the label is in the box alone,
# and say says the text is left there. Neither sends an Enter, and both log NOT-DELIVERED.
mkdir -p $T/fshim && printf '#!/bin/sh\nif [ "$1" = paste-buffer ]; then n=$(cat %s/fshim.n 2>/dev/null || echo 0); echo $((n + 1)) > %s/fshim.n; [ "$n" = "$(cat %s/fshim.fail)" ] && exit 1; fi\nexec %s "$@"\n' $T $T $T "$(command -v tmux)" > $T/fshim/tmux && chmod +x $T/fshim/tmux
for f in 0 1; do
  echo $f > $T/fshim.fail; rm -f $T/fshim.n; k=$(wc -c < $T/keys-ta.log)
  fo=$(PATH=$T/fshim:$PATH TEAM_ROLE=em $S -c $T/tp.yaml say ta "$m4" 2>&1); rc=$?; sleep 1
  p=$(pastes ta "$k"); box=$(tmux capture-pane -p -t '=tp-ta:' | grep $'^\xe2\x9d\xaf\xc2\xa0' | sed 's/ *$//')
  if [ $f = 0 ]; then
    [ $rc -ne 0 ] && echo "$fo" | grep -qF "could not paste into the input box of ta" && [ -z "$p" ] && [ "$(wc -c < $T/keys-ta.log)" = "$k" ] &&
      tail -1 $T/state/messages.log | grep -q "	ta	NOT-DELIVERED	" && ok "a failed paste of the label: not delivered, nothing reached the seat" || { bad "failed label paste (rc=$rc)"; echo "$fo"; echo "$p"; }
  else
    [ $rc -ne 0 ] && echo "$fo" | grep -qF "text left in input box" && [ "$p" = '"[from em] "' ] && [ "$box" = "$(printf '❯\302\240[from em]')" ] &&
      tail -1 $T/state/messages.log | grep -q "	ta	NOT-DELIVERED	" && ok "a failed paste of the message after its label: not delivered, the label left in the box, no Enter, and say says so" || { bad "failed message paste (rc=$rc)"; echo "$fo"; echo "$p"; echo "$box"; }
  fi
  tmux send-keys -t '=tp-ta:' C-u; sleep 0.5
done
# Short panes (#84). The team view gives seats panes of 89x13 (10 seats) and 10 to 11 rows (12
# seats). There the diff panel notice can push the box off the screen (sa: 89x13, the notice, its
# window-size unset), and a paste can grow the box past the bottom (sb at 80x10, no notice,
# window-size manual, as resize-window leaves it). say runs its checks at the pane's own size; only
# when one refuses in a window under 110x12 does it grow the window to 220x50, run that check again,
# and put back size and window-size exactly (tl on #132). A seat whose checks pass is never resized,
# so the owner's view of it does not flash: sb at 89x13, and the big seat sc.
tmux resize-window -t '=tp-sa:' -x 89 -y 13; tmux set-option -w -u -t '=tp-sa:' window-size; tmux resize-window -t '=tp-sb:' -x 89 -y 13; sleep 1
geo() { printf '%s %s' "$(tmux display-message -p -t "=tp-$1:" '#{window_width}x#{window_height}')" "opt=[$(tmux show-options -w -t "=tp-$1:" window-size 2>&1)]"; }
ga=$(geo sa); gb=$(geo sb); gc=$(geo sc)
[ "$ga" = "89x13 opt=[]" ] && [ "$gb" = "89x13 opt=[window-size manual]" ] && [ "${gc%% *}" = 220x50 ] || bad "test setup: seat geometry (sa $ga, sb $gb, sc $gc)"
tmux capture-pane -p -t '=tp-sa:' | grep -qF "Resize your terminal to at least 110 columns" && ok "stand-in: sa (89x13) draws the diff panel notice" || bad "stand-in: no notice on sa"
# rshim logs say's resize-window and paste-buffer calls, in order. steps <role> prints them for that
# seat: grow (to 220x50), shrink (any other size) and paste.
mkdir -p $T/rshim && printf '#!/bin/sh\ncase "$1" in resize-window|paste-buffer) echo "$*" >> %s/resize.log ;; esac\nexec %s "$@"\n' $T "$(command -v tmux)" > $T/rshim/tmux && chmod +x $T/rshim/tmux; : > $T/resize.log
steps() {
  LC_ALL=C awk -v w="-t $(tmux display-message -p -t "=tp-$1:" '#{window_id}') " -v s="-t =tp-$1:" '
    $1 == "paste-buffer" && index($0 " ", s " ") { printf "paste " }
    $1 == "resize-window" && index($0, w) { printf "%s ", ($0 ~ / -x 220 -y 50$/ ? "grow" : "shrink") }' $T/resize.log
}
# (i) checks that pass in a small window: no resize at all.
PATH=$T/rshim:$PATH tall sb ok "short pane, one line" "a one-line message to a seat in an 89x13 pane whose checks pass"
PATH=$T/rshim:$PATH tall sb ok "$(msg 400)" "a 400-character line to the 89x13 seat (its box scrolls)"
[ "$(steps sb)" = "paste paste paste paste " ] && [ "$(geo sb)" = "$gb" ] && ok "say does not resize a small seat whose checks pass (the owner's view does not flash)" || { bad "the small seat whose checks pass was resized ($(steps sb); $(geo sb), was $gb)"; cat $T/resize.log; }
# (iii) the notice in place of the box: the check before the paste refuses, so say grows the window,
# checks again, pastes and sends Enter in the grown window, then puts it back.
: > $T/resize.log
PATH=$T/rshim:$PATH tall sa ok "short pane, one line" "a one-line message to a seat in an 89x13 pane with the diff panel notice"
PATH=$T/rshim:$PATH tall sa ok "line one"$'\n'"line two"$'\n'"line three" "a three-line message to the 89x13 seat"
[ "$(steps sa)" = "grow paste paste shrink grow paste paste shrink " ] && ok "say grows the seat with the notice before the paste, once per message, and puts it back" || { bad "steps for the seat with the notice ($(steps sa))"; cat $T/resize.log; }
# (ii) #84's own case: the box is whole before the paste, and the paste grows it past the bottom of an
# 80x10 pane. The check after the paste refuses, so say grows the window, checks again and sends Enter.
tmux resize-window -t '=tp-sb:' -x 80 -y 10; sleep 1; gb=$(geo sb); : > $T/resize.log
[ "$gb" = "80x10 opt=[window-size manual]" ] || bad "test setup: sb geometry ($gb)"
PATH=$T/rshim:$PATH tall sb ok "$(msg 400)" "a 400-character line to a seat in an 80x10 pane (the paste grows its box past the bottom)"
PATH=$T/rshim:$PATH tall sb ok "$(msg 290)"$'\n'"two" "a two-line, 300-character message to the 80x10 seat"
[ "$(steps sb)" = "paste paste grow shrink paste paste grow shrink " ] && ok "say grows the 80x10 seat only after the paste, when the check after it refuses, and puts it back" || { bad "steps for the 80x10 seat ($(steps sb))"; cat $T/resize.log; }
# A collapsed message there (#150): its label and its placeholder are two pastes, and the check run
# again in the grown window reads them as one box, "[from em] [Pasted text #N +3 lines]".
: > $T/resize.log; k=$(wc -c < $T/keys-sb.log)
PATH=$T/rshim:$PATH tall sb ok "$m4" "a 4-line message (a placeholder) to the 80x10 seat (grown after the paste)"
[ "$(steps sb)" = "paste paste grow shrink " ] && [ "$(geo sb)" = "$gb" ] && ok "the 80x10 seat was grown after the two pastes, checked again, and put back ($gb)" || { bad "steps for the 80x10 seat with a placeholder ($(steps sb); $(geo sb), was $gb)"; cat $T/resize.log; }
label_first sb "$k" "[from em] " "the label of the message to the 80x10 seat is pasted on its own"
lastsub sb | grep -qE '^❯ \[from em\] \[Pasted text #[0-9]+ \+3 lines\]$' && ok "the 80x10 seat receives the label, then the placeholder" || { bad "label before the placeholder at 80x10"; lastsub sb; }
# A seat slow to redraw after the resize (sd, 1.5s): until it does, its old 80x10 frame is still on
# the screen, so say waits for a rule as wide as the grown window before it checks again (tl on #132).
# lastrule <role>: the width, in columns, of the last plain rule on the seat's screen (its box's bottom rule).
lastrule() { tmux capture-pane -p -t "=tp-$1:" | LC_ALL=C awk '{ sub(/[ \t]+$/, "") } /^(\342\224\200)+$/ { last = length($0) / 3 } END { print last + 0 }'; }
tmux resize-window -t '=tp-sd:' -x 80 -y 10; for i in $(seq 1 50); do [ "$(lastrule sd)" = 80 ] && break; sleep 0.1; done
[ "$(lastrule sd)" = 80 ] || bad "test setup: sd did not redraw at 80 columns"
: > $T/resize.log; PATH=$T/rshim:$PATH tall sd ok "slow seat, one line" "a message to a seat slow to redraw after the resize (say waits for the redrawn box)"
[ "$(steps sd)" = "paste paste grow shrink " ] || { bad "steps for the slow seat ($(steps sd))"; cat $T/resize.log; }
# Text typed after the message (sf, tl on #132). In a big pane the box is whole and starts with the
# label, so only the whole visible text can tell the typed text is there: refused, no resize. In an
# 80x10 pane the paste grows the box past the bottom, so the check after the paste refuses and say
# grows the window. There the box is whole again and starts with the label: it must still refuse,
# or the Enter would submit the typed text with the message.
: > $T/resize.log; PATH=$T/rshim:$PATH tall sf refused "big pane, typed after" "a message with text typed after it, in a 220x50 pane"; why "not just the message" "the box holds more than the message"
! grep -q '^resize-window' $T/resize.log || { bad "the big seat with typed text was resized"; cat $T/resize.log; }
tmux send-keys -t '=tp-sf:' C-u; tmux resize-window -t '=tp-sf:' -x 80 -y 10; sleep 1; gf=$(geo sf); : > $T/resize.log
PATH=$T/rshim:$PATH tall sf refused "$(msg 400)" "a 400-character line with text typed after it, in an 80x10 pane (grown, then checked again)"; why "not just the message" "the box holds more than the message"
[ "$(steps sf)" = "paste paste grow shrink " ] && [ "$(geo sf)" = "$gf" ] && ok "the 80x10 seat with typed text was grown after the paste, refused there, and put back ($gf)" || { bad "steps for the seat with typed text ($(steps sf); $(geo sf), was $gf)"; cat $T/resize.log; }
tmux send-keys -t '=tp-sf:' C-u; sleep 0.5
# The same with a placeholder (sec on #132): a 900-character line, grown after the paste, refused there.
: > $T/resize.log
PATH=$T/rshim:$PATH tall sf refused "$(msg 900)" "a 900-character line (a placeholder) with text typed after it, in an 80x10 pane (grown, then checked again)"; why "not just the message" "the box holds more than the placeholder"
[ "$(steps sf)" = "paste paste grow shrink " ] && [ "$(geo sf)" = "$gf" ] && ok "the 80x10 seat with a placeholder and typed text was grown after the paste, refused there, and put back ($gf)" || { bad "steps for the seat with a placeholder and typed text ($(steps sf); $(geo sf), was $gf)"; cat $T/resize.log; }
tmux send-keys -t '=tp-sf:' C-u; sleep 0.5
[ "$(geo sa)" = "$ga" ] && [ "$(geo sb)" = "$gb" ] && ok "after each, the small seats' size and window-size are as before ($ga; $gb)" || bad "small seat geometry after say (sa $(geo sa), was $ga; sb $(geo sb), was $gb)"
: > $T/resize.log; PATH=$T/rshim:$PATH tall sc ok "big pane" "a message to a seat in a 220x50 pane"
! grep -q '^resize-window' $T/resize.log && [ "$(geo sc)" = "$gc" ] && ok "a seat in a big pane is not resized (no resize-window, same size and window-size)" || { bad "the big seat was touched ($(geo sc), was $gc)"; cat $T/resize.log; }
# Two says to one small seat at once: each message arrives whole, one after the other, or one is
# refused with a reason. Never an interleaved box. The keys the seat read must be whole pastes only.
: > $T/keys-sa.log
for i in 1 2; do ( TEAM_ROLE=em $S -c $T/tp.yaml say sa "concurrent $i $(msg 200)" >$T/conc$i.out 2>&1; echo $? > $T/conc$i.rc ) & done; wait; sleep 1
conc=$(ruby -e '
  s = File.binread(ARGV[0]); b = s.scan(/\e\[200~(.*?)\e\[201~(\r?)/m)
  m = b.each_slice(2).to_a
  whole = b.map { |t, e| "\e[200~#{t}\e[201~#{e}" }.join == s && b.size.even? &&
    m.all? { |(l, le), (t, e)| l == "[from em] " && le == "" && e == "\r" && t =~ /\Aconcurrent [12] w001/ }
  puts "#{whole ? "whole" : "MIXED"} #{m.size}"' $T/keys-sa.log)
r1=$(cat $T/conc1.rc); r2=$(cat $T/conc2.rc)
if [ "$r1" = 0 ] && [ "$r2" = 0 ]; then [ "$conc" = "whole 2" ] && ok "two concurrent says to a small seat both deliver, one after the other, never mixed" || { bad "concurrent says ($conc)"; od -c $T/keys-sa.log | head; }
else [ "$conc" = "whole 1" ] && grep -qhF "another say" $T/conc1.out $T/conc2.out && ok "of two concurrent says to a small seat, one delivers and the other is refused with a reason" || { bad "concurrent says (rc $r1 $r2, $conc)"; cat $T/conc1.out $T/conc2.out; }; fi
[ "$(geo sa)" = "$ga" ] && ok "after the concurrent says, sa's size and window-size are as before" || bad "sa geometry after concurrent says ($(geo sa), was $ga)"
# A say stopped mid-delivery (TERM) still puts the window back, and sends no Enter. The paste is held
# up by a stand-in tmux; bash runs the trap once that command returns.
mkdir -p $T/pshim && printf '#!/bin/sh\n[ "$1" = paste-buffer ] && sleep 3\nexec %s "$@"\n' "$(command -v tmux)" > $T/pshim/tmux && chmod +x $T/pshim/tmux
: > $T/keys-sa.log; PATH=$T/pshim:$PATH TEAM_ROLE=em $S -c $T/tp.yaml say sa "stopped midway" >$T/term.out 2>&1 & tp=$!
for i in $(seq 1 100); do case "$(geo sa)" in 220x50*) break ;; esac; sleep 0.1; done; sleep 1   # grown, and into the held-up paste
kill -TERM $tp; wait $tp; trc=$?; sleep 1
# The TERM lands in the first (held-up) paste, the label's (#150): the message never follows it.
[ $trc -ne 0 ] && keytext $T/keys-sa.log | grep -qxF "[from em] " && [ "$(geo sa)" = "$ga" ] && [ "$(tail -c 1 $T/keys-sa.log | od -An -c | tr -d ' \n')" != '\r' ] && ok "a say stopped with TERM mid-delivery puts sa's size and window-size back, pastes nothing after the label, and sends no Enter" || { bad "say stopped mid-delivery (rc=$trc, $(geo sa), was $ga)"; cat $T/term.out; od -c $T/keys-sa.log | head; }
tmux send-keys -t '=tp-sa:' C-u; sleep 0.5
# The lock path must be a plain file (sec on #132): opening a FIFO there to append would block with
# no limit, and a symlink could point anywhere. say refuses at once, naming the file; nothing is typed.
for kind in fifo symlink; do
  mkdir -p $T/state/say; rm -f $T/state/say/sc.lock; [ $kind = fifo ] && mkfifo $T/state/say/sc.lock || ln -s $T/elsewhere $T/state/say/sc.lock
  : > $T/keys-sc.log; t0=$(date +%s)
  lo=$(perl -e 'alarm 20; exec @ARGV' env TEAM_ROLE=em $S -c $T/tp.yaml say sc "lock is a $kind" 2>&1); lrc=$?; t1=$(date +%s)
  [ $lrc = 1 ] && [ $((t1 - t0)) -lt 15 ] && echo "$lo" | grep -qF "is not a regular file" && [ ! -s $T/keys-sc.log ] \
    && ok "a $kind at a seat's lock path: say refuses at once, naming it, and types nothing" || { bad "lock path is a $kind (rc=$lrc, $((t1 - t0))s)"; echo "$lo"; }
done
rm -f $T/state/say/sc.lock
# The window that was grown is the one put back, even when another window of the seat's session has
# become current meanwhile (tl on #132: the restore went to whatever window was current).
wa=$(tmux display-message -p -t '=tp-sa:' '#{window_id}')
PATH=$T/pshim:$PATH TEAM_ROLE=em $S -c $T/tp.yaml say sa "window switch" >$T/ws.out 2>&1 & wp=$!
for i in $(seq 1 100); do case "$(geo sa)" in 220x50*) break ;; esac; sleep 0.1; done
nw=$(tmux new-window -P -F '#{window_id}' -t '=tp-sa:' "sleep 60"); nwg=$(tmux display-message -p -t "$nw" '#{window_width}x#{window_height}')
wait $wp; sleep 0.5
wag=$(tmux display-message -p -t "$wa" '#{window_width}x#{window_height}')/$(tmux show-options -w -v -t "$wa" window-size)
[ "$wag" = "89x13/" ] && [ "$(tmux display-message -p -t "$nw" '#{window_width}x#{window_height}')" = "$nwg" ] \
  && ok "the grown window is put back (89x13, window-size unset) after another window of the session became current; that one is left alone" || { bad "restore by window (grown window $wag, other $(tmux display-message -p -t "$nw" '#{window_width}x#{window_height}'), was $nwg)"; cat $T/ws.out; }
tmux kill-window -t "$nw"; tmux send-keys -t '=tp-sa:' C-u; sleep 0.5
# A small seat at a dialog: the check before the paste refuses, say grows the window once, the check
# refuses again there, and say refuses with that reason, the window put back and nothing pasted.
tmux resize-window -t '=tp-se:' -x 80 -y 10; cp $T/fake-pp-prompt.txt $T/fake-se-prompt.txt; tmux send-keys -t '=tp-se:' C-l; sleep 0.5
ge=$(geo se); : > $T/resize.log
PATH=$T/rshim:$PATH refused se "screen not recognised as ready" "a seat at a dialog in an 80x10 pane"
[ "$(steps se)" = "grow shrink " ] && [ "$(geo se)" = "$ge" ] && ok "the seat at a dialog was grown once, then put back ($ge), and nothing was pasted" || { bad "steps for the seat at a dialog ($(steps se); $(geo se), was $ge)"; cat $T/resize.log; }
rm $T/fake-se-prompt.txt; tmux send-keys -t '=tp-se:' C-l; sleep 0.5
# A seat whose session ends mid-delivery: a TERM still runs the whole trap and ends say with 143
# (tl on #132: under set -e the trap stopped at the failing resize-window and say exited 1). se grows
# only after the paste (its check there refuses at 80x10), so it is the Enter that is held up here,
# which keeps the window grown while the session is killed.
mkdir -p $T/kshim && printf '#!/bin/sh\n[ "$1" = send-keys ] && sleep 3\nexec %s "$@"\n' "$(command -v tmux)" > $T/kshim/tmux && chmod +x $T/kshim/tmux
PATH=$T/kshim:$PATH TEAM_ROLE=em $S -c $T/tp.yaml say se "session gone" >$T/se.out 2>&1 & ep=$!
for i in $(seq 1 100); do case "$(tmux display-message -p -t '=tp-se:' '#{window_width}x#{window_height}' 2>/dev/null)" in 220x50) break ;; esac; sleep 0.1; done; sleep 0.5
tmux kill-session -t '=tp-se'; kill -TERM $ep; wait $ep; erc=$?
[ $erc = 143 ] && ok "a say stopped with TERM after its seat's session ended exits 143 (the trap runs to its end)" || { bad "TERM after the session ended (rc=$erc)"; cat $T/se.out; }
$S -c $T/tp.yaml down --yes >/dev/null 2>&1
e2e_end=delivery # the last line: test/e2e.sh checks that the file ran to here
