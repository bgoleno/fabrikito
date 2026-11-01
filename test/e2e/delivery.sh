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
for r in em pp pm pd ph pu pb pf ps pg px pk pq po pn pz ta tb tc td te pv pw py; do roles="$roles  $r: { title: Seat $r, workdir: { type: project, path: $T/proj }, prompt_text: \"$r\" }
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
echo tall > $T/fake-ta-mode.txt; echo tall > $T/fake-te-mode.txt; echo tall-dim > $T/fake-tb-mode.txt; echo tall-typed > $T/fake-tc-mode.txt; echo tall-short > $T/fake-td-mode.txt
echo below > $T/fake-pb-mode.txt; echo prefill > $T/fake-pf-mode.txt; echo swallow > $T/fake-ps-mode.txt
echo suggest > $T/fake-pg-mode.txt; echo mixed > $T/fake-px-mode.txt; echo sticky > $T/fake-pk-mode.txt
echo mention > $T/fake-pn-mode.txt; echo mentionsel > $T/fake-pz-mode.txt
# The diff panel notice (#95), byte for byte as Claude Code 2.1.316 drew it in an 89-column pane on
# 2026-10-31, then the reset its next row starts with. pv: above a whole input box. pw: the same,
# in a pane too short for the box under it (the screen ends at the input row). py: above a dialog.
notice=$(printf '\033[2m\342\225\255%s\033[0m\033[38;5;246m\342\234\225\033[2m\033[39m\342\224\200\342\225\256\n\342\224\202\033[0m \033[38;5;246mResize your terminal to at least 110 columns to show the diff panel\033[39m%19s\033[2m\342\224\202\n\342\225\260%s\342\225\257\n\033[0m' \
  "$(printf '\342\224\200%.0s' $(seq 85))" "" "$(printf '\342\224\200%.0s' $(seq 87))")
printf '%s\n' "$notice" > $T/fake-pv-output.txt; cp $T/fake-pv-output.txt $T/fake-pw-output.txt; echo cut > $T/fake-pw-mode.txt
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
# the end of the text; below 801 characters and 4 lines it is not collapsed to a placeholder. ta..td
# model that box in a 60x16 pane, which shows 3 rows.
for r in ta tb tc td te; do tmux resize-window -t "=tp-$r:" -x 60 -y 16; tmux send-keys -t "=tp-$r:" C-l; done; sleep 1
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
tall ta ok "$(msg 290)" "a message taller than the box (300 characters, 6 rows in a 3-row box)"
tall ta ok "$(msg 790)" "a tall message at the 800-character edge (shown as text)"
tall ta ok "$(msg 791)" "a message one past the edge (801 characters, a placeholder)"
tall ta ok "$(msg 140)"$'\n'"$(msg 140)"$'\n'"$(msg 140)" "a tall message of 3 lines (shown as text)"
tall ta ok "$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)"$'\n'"$(msg 60)" "a message of 4 lines (a placeholder)"
tall tb refused "$(msg 290)" "a tall message with dim text after it"
tall tc refused "$(msg 290)" "a tall message with text typed after it"
tall td refused "$(msg 290)" "the end of a tall message in a box that is not full"
# A full box whose visible end matches but is under 40 characters is too little to go on: refused.
tall te refused "$(msg 50)"$'\n'"ok"$'\n'"go" "a tall message whose visible end is under 40 characters"
$S -c $T/tp.yaml down --yes >/dev/null 2>&1
e2e_end=delivery # the last line: test/e2e.sh checks that the file ran to here
