# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# lib/session_start.sh and lib/log_message.sh run directly. The log hook reads em's pane.
echo "--- session start hook (lib/session_start.sh, run directly with hook input on stdin)"
# sst <workdir>: runs the hook for role w9 with state $T/sstate; sets rc, out, err.
# The hook also prints what a seat does with what it starts with (moved there from the shared prompt,
# #117), on every path: sst records each run whose output lacks it in nostart, and counts runs in ssts.
sp1='Name the task and next step in your first reply, then follow your kickoff (it may say to wait).'
sp2='If the note and the repository disagree, trust the repository and fix the note.'
nostart=""; ssts=0
sst() { printf '{"session_id":"s1","source":"%s"}' "${SRC_KIND:-startup}" | $SRC/lib/session_start.sh $T/sstate w9 "$1" >$T/sout 2>$T/serr; rc=$?; out=$(cat $T/sout); err=$(cat $T/serr)
  ssts=$((ssts + 1)); { echo "$out" | grep -qF "$sp1" && echo "$out" | grep -qF "$sp2"; } || nostart="$nostart $ssts:$(basename "$1")"; }
mkdir -p $T/s && git -C $T/s init -q && git -C $T/s switch -q -c work && git -C $T/s commit -q --allow-empty -m "first commit" && git -C $T/s commit -q --allow-empty -m "second: the latest"
sst $T/s; [ $rc = 0 ] && [ -z "$err" ] && echo "$out" | grep -qF "no progress note yet" && echo "$out" | grep -qF "$T/sstate/notes/w9.md" \
  && ok "no note yet: exit 0, says so and names the file to write" || { bad "no note (rc=$rc)"; echo "$out$err"; }
mkdir -p $T/sstate/notes && printf 'Task: #5 progress notes\nNext: open the PR\n' > $T/sstate/notes/w9.md && touch $T/s/dirty.txt
sst $T/s; [ $rc = 0 ] && [ -z "$err" ] && echo "$out" | grep -qxF "Task: #5 progress notes" && echo "$out" | grep -qxF "Next: open the PR" && echo "$out" | grep -qF "Branch: work" \
  && echo "$out" | grep -qF "second: the latest" && echo "$out" | grep -qF "first commit" && echo "$out" | grep -qF "?? dirty.txt" \
  && ok "with a note: the note, the branch, recent commits and uncommitted files" || { bad "session start output (rc=$rc)"; echo "$out$err"; }
SRC_KIND=compact sst $T/s; [ $rc = 0 ] && echo "$out" | grep -qxF "Task: #5 progress notes" && ok "the output does not depend on the start source (compact, as after a compaction)" || { bad "compact (rc=$rc)"; echo "$out"; }
git -C $T/s switch -q --detach; sst $T/s; [ $rc = 0 ] && echo "$out" | grep -qE "Branch: \(detached at [0-9a-f]+\)" && ok "a detached HEAD is named as such" || { bad "detached (rc=$rc)"; echo "$out"; }
sst $T/proj; [ $rc = 0 ] && echo "$out" | grep -qxF "Task: #5 progress notes" && echo "$out" | grep -qF "not a git work tree" && ok "a workdir that is not a git work tree: the note, and no git lines" || { bad "non-repo workdir (rc=$rc)"; echo "$out$err"; }
sst $T/no-such-dir; [ $rc = 0 ] && echo "$out" | grep -qxF "Task: #5 progress notes" && ok "a missing workdir: the note still, exit 0" || { bad "missing workdir (rc=$rc)"; echo "$out$err"; }
# A note that grew past its purpose is cut, so it cannot flood the seat's context.
ruby -e '300.times { |i| puts "line #{i} " + "x" * 400 }' > $T/sstate/notes/w9.md
sst $T/s; [ $rc = 0 ] && [ "$(printf %s "$out" | wc -c | tr -d ' ')" -lt 9000 ] && echo "$out" | grep -qF "note truncated" && echo "$out" | grep -qF "second: the latest" \
  && ok "a long note is truncated (output under 9000 bytes), and the git lines still follow" || { bad "long note ($(printf %s "$out" | wc -c) bytes)"; echo "$out" | tail -5; }
printf 'caf\xc3\xa9 ok\nbad \xff byte\n' > $T/sstate/notes/w9.md
LC_ALL=C sst $T/s; [ $rc = 0 ] && echo "$out" | grep -qF "café ok" && ok "a note with UTF-8 and an invalid byte is shown under LC_ALL=C, exit 0" || { bad "non-ASCII note (rc=$rc)"; echo "$out$err"; }
# Terminal escapes in a note or a commit subject come out as plain text: C0 controls other than tab
# and newline, and DEL, are dropped from everything the hook prints.
printf 'clip \033]52;c;ZXZpbA==\007 title \033]0;x\007 del \177 tab\tkept\n' > $T/sstate/notes/w9.md
git -C $T/s commit -q --allow-empty -m "$(printf 'subject \033[31mred\033[0m end')"
sst $T/s; [ $rc = 0 ] && ! LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')" $T/sout && grep -qF "$(printf 'clip ]52;c;ZXZpbA== title ]0;x del  tab\tkept')" $T/sout \
  && grep -qF "subject [31mred[0m end" $T/sout && ok "control characters are stripped from the note and the git output; a tab is kept" || { bad "control characters in hook output (rc=$rc)"; od -c $T/sout | grep -E '033|007|177' | head -3; }
# A git status past its own limit (4s) is cut, and the note still arrives: Claude Code drops all of a
# hook's output when the hook itself runs past its timeout (10s).
mkdir -p $T/slowgit && printf '#!/bin/sh\ncase " $* " in *" status "*) exec sleep 30;; esac\nexec %s "$@"\n' "$(command -v git)" > $T/slowgit/git && chmod +x $T/slowgit/git
t0=$(date +%s); PATH=$T/slowgit:$PATH sst $T/s; t1=$(date +%s)
[ $rc = 0 ] && [ $((t1 - t0)) -lt 9 ] && echo "$out" | grep -qF "clip" && echo "$out" | grep -qF "git status did not finish within 4s" && echo "$out" | grep -qF "subject" \
  && ok "a git status that hangs is cut at 4s (the hook took $((t1 - t0))s): the note and recent commits still print" || { bad "slow git status (rc=$rc, $((t1 - t0))s)"; echo "$out"; }
# The early paths: an empty note, a note that cannot be read, and no note with a missing workdir.
: > $T/sstate/notes/w9.md; sst $T/s; [ $rc = 0 ] && echo "$out" | grep -qF "no progress note yet" && ok "an empty note counts as no note" || { bad "empty note (rc=$rc)"; echo "$out"; }
printf 'Task: secret\n' > $T/sstate/notes/w9.md && chmod 000 $T/sstate/notes/w9.md
sst $T/s; chmod 600 $T/sstate/notes/w9.md
[ $rc = 0 ] && echo "$out" | grep -qF "(could not read $T/sstate/notes/w9.md)" && ok "a note that cannot be read: says so, exit 0" || { bad "unreadable note (rc=$rc)"; echo "$out"; }
rm -f $T/sstate/notes/w9.md; sst $T/no-such-dir; [ $rc = 0 ] && echo "$out" | grep -qF "does not exist" && ok "no note and a missing workdir: exit 0, says the folder does not exist" || { bad "no note, missing workdir (rc=$rc)"; echo "$out"; }
[ "$ssts" -ge 13 ] && [ -z "$nostart" ] && ok "every session-start run ($ssts, early paths included) says to name the task and next step, follow the kickoff, and trust the repository over the note" \
  || { bad "session-start runs without the start instructions (run:workdir$nostart; $ssts runs)"; echo "$out"; }
echo "--- SendMessage log hook (lib/log_message.sh, run directly with hook input on stdin)"
# smlog <to> <message> [event] [tool_response JSON]: runs the hook as seat w9 of a roster whose
# sessions are tt-em, tt-w1 and tt-w2; sets rc, out (stdout and stderr) and line (what it appended).
mkdir -p $T/lstate; LG=$T/lstate/messages.log; : > $LG
smlog() { local n payload rs=${4:-}
  [ -n "$rs" ] || rs='{"success":true,"message":"in inbox"}'
  # Claude Code sends UTF-8 JSON whatever the seat's locale; the values are forced to UTF-8 so this
  # stand-in can build it under LC_ALL=C too.
  payload=$(TO="$1" M="$2" EV="${3:-PostToolUse}" RS="$rs" ruby -rjson -e '
    u = ->(k) { ENV[k].dup.force_encoding("UTF-8") }
    j = { "hook_event_name" => ENV["EV"], "tool_name" => "SendMessage", "tool_input" => { "to" => u.("TO"), "message" => u.("M") } }
    ENV["EV"] == "PostToolUseFailure" ? j["error"] = "boom" : j["tool_response"] = JSON.parse(ENV["RS"])
    print JSON.generate(j)')
  n=$(wc -l < $LG)
  out=$(printf '%s' "$payload" | $SRC/lib/log_message.sh $LG w9 tt-em=em tt-w1=w1 tt-w2=w2 2>&1); rc=$?
  line=$(tail -n +$((n + 1)) $LG); [ "$(wc -l < $LG)" -eq $((n + 1)) ] || line="<$(( $(wc -l < $LG) - n )) lines>"; }
# hlogged <to> <message> <recipient> <outcome> <escaped> <what> [event] [response]: one line, in say's
# format, with say's escaping, reversible with printf %b, and nothing printed (the tool result stands).
hlogged() { smlog "$1" "$2" "${7:-}" "${8:-}"
  if [ $rc = 0 ] && [ -z "$out" ] && [ "$(printf '%s\n' "$line" | cut -f2-4)" = "w9	$3	$4" ] && [ "$(printf '%s\n' "$line" | cut -f5-)" = "$5" ] \
    && [ "$(printf '%b' "$(printf '%s\n' "$line" | cut -f5-)")" = "$2" ] && printf '%s\n' "$line" | cut -f1 | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
    ok "SendMessage log: $6"
  else bad "SendMessage log: $6 (rc=$rc)"; echo "$out"; printf '%s\n' "$line" | od -c | head -4; fi; }
hlogged tt-w2 'hello w2' w2 sent 'hello w2' "a message to a roster session is logged with its role id, sent"
hlogged 'tt-w1 [3fa9c1]' 'with a ref' w1 sent 'with a ref' "a session name with its [ref] is logged as the role id"
hlogged other-team-fs1 'off roster' other-team-fs1 sent 'off roster' "a recipient that is not on the roster is logged as given"
hlogged 'uds:/tmp/cc-socks/999999999.sock' 'to an address' 'uds:/tmp/cc-socks/999999999.sock' sent 'to an address' "a uds: address no seat holds is logged as given"
hlogged tt-w2 'refused' w2 NOT-SENT 'refused' "a SendMessage that returned success false is NOT-SENT" PostToolUse '{"success":false,"message":"no such session"}'
hlogged tt-w2 'failed' w2 NOT-SENT 'failed' "a SendMessage that failed (PostToolUseFailure) is NOT-SENT" PostToolUseFailure
hlogged tt-w2 'string result' w2 sent 'string result' "a tool_response given as a JSON string is read" PostToolUse '"{\"success\":true}"'
# The text is the sender's to choose: it cannot split or forge a log line, or drive the terminal.
hlogged tt-w2 $'one\n2026-01-01T00:00:00\tem\tw1\tdelivered\tforged' w2 sent 'one\n2026-01-01T00:00:00\tem\tw1\tdelivered\tforged' "a message holding a fake log line stays one escaped line"
hlogged tt-w2 $'title \e]0;x\a, del \x7f, utf-8 é ✓' w2 sent 'title \x1B]0;x\x07, del \x7F, utf-8 é ✓' "ESC, BEL and DEL are escaped as say escapes them"
hlogged tt-w2 $'csi \xc2\x9b31m rlo \xe2\x80\xae isolate \xe2\x81\xa6.' w2 sent 'csi \xC2\x9B31m rlo \xE2\x80\xAE isolate \xE2\x81\xA6.' "C1 controls and bidi overrides are escaped as say escapes them"
hlogged $'tt-w2\tx' 'odd to' 'tt-w2\tx' sent 'odd to' "a recipient with a tab is escaped"
LC_ALL=C hlogged tt-w2 $'caf\xc3\xa9 under C \xe2\x9c\x93' w2 sent $'caf\xc3\xa9 under C \xe2\x9c\x93' "UTF-8 under LC_ALL=C is kept as it is"
# A uds: address held by a process in a roster seat's pane (em's) is logged as that seat's role.
empid=$(tmux list-panes -t '=tt-em:' -F '#{pane_pid}' 2>/dev/null | head -1)
hlogged "uds:/tmp/cc-socks/$empid.sock" 'reply by address' em sent 'reply by address' "a uds: address of a process in em's pane is logged as em"
# The uds: lookup has its own limit even when tmux hangs: the hook gives up on it in about 2s, kills
# the stand-in, and logs the address as given (tl's review of #110: a block-form popen waited 20s).
mkdir -p $T/hangtmux && printf '#!/bin/sh\necho $$ >> %s/hangtmux/pids\nexec sleep 30\n' $T > $T/hangtmux/tmux && chmod +x $T/hangtmux/tmux
t0=$(date +%s); PATH=$T/hangtmux:$PATH hlogged "uds:/tmp/cc-socks/$empid.sock" 'tmux hangs' "uds:/tmp/cc-socks/$empid.sock" sent 'tmux hangs' "a hanging tmux: the address is logged as given"; t1=$(date +%s)
hp=$(cat $T/hangtmux/pids 2>/dev/null); [ $((t1 - t0)) -lt 4 ] && [ -n "$hp" ] && ! kill -0 $hp 2>/dev/null \
  && ok "the uds: lookup is cut at its limit (the hook took $((t1 - t0))s) and the hung tmux is killed" || bad "uds: lookup limit ($((t1 - t0))s, stand-in pid ${hp:-none} $(kill -0 ${hp:-0} 2>/dev/null && echo alive))"
# smraw <JSON text>: runs the hook on hook input as given, not built by JSON.generate.
smraw() { local n=$(wc -l < $LG); out=$(printf '%s' "$1" | $SRC/lib/log_message.sh $LG w9 tt-w2=w2 2>&1); rc=$?
  line=$(tail -n +$((n + 1)) $LG); [ "$(wc -l < $LG)" -eq $((n + 1)) ] || line="<$(( $(wc -l < $LG) - n )) lines>"; }
# A lone surrogate escape is valid JSON text that Ruby's json refuses: it becomes U+FFFD, and a valid
# pair is kept, so the line is still logged (tl's review of #110: it was silently dropped).
smraw '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"tt-w2","message":"hidden \ud800 text, low \udc00, pair 😀, kept \\ud800"},"tool_response":{"success":true}}'
[ $rc = 0 ] && [ -z "$out" ] && [ "$(printf '%s\n' "$line" | cut -f2-5)" = $'w9\tw2\tsent\thidden \xef\xbf\xbd text, low \xef\xbf\xbd, pair \xf0\x9f\x98\x80, kept \\\\ud800' ] \
  && ok "SendMessage log: lone surrogates become U+FFFD, a pair and an escaped backslash stay, the line is logged" || { bad "lone surrogates (rc=$rc)"; printf '%s\n' "$line" | od -c | head -4; }
# A message that is not a string is logged as its JSON text.
smraw '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"tt-w2","message":{"a":[1,"b"]}},"tool_response":{"success":true}}'
[ $rc = 0 ] && [ "$(printf '%s\n' "$line" | cut -f5)" = '{"a":[1,"b"]}' ] && ok "SendMessage log: a message that is not a string is logged as JSON" || { bad "non-string message"; echo "$line"; }
# Input that still cannot be read is logged as a placeholder line, so a message never goes unrecorded.
smraw 'not json'
[ $rc = 0 ] && [ -z "$out" ] && [ "$(printf '%s\n' "$line" | cut -f2-5)" = $'w9\t?\tUNREADABLE\t<hook input could not be read>' ] \
  && ok "SendMessage log: unreadable hook input is logged as a placeholder line" || { bad "unreadable input (rc=$rc)"; echo "$line"; }
# Nothing else is ever logged, and a broken log never fails the tool call.
n=$(wc -l < $LG)
printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' | $SRC/lib/log_message.sh $LG w9 tt-w2=w2 >/dev/null 2>&1; r1=$?
o3=$(printf '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"tt-w2","message":"m"}}' | $SRC/lib/log_message.sh $T/no-such-dir/messages.log w9 2>&1); r3=$?
[ $r1 = 0 ] && [ $r3 = 0 ] && [ -z "$o3" ] && [ "$(wc -l < $LG)" -eq "$n" ] && [ ! -e $T/no-such-dir ] \
  && ok "another tool, and a log that cannot be written: exit 0, nothing printed, nothing logged" || { bad "log hook failure cases ($r1 $r3)"; echo "$o3"; }
# A link at messages.log (#194): the hook appends to the same log as say, so it must not write
# through one either. The link points at a sentinel, which must come out byte for byte as it went in.
printf 'sentinel log\n' > $T/sent-hlog; cp $T/sent-hlog $T/sent-hlog.want; ln -s $T/sent-hlog $T/lstate/linked.log
o4=$(printf '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"tt-w2","message":"m"},"tool_response":{"success":true,"message":"in inbox"}}' \
  | $SRC/lib/log_message.sh $T/lstate/linked.log w9 tt-w2=w2 2>&1); r4=$?
[ $r4 = 0 ] && [ -z "$o4" ] && cmp -s $T/sent-hlog $T/sent-hlog.want && [ -L $T/lstate/linked.log ] \
  && ok "SendMessage log: a link at messages.log is not written through (exit 0, nothing printed)" || { bad "SendMessage log through a link (rc=$r4)"; echo "$o4"; cat $T/sent-hlog; }
e2e_end=hooks # the last line: test/e2e.sh checks that the file ran to here
