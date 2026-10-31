#!/usr/bin/env bash
#
# PostToolUse and PostToolUseFailure hook on SendMessage that factory.sh puts in every seat's
# generated settings (#39). It appends one line per native message to the team's messages.log in
# say's format (README, "The message log"): time, sender role, recipient, outcome, message.
#
#   log_message.sh <log file> <sender role> [<session>=<role> ...]
#
# The hook input (JSON) arrives on stdin: tool_input.to and tool_input.message, and tool_response
# (PostToolUse) or error (PostToolUseFailure). The outcome is "sent" when SendMessage put the message
# in the receiver's inbox, and NOT-SENT when it returned success false or failed. The recipient is
# written as a role id when it names a roster seat's session (with or without a " [ref]"), or when
# it is a uds: address whose process runs in a roster seat's pane; anything else is written as given.
#
# The message is the sender's to choose, so every field is escaped exactly as say's log_field does:
# a message cannot split or forge a log line, or drive the terminal that reads the log. The message
# goes into messages.log and nowhere else. The script never touches the message or the tool result:
# it prints nothing and exits 0 whatever happens, so a log it cannot write costs a line, not the
# message. The hook's own timeout (5s) is a backstop; the uds: lookup has its own limit.
set -u
log=${1:-} from=${2:-}
[ -n "$log" ] && [ -n "$from" ] || exit 0
shift 2
# The source is ASCII (escapes, not characters): outside a UTF-8 locale ruby reads -e as US-ASCII.
ruby --disable-gems -rjson -rtimeout -e '
  log, from, *pairs = ARGV
  roles = {}
  pairs.each { |p| s, r = p.split("=", 2); roles[s] = r if s && r }

  def field(s)
    s = s.to_s.dup.force_encoding("UTF-8")
    re = s.valid_encoding? ? /[\\\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/ : (s = s.b; /[\\\x00-\x1f\x7f-\xff]/n)
    esc = { "\\" => "\\\\", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }
    s.gsub(re) { |c| esc[c] || c.bytes.map { |b| format("\\x%02X", b) }.join }
  end

  # The pane tty of each roster session, then the tty of the process named by a uds: address.
  def uds_role(to, roles)
    pid = to[%r{\Auds:.*/(\d+)\.sock\z}, 1] or return nil
    Timeout.timeout(2) do
      tty = IO.popen(["ps", "-o", "tty=", "-p", pid], err: File::NULL, &:read).to_s.strip
      return nil if tty.empty? || tty.start_with?("?")
      panes = IO.popen(["tmux", "list-panes", "-a", "-F", "\#{pane_tty} \#{session_name}"], err: File::NULL, &:read).to_s
      panes.each_line do |l|
        t, s = l.chomp.split(" ", 2)
        return roles[s] if t && s && File.basename(t) == File.basename(tty) && roles.key?(s)
      end
    end
    nil
  rescue StandardError, Timeout::Error
    nil
  end

  j = (JSON.parse(STDIN.read) rescue nil)
  exit 0 unless j.is_a?(Hash) && j["tool_name"] == "SendMessage"
  inp = j["tool_input"].is_a?(Hash) ? j["tool_input"] : {}
  to = inp["to"].to_s
  outcome =
    if j["hook_event_name"] == "PostToolUseFailure" then "NOT-SENT"
    else
      r = j["tool_response"]
      r = (JSON.parse(r) rescue r) if r.is_a?(String)
      r.is_a?(Hash) && r["success"] == false ? "NOT-SENT" : "sent"
    end
  name = to.sub(/ \[[^\]]*\]\z/, "")
  rcpt = roles[name] || uds_role(to, roles) || to
  line = [Time.now.strftime("%Y-%m-%dT%H:%M:%S"), field(from), field(rcpt), outcome, field(inp["message"])].join("\t") + "\n"
  # One write in append mode, as say appends with >>: lines from both stay whole.
  File.open(log, "a") { |f| f.write(line) } if File.directory?(File.dirname(log))
' -- "$log" "$from" "$@" </dev/stdin >/dev/null 2>&1
exit 0
