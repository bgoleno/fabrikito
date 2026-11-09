# Runs one heavy command (a full gate, an e2e run) at a time across every seat of every team on this
# host, and anyone's shell (#214). fabrikito run-exclusive execs this before it reads a team file:
#
#   ruby lib/run_exclusive.rb [--] <command> [args...]
#
# The command is an argument list, never a shell string (a pipeline is `bash -c '...'`), and the exit
# status is the command's (128 + the signal when a signal ended it). While another run holds the lock,
# this waits, however long it takes, and says who holds it and since when; it never fails for a busy
# lock. Ctrl-C or TERM while waiting exits 130 or 143 without running the command.
#
# The lock is a flock on one file per user, outside every team's state folder and checkout:
# <home>/Library/Application Support/software-factory/run-exclusive.lock, home from the user database,
# not $HOME, so every seat, team and checkout of this user finds the same file. Not the per-user T/
# folder: macOS removes files there that have not been used for some days, and a lock whose name is
# removed while a run holds it no longer makes the next run wait (tl on #214). FACTORY_RUN_LOCK names
# another file instead (the e2e uses its own).
#
# Waiting runs get the lock in the order they arrived (#283). Each takes a ticket, a file named by its
# arrival time in <lock>.queue/, flocked for as long as the run waits; only the earliest live ticket
# tries the lock. The system drops a flock when its process ends however it ends (even SIGKILL), so a
# killed waiter's ticket is found stale by the next poll and removed: its place is never stuck.
#
# System ruby 2.6: no gems, no endless methods.
require "json"
require "etc"

LOCK_POLL = 2       # seconds between tries while the lock is busy
TICKET_STALE = 10   # seconds: a waiting run touches its ticket every poll; one untouched this long is not waiting (#283)
REMIND = 300        # seconds between "still waiting" lines

def say(msg)
  $stderr.puts "run-exclusive: #{msg}"
end

def die(msg, code = 1)
  say "error: #{msg}"
  exit code
end

# Paths, arguments and variables are bytes. Under LC_ALL=C ruby reads them as ASCII, so one that is not
# would fail the JSON of the record, a regexp or the joining of two strings, and a run that only has to
# wait or run a command would end in a stack trace instead. The bytes stay as they are.
def utf8(s)
  s.dup.force_encoding("UTF-8")
end

args = ARGV.dup
args.shift if args.first == "--"
die("usage: fabrikito run-exclusive -- <command> [args...]", 64) if args.empty?

lock = ENV["FACTORY_RUN_LOCK"].to_s
# A relative path would name a different lock in each caller's folder (tl on #240).
die("FACTORY_RUN_LOCK must be an absolute path, not #{lock}", 64) unless lock.empty? || lock.start_with?("/")
if lock.empty?
  home = (Etc.getpwuid(Process.uid).dir rescue nil).to_s
  die("cannot find this user's home folder in the user database, so there is no place for the lock") if home.empty?
  lock = File.join(home, "Library", "Application Support", "software-factory", "run-exclusive.lock")
end
lock = utf8(File.expand_path(lock))
holder = "#{lock}.holder"

def alive?(pid)
  return false unless pid.is_a?(Integer) && pid > 0
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
rescue Errno::EPERM
  true
end

# The holder record: who took the lock, written by the holder just after it took it. A waiter can read
# the record of a run that has ended (it is removed at the end, but a killed run leaves it), or none.
def record(holder)
  j = File.open(holder, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) { |f| f.stat.file? ? f.read(65_536) : nil }
  j && JSON.parse(j)
rescue StandardError
  nil
end

# The record's fields come from another run (its folder, its command), so control characters in them
# are shown escaped, never sent to the terminal that reads this (sec on #240).
def shown(x)
  x.to_s.gsub(/[[:cntrl:]\u007f-\u009f]/) { |c| c.bytes.map { |b| format("\\x%02X", b) }.join }
rescue StandardError
  "?"
end

def who(rec)
  return "an unknown holder" unless rec.is_a?(Hash) && alive?(rec["pid"])
  "#{shown(rec["who"])} (pid #{rec["pid"]}, in #{shown(rec["cwd"])}), holding since #{shown(rec["since"])}: #{shown(rec["cmd"])}"
end

# Nesting: a run-exclusive inside the command of another (a gate script that calls it again) would wait
# for itself forever. The holder hands its command FACTORY_RUN_EXCLUSIVE_HELD=<lock>:<its pid>, and an
# inner call on the same lock runs its command directly, but only while the record names that pid and
# that pid is alive. The variable alone is not enough: anything the command leaves running (a tmux
# server started under the lock) keeps it for every shell it starts later, and those would then skip
# the lock for good (tl on #214).
held = utf8(ENV["FACTORY_RUN_EXCLUSIVE_HELD"].to_s).scrub
if (m = held.match(/\A(.+):(\d+)\z/)) && m[1] == lock
  rec = record(holder)
  if rec.is_a?(Hash) && rec["pid"] == m[2].to_i && alive?(m[2].to_i)
    begin
      exec([args[0], args[0]], *args[1..-1])
    rescue SystemCallError => e
      die("cannot run #{args[0]}: #{e.message}", 127)
    end
  end
end

# The folder is made owner-only. Neither it nor the lock may be a link, or anything but a folder and a
# regular file with one name: the lock would then be taken on some other file (#194's checks).
dir = File.dirname(lock)
begin
  Dir.mkdir(dir, 0o700)
rescue Errno::EEXIST
  nil
rescue SystemCallError => e
  die("cannot make #{dir}: #{e.message}")
end
st = File.lstat(dir)
die("#{dir} is a symlink or not a folder, and the lock is never taken through one: remove that exact path") if st.symlink? || !st.directory?

def unsafe?(path)
  st = File.lstat(path)
  st.symlink? || !st.file? || st.nlink > 1
rescue Errno::ENOENT
  false
end

def open_lock(lock)
  die("#{lock} is a symlink, a hard link or not a regular file, and the lock is never taken through one. Do not delete this file: it may be the real one, with a second name made elsewhere. Remove the other name, or move this file aside") if unsafe?(lock)
  # NOFOLLOW: a link made after the check fails the open. NONBLOCK: a FIFO does not hang it. Ruby opens
  # every file close-on-exec, so the command never holds the lock: anything it leaves running would
  # hold it otherwise, as with lockf(1), which hands it on (the e2e's tmux server outlives the run).
  f = File.open(lock, File::RDWR | File::CREAT | File::NOFOLLOW | File::NONBLOCK, 0o600)
  st = f.stat
  unless st.file? && st.nlink == 1
    f.close
    die("#{lock} is not a regular file with one name, and the lock is never taken through one. Do not delete this file: it may be the real one, with a second name made elsewhere. Remove the other name, or move this file aside")
  end
  f
rescue Errno::ELOOP
  die("#{lock} is a symlink, and the lock is never taken through one: remove that exact path")
rescue SystemCallError => e
  die("cannot open #{lock}: #{e.message}")
end

# The queue (#283). Tickets are named <arrival time in ns, 20 digits>-<pid>, so a sorted listing is the
# order of arrival. A ticket is made under a temporary name, flocked, and then renamed (the lock stays
# with the file), so a name that looks like a ticket is always already locked by its run.
QUEUE_RE = /\A\d{20}-\d{1,10}\z/
TMP_RE = /\A\.tmp-\d{1,10}\z/

def queue_dir!(qdir)
  begin
    Dir.mkdir(qdir, 0o700)
  rescue Errno::EEXIST
    nil
  rescue SystemCallError => e
    die("cannot make #{qdir}: #{e.message}")
  end
  st = File.lstat(qdir)
  die("#{qdir} is a symlink or not a folder, and the queue is never kept in one: remove that exact path") if st.symlink? || !st.directory?
  die("#{qdir} is owned by another user or open to others, and the queue is never kept in one: move it aside") if st.uid != Process.uid || (st.mode & 0o022) != 0
end

# Returns [open file, path]. The file's flock is the ticket's life: it ends with this run.
def take_ticket(qdir)
  3.times do
    name = format("%020d-%d", Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond), Process.pid)
    tmp = File.join(qdir, ".tmp-#{Process.pid}")
    begin
      # Inside the retry: the last run to leave may remove the folder between the mkdir and the lstat in
      # queue_dir!, or between it and the open below (tl on #284).
      queue_dir!(qdir)
      File.unlink(tmp) if File.symlink?(tmp) || File.exist?(tmp)
      f = File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600)
      f.flock(File::LOCK_EX)
      path = File.join(qdir, name)
      File.rename(tmp, path)
      return [f, path]
    rescue Errno::ENOENT
      next # the last run left and removed the empty folder between the mkdir and the open: make it again
    rescue SystemCallError => e
      (File.unlink(tmp) rescue nil)
      die("cannot take a place in the queue #{qdir}: #{e.message}")
    end
  end
  die("cannot take a place in the queue #{qdir}")
end

# Whether the run that made this ticket is alive: its flock is still held. A ticket nobody holds is
# stale (its run was killed) and is removed. Anything that is not a regular file with one name is not a
# ticket: only its name is removed, never what it leads to. A ticket that cannot be read counts as
# stale: a place in line is not worth a wait that never ends.
def live_ticket?(path)
  st = File.lstat(path)
  unless st.file? && st.nlink == 1
    (File.unlink(path) rescue nil)
    return false
  end
  f = File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
  begin
    # Held, and touched lately: a run that is waiting. Held but not touched for TICKET_STALE seconds: its
    # run is stopped (Ctrl-Z, kill -STOP) or hung, and a ticket like that must not hold up the line while
    # the lock is free. Its run finds the ticket gone when it continues and takes a new place at the end.
    return true if !f.flock(File::LOCK_SH | File::LOCK_NB) && Time.now - f.stat.mtime <= TICKET_STALE
    cur = (File.lstat(path) rescue nil)
    fs = f.stat
    File.unlink(path) if cur && cur.dev == fs.dev && cur.ino == fs.ino
    false
  ensure
    f.close
  end
rescue SystemCallError
  false
end

# How many live runs arrived before the one whose ticket is named name.
def ahead(qdir, name)
  names = (Dir.children(qdir) rescue [])
  # A run killed between its create and its rename leaves a .tmp-<pid>. One younger than a few seconds may be
  # a run about to lock it, so it is left alone (its probe would call it stale and the run would lose its place).
  names.each { |n| live_ticket?(File.join(qdir, n)) if n =~ TMP_RE && (Time.now - (File.lstat(File.join(qdir, n)).mtime rescue Time.now)) > 5 }
  names.select { |n| n =~ QUEUE_RE && n < name }.count { |n| live_ticket?(File.join(qdir, n)) }
end

# Until the command is about to start, a signal ends this run (130, 143, 129) without running it. From
# then on it is passed on to the command, and the command's own end decides the exit status. A signal
# that arrives while the command is being started is held and passed on once its pid is known. CONT
# follows it: a stopped command (a background job that touched the terminal) acts on no signal until it
# is continued, and it would keep the lock for the whole host (qa on #240).
child = nil
spawning = false
pending = nil
pass_on = lambda do |s|
  begin
    Process.kill(s, child)
    Process.kill("CONT", child)
  rescue SystemCallError
    nil
  end
end
{ "INT" => 130, "TERM" => 143, "HUP" => 129 }.each do |s, code|
  trap(s) do
    if child then pass_on.call(s)
    elsif spawning then pending ||= s
    else exit(code)
    end
  end
end

started = Time.now
waited = false
reminded = started
f = nil
qdir = "#{lock}.queue"
tf, tpath = take_ticket(qdir)
tname = File.basename(tpath)
# However this run ends (a signal, a refusal, the end of its command) its ticket goes, and the folder
# with it when it is the last (a leftover folder would change nothing but the listing).
at_exit do
  (File.unlink(tpath) rescue nil)
  (tf.close rescue nil)
  (Dir.rmdir(qdir) rescue nil)
end
loop do
  # Show the line this run is alive (its flock does not tell a stopped run from a running one). If the
  # ticket is gone, the others took this run for stopped (it was, or the machine stalled it for
  # TICKET_STALE seconds): it takes a new place at the end. Mutual exclusion is the main lock, not this.
  begin
    File.utime(nil, nil, tpath)
  rescue SystemCallError
    (tf.close rescue nil)
    tf, tpath = take_ticket(qdir)
    tname = File.basename(tpath)
  end
  n = ahead(qdir, tname)
  # Only the earliest waiting run tries the lock; the others wait their turn, however free it is.
  f = n == 0 ? open_lock(lock) : nil
  if f && f.flock(File::LOCK_EX | File::LOCK_NB)
    # The lock is on the open file, not the name. A waiter can open the file, have its name removed
    # and made again by another run, then lock the old file once its holder ends: it would hold a lock
    # nobody else takes, and overlap the run on the new file. So the name must still lead to the file
    # locked; if not, take the lock again, on what the name leads to now (tl on #214).
    cur = (File.lstat(lock) rescue nil)
    fs = f.stat
    break if cur && cur.file? && !cur.symlink? && cur.dev == fs.dev && cur.ino == fs.ino
    f.close
    next
  end
  f.close if f
  now = Time.now
  line = n.zero? ? "" : "; #{n} earlier run#{n == 1 ? " is" : "s are"} waiting ahead of this one"
  if !waited
    say "waiting for the lock (#{lock}), held by #{who(record(holder))}#{line}"
    waited = true
  elsif now - reminded >= REMIND
    say "still waiting, since #{started.strftime("%H:%M:%S")} (#{(now - started).round}s), for #{who(record(holder))}#{line}"
    reminded = now
  end
  sleep LOCK_POLL
end

# This run's turn is over: its ticket goes, and the next in line may try the lock.
(File.unlink(tpath) rescue nil)
me = Process.pid
rec = {
  "pid" => me,
  "who" => utf8([ENV["TEAM_ROLE"].to_s.empty? ? "a shell" : ENV["TEAM_ROLE"],
                 (ENV["TEAM_CONFIG"].to_s.empty? ? nil : File.basename(ENV["TEAM_CONFIG"], ".*"))].compact.join(" of ")).scrub,
  "since" => Time.now.strftime("%Y-%m-%dT%H:%M:%S"),
  "cwd" => utf8(Dir.pwd).scrub,
  "cmd" => utf8(args.join(" ")).scrub[0, 300],
}
# Written to a temporary name and renamed: rename replaces a link at the record's name rather than
# writing through it, and a waiter never reads half a record.
tmp = "#{holder}.#{me}"
begin
  File.unlink(tmp) if File.symlink?(tmp) || File.exist?(tmp)
  File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |o| o.write(JSON.generate(rec)) }
  File.rename(tmp, holder)
rescue SystemCallError => e
  # Without the record, a run-exclusive inside this command could not tell that its parent holds the
  # lock, and would wait for it forever, with every other run on the host behind it (tl on #240). So
  # nothing runs: the lock is released and the run fails, saying why.
  (File.unlink(tmp) rescue nil)
  f.close
  die("could not write the holder record #{holder} (#{e.message}), so the command was not run: remove that exact path if it is not a regular file, or make room, then run again")
end
say "got the lock after #{(Time.now - started).round}s" if waited
locked = f.stat

# The command runs in this run's process group, the caller's. Whoever stops work by process group (the
# stop gate's time limit sends TERM, then KILL, to the gate's group) then reaches the command and this
# run alike. In a group of its own, a KILL to the caller's group would end only this run: the lock would
# drop while the command ran on, beside the next run (tl on #240). It also stays in the terminal's
# foreground group, so a pager or a prompt works and Ctrl-C reaches it (qa on #240). A signal sent to this
# run alone is passed on to the command. One sent to the whole group therefore reaches the command twice:
# this run cannot tell the two apart. A command that cleans up on a signal must not let the second one
# cut its cleanup short (test/e2e.sh's on_exit ignores them).
env = { "FACTORY_RUN_EXCLUSIVE_HELD" => "#{lock}:#{me}" }
# A background job that touches the terminal gets TTIN or TTOU sent to its whole group, and this run
# stops with its command. It must: the shell would otherwise see a job still running, and fg would hand
# over the terminal without continuing the command. So it stays an ordinary stopped job, and from another
# shell it takes TERM and then CONT (docs/gate.md).
begin
  spawning = true
  pid = Process.spawn(env, [args[0], args[0]], *args[1..-1])
  child = pid
  spawning = false
  pass_on.call(pending) if pending
rescue SystemCallError => e
  File.unlink(holder) rescue nil
  die("cannot run #{args[0]}: #{e.message}", 127)
end
status = nil
loop do
  begin
    _, status = Process.wait2(child)
    break
  rescue Errno::EINTR
    next
  end
end
# The name must also have lasted while this run held the lock: once it is gone, a run that starts makes
# a new file and does not wait for this one, and nothing can see that in time (a holder cannot give its
# open file the name back). So it is only reported, at the end, for whoever reads this run's output.
cur = (File.lstat(lock) rescue nil)
unless cur && cur.dev == locked.dev && cur.ino == locked.ino
  say "warning: #{lock} was removed or replaced while this run held the lock, so a run that started meanwhile may have overlapped it"
end
# Removed while the lock is still held, so it can only be this run's record.
File.unlink(holder) rescue nil
f.close
exit(status.exited? ? status.exitstatus : 128 + (status.termsig || 0))
