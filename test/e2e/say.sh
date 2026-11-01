# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# say: delivery to a seat, the kickoff label, titles, the messages.log line.
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
# message field is <escaped>, and printf %b of that field gives back the message (README format).
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
  set -- HOME="$T/home$E" TEAM_STATE_DIR="$T/state$E" TEAM_SCRIPT="$T/dir$E/factory.sh" TEAM_LOG="$T/state$E/messages.log" \
    CLAUDE_CONFIG_DIR="$T/home$E/.claude" "$@"
  # PATH is passed as one word: it can hold spaces.
  if [ $l = C ]; then env LC_ALL=C "$@" ruby $SRC/lib/team_config.rb "$NT" $c em 2>&1
  else env -i PATH="$PATH" "$@" ruby $SRC/lib/team_config.rb "$NT" $c em 2>&1; fi; }
for l in C none; do
  out=$(rn $l render); echo "$out" | grep -qxF "em Zo$E $T/proj$E $T/dir$E/factory.sh $T/state$E/messages.log" \
    && ok "non-ASCII owner, workdir, TEAM_SCRIPT and TEAM_LOG render byte for byte ($l)" || { bad "non-ASCII render ($l)"; echo "$out" | tail -2; }
  out=$(rn $l kickoff); echo "$out" | grep -qF "or Zo$E." && ok "the kickoff names the non-ASCII owner ($l)" || { bad "non-ASCII kickoff ($l)"; echo "$out" | tail -2; }
  out=$(rn $l settings); echo "$out" | ruby -rjson -e 'd = JSON.parse(STDIN.read)["permissions"]["deny"]; exit(ARGV.all? { |w| d.include?(w) } ? 0 : 1)' \
    "Edit(/$T/proj$E/.claude/settings.json)" "Edit(/$T/state$E/settings/**)" "Edit(/$T/home$E/.claude/settings.json)" "Edit(/$NT)" \
    && ok "settings with a non-ASCII workdir, state folder, home, config folder and team file folder ($l)" || { bad "non-ASCII settings ($l)"; echo "$out" | tail -2; }
  out=$(rn $l permissions_report); [ $? = 0 ] && echo "$out" | grep -qF "[em]" && ok "check's permission report with a non-ASCII home ($l)" || { bad "non-ASCII permissions_report ($l)"; echo "$out" | tail -2; }
done
# Invalid UTF-8 from outside is an error that names where it came from, not a Ruby backtrace.
out=$(rn C render TEAM_SCRIPT=$'/x/\xff/factory.sh'); [ $? != 0 ] && echo "$out" | grep -qF "the environment variable TEAM_SCRIPT is not valid UTF-8" && ! echo "$out" | grep -q "Error)" \
  && ok "an environment value that is not UTF-8 is refused, naming the variable" || { bad "invalid TEAM_SCRIPT"; echo "$out" | tail -2; }
out=$(rn none settings HOME=$'/tmp/x\xff'); [ $? != 0 ] && echo "$out" | grep -qF "the home folder (HOME) is not valid UTF-8" && ! echo "$out" | grep -q "Error)" \
  && ok "a home folder that is not UTF-8 is refused, naming HOME" || { bad "invalid HOME"; echo "$out" | tail -2; }
# say validates and renders the whole team before it sends: from that team, under both locales.
for l in C none; do
  n=$(wc -l < $T/state/messages.log)
  if [ $l = C ]; then LC_ALL=C HOME="$T/home$E" TEAM_ROLE=em $S -c "$NT" say w2 "from a non-ASCII team ($l)" >/dev/null 2>&1
  else env -i PATH="$PATH" HOME="$T/home$E" TMUX_TMPDIR="$TMUX_TMPDIR" TEAM_STATE_DIR="$TEAM_STATE_DIR" TEAM_ROLE=em $S -c "$NT" say w2 "from a non-ASCII team ($l)" >/dev/null 2>&1; fi
  [ "$(wc -l < $T/state/messages.log)" -eq $((n + 1)) ] && tail -1 $T/state/messages.log | grep -qF "from a non-ASCII team ($l)" \
    && ok "say from a team with a non-ASCII workdir, owner and home ($l)" || { bad "say from a non-ASCII team ($l)"; tail -1 $T/state/messages.log; }
done
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
e2e_end=say # the last line: test/e2e.sh checks that the file ran to here
