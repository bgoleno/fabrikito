# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# say: delivery to a seat, the kickoff label, titles, the messages.log line, an empty message refused (#157).
echo "--- say"
TEAM_ROLE=em $S -c $T/team.yaml say w1 "hello w1 from em" && sleep 1
echo "--- kickoff label"
# The kickoff reaches a seat as its first user message, so it carries a label that says it is team
# configuration: unlabelled input is how a seat recognises the owner typing.
head -c 16 $T/state/prompts/em.kickoff | grep -qxF "[from launcher] " && ok "the rendered kickoff starts with [from launcher]" || { bad "kickoff file label"; head -2 $T/state/prompts/em.kickoff; }
grep -qF "[from launcher] Team session started: you are the Manager (session tt-em)." $T/args.log && grep -qF "[from launcher] Team session started: you are the Worker One (session tt-w1)." $T/args.log && ok "the kickoff each stand-in seat received starts with [from launcher]" || { bad "kickoff received label"; grep -F "Team session started" $T/args.log; }
kchk=$($S -c $T/team.yaml check 2>&1)
echo "$kchk" | grep -qF "[em] [from launcher] Team session started: you are the Manager" && echo "$kchk" | grep -qF "not the owner's voice" && ok "check shows each seat's kickoff with its label" || { bad "check: kickoff"; echo "$kchk" | grep -n -i -A3 kickoff; }
kout=$(TEAM_ROLE=launcher $S -c $T/team.yaml say w1 "pretend kickoff" 2>&1); rc=$?
[ $rc != 0 ] && echo "$kout" | grep -qF "reserved" && ! tmux capture-pane -p -t '=tt-w1:' | grep -q "pretend kickoff" && ok "say refuses to send as launcher (only the launcher's kickoff carries that label)" || { bad "say as launcher (rc=$rc)"; echo "$kout"; }
tmux capture-pane -p -t '=tt-w1:' | grep -q "from em\] hello w1" && ok "message arrived in w1's pane" || bad "message arrived"
keytext $T/keys-w1.log 2>/dev/null | grep -q "from em\] hello w1" && ok "the stand-in logged the submitted message (the key log works)" || bad "key log of w1"
tmux show-options -t '=tt-w1:' set-titles-string | grep -q 'set-titles-string "w1 | Worker One | tt-w1"' && ok "pane title set at startup: role | title | session" || bad "pane title at startup"
tmux set-option -t '=tt-w1:' set-titles-string "stale" && $S -c $T/team.yaml titles >/dev/null && tmux show-options -t '=tt-w1:' set-titles-string | grep -q '"w1 | Worker One | tt-w1"' && ok "titles command repairs a changed title" || bad "titles command"
# logged <to> <outcome> <message> <escaped> <what>: one say writes exactly one log line, whose
# message field is <escaped>, and printf %b of that field gives back the message (the format in docs/messaging.md).
logged() {
  local n line
  n=$(wc -l < $T/state/messages.log)
  TEAM_ROLE=em $S -c $T/team.yaml say "$1" "$3" >/dev/null 2>&1; sleep 1
  line=$(tail -n +$((n + 1)) $T/state/messages.log)
  if [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && [ "$(printf '%s\n' "$line" | cut -f2-4)" = "em	$1	$2" ] &&
    [ "$(printf '%s\n' "$line" | cut -f5-)" = "$4" ] && [ "$(printf '%b' "$(printf '%s\n' "$line" | cut -f5-)")" = "$3" ]; then
    ok "log: $5 is one line, escaped and reversible"
  else bad "log: $5"; printf '%s\n' "$line" | od -c | head -5; fi
}
logged w1 delivered $'first line\nsecond line' 'first line\nsecond line' "a multi-line message"
logged w2 NOT-DELIVERED $'col a\tcol b' 'col a\tcol b' "a message with a tab"
logged w2 NOT-DELIVERED $'cr\r and a literal \\n, \\t and \\\\' 'cr\r and a literal \\n, \\t and \\\\' "a message with a CR and literal backslashes"
# Other controls are escaped so tail cannot be driven by a message (this one would retitle the
# terminal); UTF-8 is left as it is. w2 is down, so nothing reaches a pane.
logged w2 NOT-DELIVERED $'title \e]0;x\a, del \x7f, utf-8 é ✓' 'title \x1B]0;x\x07, del \x7F, utf-8 é ✓' "a message with ESC, BEL and DEL"
logged all delivered $'to all,\nfrom em' 'to all,\nfrom em' "a multi-line say all"
# C1 controls (CSI, OSC, ST) and bidi overrides are escaped by code point, as their UTF-8 bytes.
logged w2 NOT-DELIVERED $'csi \xc2\x9b31m osc \xc2\x9d0;x\xc2\x9c rlo \xe2\x80\xae isolate \xe2\x81\xa6.' 'csi \xC2\x9B31m osc \xC2\x9D0;x\xC2\x9C rlo \xE2\x80\xAE isolate \xE2\x81\xA6.' "a message with C1 controls and bidi overrides"
logged w2 NOT-DELIVERED $'not utf-8: \x9b, \xff' 'not utf-8: \x9B, \xFF' "a message that is not valid UTF-8"
# say delivers a message body with control bytes as plain text. What the seat receives for one say is two
# pastes (the label, then the body) and the Enter: four ESC, all of them the paste marks, and one CR, the
# Enter. A control byte of the body other than a tab or a newline is not sent: an ESC there could end the
# paste early or drive the seat's terminal, and a CR is an Enter. The printable text arrives as it was, the
# message is delivered, and the log keeps the message as it was given, escaped.
ctl_say() { # ctl_say <what> <body> <the text the seat must receive>
  local k0 n rc esc cr other line
  k0=$(wc -c < $T/keys-w1.log | tr -d ' '); n=$(wc -l < $T/state/messages.log)
  TEAM_ROLE=em $S -c $T/team.yaml say w1 "$2" >/dev/null 2>&1; rc=$?; sleep 1
  tail -c +$((k0 + 1)) $T/keys-w1.log > $T/ctl-keys
  esc=$(LC_ALL=C tr -cd '\033' < $T/ctl-keys | wc -c | tr -d ' '); cr=$(LC_ALL=C tr -cd '\r' < $T/ctl-keys | wc -c | tr -d ' ')
  other=$(keytext $T/ctl-keys | LC_ALL=C tr -d '\r' | LC_ALL=C tr -cd '\000-\010\013-\037\177' | wc -c | tr -d ' ')
  line=$(tail -n +$((n + 1)) $T/state/messages.log)
  if [ $rc = 0 ] && [ "$esc" = 4 ] && [ "$cr" = 1 ] && [ "$other" = 0 ] && [ "$(keytext $T/ctl-keys | LC_ALL=C tr -d '\r')" = "[from em] $3" ] \
    && [ "$(printf '%s\n' "$line" | cut -f2-4)" = "em	w1	delivered" ] && [ "$(printf '%b' "$(printf '%s\n' "$line" | cut -f5-)")" = "$2" ]; then
    ok "say delivers $1 as plain text: two pastes and one Enter reach the seat, and the log keeps the message as given"
  else bad "say with $1 (rc=$rc, ESC=$esc, CR=$cr, other controls=$other)"; od -c $T/ctl-keys | head -6; printf '%s\n' "$line" | cut -c1-200
    # A say that was refused after its paste leaves the text in the box, where it would fail every later
    # case that sends to w1: submit it, so one failure here stays one failure.
    tmux send-keys -t '=tt-w1:' Enter; sleep 1; fi
}
ctl_say "a body that holds ESC, an end-of-paste mark, BEL, CR and DEL" $'ctl \e[201~after \e]0;t\a cr\rdel\x7f end' 'ctl [201~after ]0;t crdel end'
ctl_say "a body that holds C1 controls (CSI and OSC as code points)" $'c1 \xc2\x9b31m and \xc2\x9d0;t\xc2\x9c, utf-8 é ✓ kept' 'c1 31m and 0;t, utf-8 é ✓ kept'
# A body that is not valid UTF-8 is refused before anything is pasted. No byte of it reaches the seat, so
# the C1 controls written as UTF-8 in it do not either, and nothing is left in the seat's box.
k0=$(wc -c < $T/keys-w1.log | tr -d ' '); n=$(wc -l < $T/state/messages.log)
out=$(TEAM_ROLE=em $S -c $T/team.yaml say w1 $'bad \xff byte, c1 \xc2\x9b31m and \xc2\x9d0;t\xc2\x9c' 2>&1); rc=$?; sleep 1
line=$(tail -n +$((n + 1)) $T/state/messages.log)
if [ $rc -ne 0 ] && [ "$(wc -c < $T/keys-w1.log | tr -d ' ')" = "$k0" ] && echo "$out" | grep -qF "not valid UTF-8" && [ "$(printf '%s\n' "$line" | cut -f2-4)" = "em	w1	NOT-DELIVERED" ]; then
  ok "say refuses a body that is not valid UTF-8, with C1 controls written as UTF-8 in it, before any paste: no byte reaches the seat, logged NOT-DELIVERED"
else bad "say with a body that is not valid UTF-8 (rc=$rc)"; echo "$out" | tail -2; tail -c +$((k0 + 1)) $T/keys-w1.log | od -c | head -4; printf '%s\n' "$line" | cut -c1-200
  tmux send-keys -t '=tt-w1:' Enter; sleep 1; fi
# An empty or whitespace-only message is refused before any tmux call (#157), instead of a bare label
# going out as a turn of its own. A tmux stand-in first on PATH logs each call and runs the real tmux,
# so a say that did reach tmux would deliver as before and fail here.
mkdir -p $T/tmuxlog && printf '#!/bin/sh\necho "$*" >> %s/tmuxlog.log\nexec %s "$@"\n' $T "$(command -v tmux)" > $T/tmuxlog/tmux && chmod +x $T/tmuxlog/tmux
# no_message <what> <from, or - for TEAM_ROLE unset> <to> <message...>: refused, no tmux call, no key to
# any seat, one NOT-DELIVERED line (sender '?' when TEAM_ROLE is unset: telling a seat from the owner takes tmux).
no_message() {
  local what=$1 lf=$2 to=$3 n k out rc calls line
  shift 3
  n=$(wc -l < $T/state/messages.log); k=$(cat $T/keys-*.log 2>/dev/null | wc -c); : > $T/tmuxlog.log
  if [ "$lf" = - ]; then lf='?'; out=$(env -u TEAM_ROLE "PATH=$T/tmuxlog:$PATH" $S -c $T/team.yaml say "$to" "$@" 2>&1); rc=$?
  else out=$(env "PATH=$T/tmuxlog:$PATH" TEAM_ROLE="$lf" $S -c $T/team.yaml say "$to" "$@" 2>&1); rc=$?; fi
  sleep 1; calls=$(wc -l < $T/tmuxlog.log | tr -d ' '); line=$(tail -n +$((n + 1)) $T/state/messages.log)
  if [ $rc != 0 ] && [ "$calls" = 0 ] && echo "$out" | grep -qF "not delivered: the message is empty" && [ "$(cat $T/keys-*.log 2>/dev/null | wc -c)" = "$k" ] &&
    [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && [ "$(printf '%s\n' "$line" | cut -f2-4)" = "$lf	$to	NOT-DELIVERED" ]; then
    ok "say refuses $what before any tmux call: no keys, logged NOT-DELIVERED"
  else bad "say $what (rc=$rc, tmux calls=$calls)"; echo "$out" | tail -3; printf '%s\n' "$line"; fi
}
no_message "an empty message to one seat" em w1 ""
no_message "a message of spaces to one seat" em w1 "   "
no_message "a message of a tab and a newline to one seat" em w1 $'\t\n'
no_message "an empty message to all" em all ""
no_message "a message of spaces to all" em all "   "
no_message "an empty message with TEAM_ROLE unset" - w1 ""
# Several empty arguments (tl on #202): bash 3.2 puts \177 for each in "${*:2}", which is not
# whitespace, while say sends and logs "$*", which is.
no_message "two empty arguments to one seat" em w1 "" ""
no_message "spaces and an empty argument to one seat" em w1 "   " ""
# No tracked file may hold a bidi embedding, override or isolate character itself (Trojan Source):
# the escaper names those ranges with ASCII \u escapes, and so must anything else.
bidi=$(cd $SRC && git ls-files -z | xargs -0 ruby --disable-gems -e 'ARGV.each { |f| next unless File.file?(f); File.binread(f).each_line.with_index(1) { |l, i| puts "#{f}:#{i}" if l =~ /\xE2\x80[\xAA-\xAE]|\xE2\x81[\xA6-\xA9]/n } }')
[ -z "$bidi" ] && ok "no tracked file contains a bidi control character" || { bad "bidi control characters in: $bidi"; }
# Outside a UTF-8 locale (a script, cron, env -i) ruby reads its -e program as US-ASCII, so the
# escaper's source must be ASCII: the field is escaped, not the failure marker.
n=$(wc -l < $T/state/messages.log)
LC_ALL=C TEAM_ROLE=em $S -c $T/team.yaml say w2 $'c locale: csi \xc2\x9b, e-acute \xc3\xa9' >/dev/null 2>&1
[ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && [ "$(tail -1 $T/state/messages.log | cut -f5-)" = $'c locale: csi \\xC2\\x9B, e-acute \xc3\xa9' ] &&
  ok "log: under LC_ALL=C the message is escaped, not logged as a failure" || { bad "log: LC_ALL=C"; tail -1 $T/state/messages.log; }
# Prompt and team files are read as UTF-8 whatever the locale (#72). say validates the team file,
# which renders every prompt, so a non-ASCII prompt or kickoff must not stop it under LC_ALL=C.
# A prompt file, not prompt_text: YAML hands back UTF-8 strings in any locale, a plain read does not.
printf 'em prompt, caf\xc3\xa9 \xe2\x80\xa6\n' > $T/em-u.md
EMU=$T/em-u.md ruby -pe 'sub(/prompt_text: "em prompt"/) { "prompt: #{ENV["EMU"]}, kickoff: \"start, caf\u00e9 \u2026\"" }' $T/team.yaml > $T/team-u.yaml
n=$(wc -l < $T/state/messages.log)
LC_ALL=C TEAM_ROLE=em $S -c $T/team-u.yaml say w2 'from a team with a non-ASCII prompt' >/dev/null 2>&1
[ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && tail -1 $T/state/messages.log | grep -qF "from a team with a non-ASCII prompt" \
  && ok "say under LC_ALL=C with a non-ASCII prompt in the team" || { bad "say under LC_ALL=C with a non-ASCII prompt"; tail -1 $T/state/messages.log; }
LC_ALL=C ruby $SRC/lib/team_config.rb $T/team-u.yaml render em 2>&1 | grep -qF $'em prompt, caf\xc3\xa9 \xe2\x80\xa6' \
  && LC_ALL=C ruby $SRC/lib/team_config.rb $T/team-u.yaml kickoff em 2>&1 | grep -qxF $'[from launcher] start, caf\xc3\xa9 \xe2\x80\xa6' \
  && ok "a non-ASCII prompt and kickoff come out byte for byte under LC_ALL=C" || bad "non-ASCII prompt or kickoff under LC_ALL=C"
# Non-ASCII values from outside the team file too (#82): environment values, the home folder and the
# team file's own folder are tagged by the locale, and under LC_ALL=C or with no locale a non-ASCII
# byte in one stopped render (subst), settings (JSON) and check. The workdir and owner come from the
# team file, which lives in a non-ASCII folder.
E=$'\xc3\xa9'; mkdir -p "$T/dir$E" "$T/proj$E" "$T/home$E" "$T/state$E"; NT="$T/dir$E/team.yaml"
E=$E P="$T/proj$E" ruby -pe '$_ = "owner: \"Zo#{ENV["E"]}\"\n" + $_ if $_.start_with?("team: ")
  sub(/workdir: \{ type: project, path: \S+ \}, prompt_text: "em prompt"/) { %Q(workdir: { type: project, path: "#{ENV["P"]}" }, prompt_text: "em @@OWNER@@ @@WORKDIR@@ @@SCRIPT@@ @@LOG@@") }' $T/team.yaml > "$NT"
# rn <C | none> <command> [VAR=value ...]: team_config.rb on that team under LC_ALL=C, or with no
# locale at all (env -i: no LANG, no LC_*), with non-ASCII values for the variables it reads.
rn() { local l=$1 c=$2; shift 2
  set -- HOME="$T/home$E" TEAM_STATE_DIR="$T/state$E" TEAM_SCRIPT="$T/dir$E/fabrikito" TEAM_LOG="$T/state$E/messages.log" \
    CLAUDE_CONFIG_DIR="$T/home$E/.claude" "$@"
  # PATH is passed as one word: it can hold spaces.
  if [ $l = C ]; then env LC_ALL=C "$@" ruby $SRC/lib/team_config.rb "$NT" $c em 2>&1
  else env -i PATH="$PATH" "$@" ruby $SRC/lib/team_config.rb "$NT" $c em 2>&1; fi; }
for l in C none; do
  out=$(rn $l render); echo "$out" | grep -qxF "em Zo$E $T/proj$E $T/dir$E/fabrikito $T/state$E/messages.log" \
    && ok "non-ASCII owner, workdir, TEAM_SCRIPT and TEAM_LOG render byte for byte ($l)" || { bad "non-ASCII render ($l)"; echo "$out" | tail -2; }
  out=$(rn $l kickoff); echo "$out" | grep -qF "or Zo$E." && ok "the kickoff names the non-ASCII owner ($l)" || { bad "non-ASCII kickoff ($l)"; echo "$out" | tail -2; }
  out=$(rn $l settings); echo "$out" | ruby -rjson -e 'd = JSON.parse(STDIN.read)["permissions"]["deny"]; exit(ARGV.all? { |w| d.include?(w) } ? 0 : 1)' \
    "Edit(/$T/proj$E/.claude/settings.json)" "Edit(/$T/state$E/settings/**)" "Edit(/$T/home$E/.claude/settings.json)" "Edit(/$NT)" \
    && ok "settings with a non-ASCII workdir, state folder, home, config folder and team file folder ($l)" || { bad "non-ASCII settings ($l)"; echo "$out" | tail -2; }
  out=$(rn $l permissions_report); [ $? = 0 ] && echo "$out" | grep -qF "[em]" && ok "check's permission report with a non-ASCII home ($l)" || { bad "non-ASCII permissions_report ($l)"; echo "$out" | tail -2; }
done
# Invalid UTF-8 from outside is an error that names where it came from, not a Ruby backtrace.
out=$(rn C render TEAM_SCRIPT=$'/x/\xff/fabrikito'); [ $? != 0 ] && echo "$out" | grep -qF "the environment variable TEAM_SCRIPT is not valid UTF-8" && ! echo "$out" | grep -q "Error)" \
  && ok "an environment value that is not UTF-8 is refused, naming the variable" || { bad "invalid TEAM_SCRIPT"; echo "$out" | tail -2; }
out=$(rn none settings HOME=$'/tmp/x\xff'); [ $? != 0 ] && echo "$out" | grep -qF "the home folder (HOME) is not valid UTF-8" && ! echo "$out" | grep -q "Error)" \
  && ok "a home folder that is not UTF-8 is refused, naming HOME" || { bad "invalid HOME"; echo "$out" | tail -2; }
# say validates and renders the whole team before it sends: from that team, under both locales.
# env -i drops the tmux guard's variables with the rest, and the guard then refuses every call (#307), so
# they are passed on beside TMUX_TMPDIR.
for l in C none; do
  n=$(wc -l < $T/state/messages.log)
  if [ $l = C ]; then LC_ALL=C HOME="$T/home$E" TEAM_ROLE=em $S -c "$NT" say w2 "from a non-ASCII team ($l)" >/dev/null 2>&1
  else env -i PATH="$PATH" HOME="$T/home$E" TMUX_TMPDIR="$TMUX_TMPDIR" TMUX_GUARD_ROOTS="$TMUX_GUARD_ROOTS" TMUX_GUARD_LOG="$TMUX_GUARD_LOG" TEAM_STATE_DIR="$TEAM_STATE_DIR" TEAM_ROLE=em $S -c "$NT" say w2 "from a non-ASCII team ($l)" >/dev/null 2>&1; fi
  [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && tail -1 $T/state/messages.log | grep -qF "from a non-ASCII team ($l)" \
    && ok "say from a team with a non-ASCII workdir, owner and home ($l)" || { bad "say from a non-ASCII team ($l)"; tail -1 $T/state/messages.log; }
done
# What the file system returns is tagged by the locale too (#360): outside a UTF-8 locale a listed name
# with a non-ASCII byte came back as a binary string, which is never equal to the UTF-8 path of the team's
# own state folder, cannot be joined to a folder with a non-ASCII name and cannot be normalized, and the
# mount table came back as US-ASCII. The state folder above is empty, so nothing takes it for a team's
# state and those cases never met this. up fills it (settings/, launch/, prompts/), and from then on
# every command that loads the team file ended in a Ruby backtrace.
# The four names below steer the helpers. A caller's own value would change what the cases compare (with
# NRL exported, the UTF-8 locale with itself), so none comes in from the environment (tl on #362).
unset NRL NRD NSL NSANY
# nr <C | latin1 | none> <team file> <command> [VAR=value ...]: as rn, on any team file and without this
# run's TEAM_STATE_DIR; latin1 is en_US.ISO8859-1. With NRL set it runs under that locale instead: the
# UTF-8 reference, same environment. With NRD set it runs in that folder (for a relative team file path).
nr() { local l=$1 f=$2 c=$3 loc=C; shift 3
  set -- HOME="$T/home$E" CLAUDE_CONFIG_DIR="$T/home$E/.claude" "$@"
  [ $l = latin1 ] && loc=en_US.ISO8859-1
  ( [ -z "${NRD:-}" ] || cd "$NRD" || exit 1
    if [ $l = none ]; then env -i PATH="$PATH" ${NRL:+LC_ALL=$NRL} "$@" ruby $SRC/lib/team_config.rb "$f" $c em 2>&1
    else env -u TEAM_STATE_DIR LC_ALL=${NRL:-$loc} "$@" ruby $SRC/lib/team_config.rb "$f" $c em 2>&1; fi ); }
# nsame <what> <team file> <lines the output must hold, one a line> [VAR=value ...]: validate, check's
# report and em's settings come out under LC_ALL=C and with no locale exactly as under a UTF-8 locale,
# each status included, with no Ruby error and with those lines (an empty line asks for nothing). NSL
# names other locales to run under, in nr's words.
nsame() { local what=$1 f=$2 want=$3 l c w out ref good; shift 3
  for l in ${NSL:-C none}; do
    out=$(for c in validate permissions_report settings; do nr $l "$f" $c "$@"; echo "$c: status $?"; done)
    ref=$(for c in validate permissions_report settings; do NRL=en_US.UTF-8 nr $l "$f" $c "$@"; echo "$c: status $?"; done)
    good=1; [ "$out" = "$ref" ] && { [ -n "${NSANY:-}" ] || ! echo "$out" | grep -q 'Error)'; } || good=0
    while IFS= read -r w; do echo "$out" | grep -qF -- "$w" || good=0; done <<< "$want"
    [ $good = 1 ] && ok "$what ($l)" || { bad "$what ($l)"; echo "$out" | grep -E 'Error\)|status|^other teams|^skipped|^team config error' | head -8; }
  done; }
nf() { mkdir -p "$1/settings" "$1/launch" "$1/prompts"; } # what up leaves in a state folder
NA=$T/na; nf "$NA/alone/s$E"; nf "$NA/two/s$E"; nf "$NA/two/other"; nf "$NA/beside/own"; nf "$NA/beside/o$E"
nsame "a filled state folder with a non-ASCII name, alone in its parent, is the team's own" "$NT" "validate: status 0
other teams: none" TEAM_STATE_DIR="$NA/alone/s$E"
nsame "a filled state folder with a non-ASCII name beside another team's" "$NT" "validate: status 0
other teams: $NA/two/other (found)" TEAM_STATE_DIR="$NA/two/s$E"
nsame "another team's state folder with a non-ASCII name is found and denied" "$NT" "validate: status 0
other teams: $NA/beside/o$E (found)
\"Edit(/$NA/beside/o$E/**)\"" TEAM_STATE_DIR="$NA/beside/own"
# Under a locale that is neither UTF-8 nor C the fault was silent: every command exited 0, and the other
# team's folder was not found, so the seats got no deny for it (tl and sec2 on #362).
NSL=latin1 nsame "another team's state folder with a non-ASCII name is found and denied, as under a UTF-8 locale" "$NT" "validate: status 0
other teams: $NA/beside/o$E (found)
\"Edit(/$NA/beside/o$E/**)\"" TEAM_STATE_DIR="$NA/beside/own"
# The team file's own path comes from the command line, which the locale tags whatever the line in the
# parser says, and a relative one is joined to the working folder, which that line makes UTF-8: the two
# must not meet before the argument is read as UTF-8 too (tl on #362).
nf "$NA/plain/own"
NRD="$T/dir$E" nsame "a team file named by a relative path with a non-ASCII character, from a folder with one" "../dir$E/team.yaml" "validate: status 0
other teams: none" TEAM_STATE_DIR="$NA/plain/own"
# A state root with a non-ASCII name: joining any listed non-ASCII name to it raised, a plain file's too.
nf "$NA/root$E/s$E"; nf "$NA/root$E/o$E"; : > "$NA/root$E/note$E.txt"
nsame "a state root with a non-ASCII name that holds non-ASCII names" "$NT" "validate: status 0
other teams: $NA/root$E/o$E (found)" TEAM_STATE_DIR="$NA/root$E/s$E"
# A link is compared by its real path before anything says what it leads to.
nf "$NA/link/own"; ln -s "$NA/link/own" "$NA/link/l$E"
nsame "a link with a non-ASCII name to the team's own state folder is passed over" "$NT" "validate: status 0
skipped   : $NA/link/l$E (a symlink to this team's own state folder, or to a folder holding it)" TEAM_STATE_DIR="$NA/link/own"
# state: lists the folder it names when that is not a team's state yet (validate_state_key).
mkdir -p "$NA/key$E/c$E"; nf "$NA/held$E/c$E"
{ printf 'state: "%s"\n' "$NA/key$E"; cat "$NT"; } > "$NA/key.yaml"; { printf 'state: "%s"\n' "$NA/held$E"; cat "$NT"; } > "$NA/held.yaml"
nsame "state: a folder with a non-ASCII name that holds one" "$NA/key.yaml" "validate: status 0"
nsame "state: a folder with a non-ASCII name that holds a team's state is refused, naming both" "$NA/held.yaml" "validate: status 1
state: $NA/held$E holds another team's state folder ($NA/held$E/c$E)"
# state: on a volume is looked up in the mount table. The stand-in prints $NA/mounts: volumes no machine has.
mkdir -p "$NA/bin"; printf '#!/bin/sh\ncat "%s"\n' "$NA/mounts" > "$NA/bin/mount"; chmod +x "$NA/bin/mount"
{ printf 'state: "%s"\n' "/Volumes/e2e-V$E/st"; cat "$NT"; } > "$NA/vol.yaml"
printf '/dev/disk9s1 on /Volumes/e2e-V\303\251 (apfs, local)\n' > "$NA/mounts"
nsame "state: on a mounted volume with a non-ASCII name" "$NA/vol.yaml" "validate: status 0" PATH="$NA/bin:$PATH"
# A name that is not valid UTF-8 (tl on #360) is read as under a UTF-8 locale too, so the result is that
# locale's. In the mount table: a volume listed beside it is still found, and one not listed is still
# not mounted.
printf '/dev/disk8s1 on /Volumes/e2e-\377 (apfs, local)\n/dev/disk9s1 on /Volumes/e2e-V\303\251 (apfs, local)\n' > "$NA/mounts"
nsame "state: the volume is found in a mount table that holds a name that is not valid UTF-8" "$NA/vol.yaml" "validate: status 0" PATH="$NA/bin:$PATH"
printf '/dev/disk8s1 on /Volumes/e2e-\377 (apfs, local)\n' > "$NA/mounts"
nsame "state: a volume missing from a mount table that holds a name that is not valid UTF-8 is not mounted" "$NA/vol.yaml" "validate: status 1
state: /Volumes/e2e-V$E/st is on /Volumes/e2e-V$E, which is not mounted" PATH="$NA/bin:$PATH"
# In a listing: a folder with such a name that holds a team's state, beside the team's own. APFS and most
# disks refuse the name, and then there is nothing to list; where a disk takes it, the outcome only has
# to be the UTF-8 locale's, whatever that is (NSANY: a Ruby error there is compared, not refused).
nf "$NA/bad/own"
if nf "$NA/bad/o"$'\xff' 2>/dev/null; then NSANY=1 nsame "a listed name that is not valid UTF-8 gives the UTF-8 locale's result" "$NT" "" TEAM_STATE_DIR="$NA/bad/own"
else for l in C none; do ok "a listed name that is not valid UTF-8: this disk refuses such a name, so nothing was compared ($l)"; done; fi
# Through the launcher: every command validates the team file first.
out=$(LC_ALL=C HOME="$T/home$E" TEAM_STATE_DIR="$NA/alone/s$E" $S -c "$NT" check 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qxF "other teams: none" && ! echo "$out" | grep -q 'Error)' \
  && ok "check under LC_ALL=C with a filled state folder whose name is not ASCII" || { bad "check under LC_ALL=C, filled non-ASCII state folder (rc=$rc)"; echo "$out" | tail -3; }
# The sender comes from TEAM_ROLE, which nothing validates: it is escaped like the message.
n=$(wc -l < $T/state/messages.log)
TEAM_ROLE=$'e\tm\nx' $S -c $T/team.yaml say w2 "from an odd sender" >/dev/null 2>&1
[ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && [ "$(tail -1 $T/state/messages.log | cut -f2-5)" = 'e\tm\nx	w2	NOT-DELIVERED	from an odd sender' ] &&
  ok "log: a TEAM_ROLE with a tab and a newline is escaped, one line" || { bad "log: odd TEAM_ROLE"; tail -2 $T/state/messages.log | od -c | head -6; }
echo "--- say never writes messages.log through a link (#194)"
# A seat could put a link at messages.log after up; every say's line would then be appended
# wherever it points. say refuses before it delivers (fail closed) and says the line was not
# written. The link points at a sentinel, which must come out byte for byte as it went in.
printf 'sentinel log\n' > $T/sent-log; cp $T/sent-log $T/sent-log.want
mv $T/state/messages.log $T/msglog.real && ln -s $T/sent-log $T/state/messages.log
lout=$(TEAM_ROLE=em $S -c $T/team.yaml say w1 "through a linked log" 2>&1); rc=$?; sleep 1
rm $T/state/messages.log && mv $T/msglog.real $T/state/messages.log
[ $rc != 0 ] && cmp -s $T/sent-log $T/sent-log.want && echo "$lout" | grep -qF "$T/state/messages.log is a symlink" && echo "$lout" | grep -qF "could not be written" \
  && tmux has-session -t '=tt-w1' 2>/dev/null && ! tmux capture-pane -p -t '=tt-w1:' | grep -q "through a linked log" \
  && ok "say: a link at messages.log is refused, nothing is delivered or written through it, and say says the line was not written" || { bad "say through a linked log (rc=$rc)"; echo "$lout"; cat $T/sent-log; }
# A hard link is a regular file to [ -L ], [ -p ] and [ -f ] (tl on #206): say refuses a second link.
mv $T/state/messages.log $T/msglog.real && ln $T/sent-log $T/state/messages.log
lout=$(TEAM_ROLE=em $S -c $T/team.yaml say w1 "through a hard-linked log" 2>&1); rc=$?; sleep 1
rm $T/state/messages.log && mv $T/msglog.real $T/state/messages.log
[ $rc != 0 ] && cmp -s $T/sent-log $T/sent-log.want && echo "$lout" | grep -qF "$T/state/messages.log is a symlink, a FIFO or a hard link" && echo "$lout" | grep -qF "could not be written" && echo "$lout" | grep -qF "Do not delete this file: it may be the real one, with a second name made elsewhere. Remove the other name, or move this file aside" && ! echo "$lout" | grep -qF "exact path" \
  && tmux has-session -t '=tt-w1' 2>/dev/null && ! tmux capture-pane -p -t '=tt-w1:' | grep -q "through a hard-linked log" \
  && ok "say: a hard link at messages.log is refused, nothing is delivered or written through it, say says the line was not written, and the advice is to remove the other name or move the file aside, never to delete it" || { bad "say through a hard-linked log (rc=$rc)"; echo "$lout"; cat $T/sent-log; }
# A say to or from sec is logged without its body (#227). A team file that also has a sec seat (down: the
# line is NOT-DELIVERED, which is the status the checks read; em and w1 are up, so a say to them is delivered), with its own state folder.
echo "--- say: sec's messages are logged without their body (#227)"
sed 's|^  w2: .*|&\n  sec: { title: Security, workdir: { type: project, path: '$T'/proj }, prompt_text: "sec prompt" }|' $T/team.yaml > $T/team-sec.yaml
mkdir -p $T/secstate
# em and w1 were started with the state folder $T/state, and a command acts only on its own team's sessions:
# one whose state folder or repository is another is another team's, whatever its name. team-sec.yaml runs
# with a state folder of its own, so for this section the two seats are handed to it, the way the owner
# hands a session over after a state folder was moved (the refusal gives the command), and back at its end.
say_hand() { local s d; d=$(cd "$1" && pwd -P); for s in tt-em tt-w1; do tmux set-environment -t "=$s" TEAM_STATE_REAL "$d"; done; }
say_hand $T/secstate
SECLOG=$T/secstate/messages.log; : > $SECLOG
SEC_MARK='[body not logged: sec]'
# secsay <what> <from> <to> <message>: one line with time, sender, recipient, status, marker; the sentinel is nowhere in the log.
secsay() { local what=$1 f=$2 t=$3 m=$4 st=$5 n line
  n=$(wc -l < $SECLOG 2>/dev/null || echo 0)
  TEAM_STATE_DIR=$T/secstate TEAM_ROLE=$f $S -c $T/team-sec.yaml say "$t" "$m" >/dev/null 2>&1
  line=$(tail -n +$((n + 1)) $SECLOG)
  if [ "$(wc -l < $SECLOG)" -eq $((n + 1)) ] && [ "$(printf '%s\n' "$line" | cut -f2-5)" = "$f	$t	$st	$SEC_MARK" ] && ! grep -q SENTINEL-227-say $SECLOG \
    && printf '%s\n' "$line" | cut -f1 | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
    ok "say log: $what is logged without its body"
  else bad "say log: $what"; printf '%s\n' "$line"; fi; }
secsay "a say to sec" em sec "to sec SENTINEL-227-say" NOT-DELIVERED
secsay "a say from sec" sec em $'from sec\nSENTINEL-227-say, tab\t' delivered
secsay "a say from sec to w1" sec w1 "SENTINEL-227-say again" delivered
# say all from a seat other than sec is logged in full, as today: the text is that seat's, and the line names all.
n=$(wc -l < $SECLOG)
TEAM_STATE_DIR=$T/secstate TEAM_ROLE=em $S -c $T/team-sec.yaml say all "plain broadcast SENTINEL-227-other" >/dev/null 2>&1
[ "$(tail -n +$((n + 1)) $SECLOG | cut -f2,3,5)" = "em	all	plain broadcast SENTINEL-227-other" ] && ok "say log: a say all from another seat is logged in full" || { bad "say log: say all from another seat"; tail -n +$((n + 1)) $SECLOG; }
# say between two other seats: in full.
n=$(wc -l < $SECLOG)
TEAM_STATE_DIR=$T/secstate TEAM_ROLE=em $S -c $T/team-sec.yaml say w2 "plain SENTINEL-227-w2" >/dev/null 2>&1
[ "$(tail -n +$((n + 1)) $SECLOG | cut -f2,3,4,5)" = "em	w2	NOT-DELIVERED	plain SENTINEL-227-w2" ] && ok "say log: a say between two other seats is logged in full, status as before" || { bad "say log: say between other seats"; tail -n +$((n + 1)) $SECLOG; }
# The settings that tune the repeat window and the notice count (#273): FABRIKITO_SAY_*, and the old FACTORY_SAY_*
# still read for one release; the new name wins when both are set.
say_set() { env -u FABRIKITO_SAY_RESEND_WINDOW -u FACTORY_SAY_RESEND_WINDOW -u FABRIKITO_SAY_NOTICE_COUNT -u FACTORY_SAY_NOTICE_COUNT "$@" bash -c "$(grep -E '^SAY_(RESEND_WINDOW|NOTICE_COUNT)=' $S)
echo \$SAY_RESEND_WINDOW \$SAY_NOTICE_COUNT"; }
[ "$(say_set)" = "300 3" ] && [ "$(say_set FABRIKITO_SAY_RESEND_WINDOW=11 FABRIKITO_SAY_NOTICE_COUNT=5)" = "11 5" ] \
  && [ "$(say_set FACTORY_SAY_RESEND_WINDOW=12 FACTORY_SAY_NOTICE_COUNT=6)" = "12 6" ] && [ "$(say_set FABRIKITO_SAY_RESEND_WINDOW=13 FACTORY_SAY_RESEND_WINDOW=14 FABRIKITO_SAY_NOTICE_COUNT=7 FACTORY_SAY_NOTICE_COUNT=8)" = "13 7" ] \
  && ok "say: FABRIKITO_SAY_RESEND_WINDOW and _NOTICE_COUNT set the window and the count, the old FACTORY_SAY_ names still do, and the new ones win" || { bad "say: the names of the window and count settings"; say_set; say_set FACTORY_SAY_RESEND_WINDOW=12; }
say_hand $T/state
e2e_end=say # the last line: test/e2e.sh checks that the file ran to here
