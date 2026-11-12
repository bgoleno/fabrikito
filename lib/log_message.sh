#!/usr/bin/env bash
#
# PostToolUse and PostToolUseFailure hook on SendMessage that fabrikito puts in every seat's
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
# A call with notify_when_idle and no message sends nothing: its outcome is NOTIFY-WHEN-IDLE and its
# message the placeholder "<no message: notify when idle>" (#247).
# A message or recipient that is not a string is written as its JSON text. Input that cannot be read
# at all is still recorded, as a line with recipient "?", outcome UNREADABLE and a placeholder message:
# the hook runs only on SendMessage, so a message was sent, and the log should say so.
#
# A message to or from the role id sec is written without its body: the marker "[body not logged: sec]"
# stands in for the text, the other fields are as always (#227). So is a message to a uds: address
# that did not resolve to a roster seat, with the marker "[body not logged: unresolved address]".
#
# The message is the sender's to choose, so every field is escaped exactly as say's log_field does:
# a message cannot split or forge a log line, or drive the terminal that reads the log. The message
# goes into messages.log and nowhere else. The script never touches the message or the tool result:
# it prints nothing and exits 0 whatever happens, so a log it cannot write costs a line, not the
# message. The hook's own timeout (5s) is a backstop; the uds: lookup gives up after 2s by itself.
set -u
log=${1:-} from=${2:-}
[ -n "$log" ] && [ -n "$from" ] || exit 0
shift 2
# The source is ASCII (escapes, not characters): outside a UTF-8 locale ruby reads -e as US-ASCII.
ruby --disable-gems -rjson -e '
  log, from, *pairs = ARGV
  roles = {}
  pairs.each { |p| s, r = p.split("=", 2); roles[s] = r if s && r }
  stamp = Time.now.strftime("%Y-%m-%dT%H:%M:%S")

  def field(s)
    s = s.to_s.dup.force_encoding("UTF-8")
    re = s.valid_encoding? ? /[\\\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/ : (s = s.b; /[\\\x00-\x1f\x7f-\xff]/n)
    esc = { "\\" => "\\\\", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }
    s.gsub(re) { |c| esc[c] || c.bytes.map { |b| format("\\x%02X", b) }.join }
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Runs argv with its output on a pipe, in a process group of its own, until the deadline. Returns
  # its output, or nil if it has not finished by then: it is then killed, its whole group with it,
  # and reaped. Not Timeout around a block-form IO.popen, which waits for the child with no limit
  # when it closes the pipe (tl review of #110: a hung tmux held the hook for 20s).
  def run_until(argv, deadline)
    r, w = IO.pipe
    pid = Process.spawn(*argv, in: File::NULL, out: w, err: File::NULL, pgroup: true)
    w.close
    out = String.new
    loop do
      left = deadline - now
      return nil if left <= 0 || IO.select([r], nil, nil, left).nil?
      c = r.read_nonblock(65_536, exception: false)
      break if c.nil?
      out << c if c.is_a?(String)
    end
    until Process.waitpid(pid, Process::WNOHANG)
      return nil if now >= deadline
      sleep 0.01
    end
    pid = nil
    out.force_encoding("UTF-8")
  ensure
    [r, w].each { |io| io.close if io && !io.closed? }
    if pid
      (Process.kill("KILL", -pid) rescue nil)
      (Process.waitpid(pid) rescue nil)
    end
  end

  # The pane tty of each roster session, then the tty of the process named by a uds: address. Both
  # commands share one 2s limit.
  def uds_role(to, roles)
    pid = to[%r{\Auds:.*/(\d+)\.sock\z}, 1] or return nil
    deadline = now + 2
    tty = run_until(["ps", "-o", "tty=", "-p", pid], deadline).to_s.strip
    return nil if tty.empty? || tty.start_with?("?")
    panes = run_until(["tmux", "list-panes", "-a", "-F", "\#{pane_tty} \#{session_name}"], deadline).to_s
    panes.each_line do |l|
      t, s = l.chomp.split(" ", 2)
      return roles[s] if t && s && File.basename(t) == File.basename(tty) && roles.key?(s)
    end
    nil
  rescue StandardError
    nil
  end

  # Ruby 2.6 json refuses a lone surrogate escape (a high half with no low half after it, or a low
  # half alone), which JSON.stringify writes for a JS string that holds one, so the whole line would
  # be lost (tl review of #110). Each lone one becomes \ufffd, U+FFFD. Escapes are matched left to
  # right, so a valid pair stays, and so does an escaped backslash followed by the text "ud800". Done
  # on the bytes, so input that is not valid UTF-8 still parses, and field escapes those bytes.
  def lone_surrogates_replaced(raw)
    raw.b.gsub(/\\u[dD][89abAB]\h\h\\u[dD][c-fC-F]\h\h|\\u[dD][89a-fA-F]\h\h|\\./mn) { |m| m.bytesize == 6 ? "\\ufffd" : m }.force_encoding("UTF-8")
  end

  # A field that is not a string is written as its JSON text; a missing one is empty.
  def text(x)
    return "" if x.nil?
    return x if x.is_a?(String)
    JSON.generate(x)
  rescue StandardError
    x.inspect
  end

  # One write in append mode, as say appends with >>: lines from both stay whole. Never through a
  # link at the log, or into anything there but a regular file (#194, as say): NOFOLLOW makes the
  # open fail on a symlink, NONBLOCK keeps it from waiting on a FIFO, and what was opened must be a
  # regular file with one link: a hard link passes the other two (tl and sec on #206). A refused
  # open raises, which costs the line, as any other failure here does. A log this creates is for the
  # owner only (0600, whatever the umask), as the one say creates is: it holds every message.
  def append(log, fields)
    return unless File.directory?(File.dirname(log))
    File.open(log, File::WRONLY | File::APPEND | File::CREAT | File::NOFOLLOW | File::NONBLOCK, 0o600) do |f|
      st = f.stat
      f.write(fields.join("\t") + "\n") if st.file? && st.nlink == 1
    end
  end

  j = (JSON.parse(lone_surrogates_replaced(STDIN.read)) rescue nil)
  unless j.is_a?(Hash)
    append(log, [stamp, field(from), "?", "UNREADABLE", "<hook input could not be read>"])
    exit 0
  end
  exit 0 unless j["tool_name"] == "SendMessage"
  inp = j["tool_input"].is_a?(Hash) ? j["tool_input"] : {}
  to = text(inp["to"])
  outcome =
    if j["hook_event_name"] == "PostToolUseFailure" then "NOT-SENT"
    else
      r = j["tool_response"]
      r = (JSON.parse(r) rescue r) if r.is_a?(String)
      r.is_a?(Hash) && r["success"] == false ? "NOT-SENT" : "sent"
    end
  # A call with notify_when_idle and no message sends nothing: it asks to be told when the receiver
  # is idle (#247). Logged as sent with an empty message it read as an empty message sent, so it is
  # written with a placeholder message, and as outcome NOTIFY-WHEN-IDLE when it succeeded (a failure
  # stays NOT-SENT). Only a missing or empty message with notify_when_idle exactly true counts; every
  # other call is logged as before, byte for byte. The sender cannot choose the outcome, so a
  # message that spells the placeholder cannot pass for a subscription.
  watch = inp["notify_when_idle"] == true && (inp["message"].nil? || inp["message"] == "")
  outcome = "NOTIFY-WHEN-IDLE" if watch && outcome == "sent"
  msg = watch ? "<no message: notify when idle>" : field(text(inp["message"]))
  name = to.sub(/ \[[^\]]*\]\z/, "")
  rcpt = roles[name] || uds_role(to, roles) || to
  # A message to or from the security seat is logged without its body (#227): it can hold an unfixed
  # finding, which hard rule 5 keeps to sec and the EM, and the log is readable by more than they are
  # (the observer role, a copy kept elsewhere). The line keeps time, sender, recipient and outcome, so
  # the delivery checks read it as before. The test is on the resolved recipient and the sender, both
  # role ids, so a session name, a "[ref]" or a uds: address that resolves to sec is caught too. The
  # id is TRIAGE_WRITER in lib/team_config.rb. A message to "all" (say) is not one to sec: see the README.
  msg = "[body not logged: sec]" if (rcpt == "sec" || from == "sec") && !watch
  # Fail closed (sec on #227): a uds: address that did not resolve to a roster seat (the 2s lookup ran
  # out on a loaded host, or the sender is outside a roster pane) may still be one for sec, and replying to a
  # message by its from address is the usual way to answer sec. Its body is not written either. A named
  # recipient that is not on the roster is still logged in full, as before.
  msg = "[body not logged: unresolved address]" if rcpt == to && to.start_with?("uds:") && !watch && msg != "[body not logged: sec]"
  append(log, [stamp, field(from), field(rcpt), outcome, msg])
' -- "$log" "$from" "$@" </dev/stdin >/dev/null 2>&1
exit 0
