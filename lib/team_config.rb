#!/usr/bin/env ruby
# frozen_string_literal: true

# Answers the questions factory.sh asks about a team definition file.
#
#   team_config.rb <team.yaml> validate
#   team_config.rb <team.yaml> ids                 role ids, in file order (start order)
#   team_config.rb <team.yaml> get <dotted.key>    e.g. storage.volume, sessions.prefix
#   team_config.rb <team.yaml> role <id> <key>     title | session | workdir_type | worktree_name | model | effort |
#                                                  permission_mode
#   team_config.rb <team.yaml> workdir <id>        absolute working directory of a seat
#   team_config.rb <team.yaml> claude_args <id>    the seat's claude arguments, one per line
#   team_config.rb <team.yaml> render <id>         the seat's full system prompt
#   team_config.rb <team.yaml> kickoff <id>        the seat's first message
#   team_config.rb <team.yaml> settings <id>       the seat's generated Claude Code settings (JSON)
#   team_config.rb <team.yaml> permissions_report  each seat's mode and rules, for `check`
#
# Ruby is used because it ships with macOS and parses YAML without installing anything.
# Unknown keys are an error, not ignored: a misspelled `volume:` that silently fell back to a
# default would put worktrees on the wrong disk.
require 'yaml'
require 'json'

def die(msg)
  warn "team config error: #{msg}"
  exit 1
end

TOP_KEYS = %w[team owner repo project storage sessions display prompts kickoff permissions roles].freeze
DISPLAY_KEYS = %w[iterm primary window].freeze
PROJECT_KEYS = %w[name url].freeze
EFFORTS = %w[low medium high xhigh max].freeze
REPO_KEYS = %w[path github base gate gate_timeout gate_max_blocks].freeze
STORAGE_KEYS = %w[volume root].freeze
SESSION_KEYS = %w[prefix claude].freeze
CLAUDE_KEYS = %w[wrapper args model effort permission_mode].freeze
PROMPT_KEYS = %w[common].freeze
ROLE_KEYS = %w[title summary workdir prompt prompt_text kickoff session model effort permission_mode permissions
               gate_on_stop skills].freeze
WORKDIR_KEYS = %w[type path name].freeze
ID_RE = /\A[a-z][a-z0-9]*\z/.freeze
PREFIX_RE = /\A[a-z0-9][a-z0-9-]*\z/.freeze
# A skill as the Skill tool names it: a bare name, or plugin:name.
SKILL_RE = /\A[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?\z/.freeze

# The folder factory.sh and this file are installed in.
INSTALL = File.expand_path('..', __dir__)

# The documented permission modes (https://code.claude.com/docs/en/permission-modes). `default`
# is the config value and `manual` its CLI alias. Both are passed through as written: the 2.1.316
# CLI accepts `--permission-mode default` although its error message lists only `manual`.
PERMISSION_MODES = %w[default manual acceptEdits plan auto dontAsk bypassPermissions].freeze

# Strongest first. Claude Code checks deny, then ask, then allow, across every settings source, and
# the first match decides (https://code.claude.com/docs/en/permissions).
PERMISSION_LISTS = %w[deny ask allow].freeze

# Flags factory.sh sets itself, or that would undo this file's permission keys. :always, or
# :with_mode (only when a seat has a permission_mode; a legacy file may still pass them in args).
RESERVED_FLAGS = {
  '--settings' => [:always, 'factory.sh passes each seat its generated settings file'],
  '--setting-sources' => [:always, "it changes which settings files load, and can drop the user's own deny rules"],
  '--permission-prompt-tool' => [:always, 'it hands ask decisions to a program'],
  '--permission-mode' => [:with_mode, 'use permission_mode'],
  '--dangerously-skip-permissions' => [:with_mode, 'use permission_mode: bypassPermissions'],
  '--allow-dangerously-skip-permissions' => [:with_mode, 'use permission_mode']
}.freeze

# Folders factory.sh owns under the state folder: settings, launch and prompts are rewritten for every
# start; bin holds the copies of claude the seats run, made by up when missing (#50). Seats may not
# edit them (see protected_paths), so a folder added here is protected without further changes.
# Files seats are meant to write (such as progress notes) belong in a folder that is not listed.
GENERATED_DIRS = %w[settings launch prompts bin].freeze

# Folders under the state folder that hooks write, and seats must not: the gate's failure counter
# lives in gate/, so a seat that could edit it could switch its own gate off. Protected like
# GENERATED_DIRS, but not regenerated per start.
HOOK_DIRS = %w[gate].freeze

# The field a tool's own specifier already covers. Claude Code ignores a `Tool(field:...)` rule on
# it, with only a startup warning.
PRIMARY_FIELDS = {
  'Bash' => 'command', 'PowerShell' => 'command', 'Read' => 'file_path', 'Edit' => 'file_path',
  'Write' => 'file_path', 'Grep' => 'path', 'Glob' => 'path', 'NotebookEdit' => 'notebook_path', 'WebFetch' => 'url'
}.freeze

# Claude Code accepts a path rule for these but never matches it: only Edit and Read rules are
# checked against paths.
NEVER_MATCH = %w[Write NotebookEdit Glob MultiEdit].freeze

# Why a permission rule string is wrong, or nil. Claude Code drops a malformed rule with at most a
# warning (none at all under -p), so a rule is checked here, where a mistake stops the launch.
def rule_error(rule, list)
  return 'a rule must be a non-empty string' unless rule.is_a?(String) && !rule.empty?
  return 'it has leading or trailing whitespace' if rule != rule.strip

  # Parentheses inside a specifier are literal, so the specifier runs from the first ( to a final ).
  open = rule.index('(')
  name = open ? rule[0...open] : rule
  if open ? !rule.end_with?(')') : rule.include?(')')
    return 'it must be Tool or Tool(specifier)'
  end

  spec = open ? rule[(open + 1)...-1] : nil
  return 'it has an empty specifier: write the bare tool name to match every use' if spec && spec.strip.empty?

  if name.start_with?('mcp__')
    return 'mcp__ rules cannot have a (specifier): Claude Code skips them when it loads a settings file' if spec
    return 'it must be Tool or Tool(specifier)' unless name =~ /\Amcp__[A-Za-z0-9_*.-]+\z/

    server = name[/\Amcp__(.*?)__/, 1]
    if list == 'allow' && name.include?('*') && (server.nil? || server.empty? || server.include?('*'))
      return 'a tool-name glob is only allowed in deny and ask, or after mcp__<server>__ in allow'
    end
    return nil
  end
  return 'it must be Tool or Tool(specifier)' unless name =~ /\A[A-Za-z0-9_*]+\z/
  return "the tool name must start with an uppercase letter, as Claude Code's tool names do" unless name =~ /\A[A-Z*]/
  return 'a tool-name glob is only allowed in deny and ask, or after mcp__<server>__ in allow' if list == 'allow' && name.include?('*')
  return nil if spec.nil?

  if NEVER_MATCH.include?(name)
    return "#{name}(path) never matches: write Edit(path) (Read(path) for Glob), or the bare tool name"
  end
  field = PRIMARY_FIELDS[name]
  if field && spec =~ /\A\s*#{field}\s*:/
    return "#{field} is the tool's main input field, and Claude Code ignores a #{field}: rule; " \
           'write Bash(rm *), Read(./path) or WebFetch(domain:host)'
  end
  if %w[Read Edit].include?(name) && spec.start_with?('/') && !spec.start_with?('//')
    return 'a single leading / anchors at the folder of the generated settings file, so it matches nothing ' \
           'in the project; write //absolute, ~/home, ./relative or a bare name'
  end
  if %w[Bash PowerShell].include?(name) && spec.include?(':*') && !spec.end_with?(':*')
    return ':* is only a wildcard at the end of a rule; elsewhere the colon is literal (write a space before the *)'
  end
  nil
end

# A path with the characters that are special in a gitignore pattern (Read and Edit rules use
# that syntax) escaped.
def glob_escape(path)
  path.gsub(/[\\*?\[\]]/) { |c| "\\#{c}" }
end

# The real path of a file that may not exist yet: the longest existing prefix is resolved, so a
# symlinked folder (/tmp, /var on macOS) gives the path Claude Code compares rules against.
def real_path(path)
  base = path
  rest = []
  until File.exist?(base) || base == '/'
    rest.unshift(File.basename(base))
    base = File.dirname(base)
  end
  File.join(File.realpath(base), *rest)
end

class TeamConfig
  attr_reader :path, :dir

  def initialize(path)
    @path = File.expand_path(path)
    @dir = File.dirname(@path)
    die "cannot read #{@path}" unless File.file?(@path)
    begin
      @c = YAML.safe_load(File.read(@path), permitted_classes: [], aliases: false)
    rescue Psych::Exception => e
      die "#{@path} is not valid YAML: #{e.message}"
    end
    die 'top level must be a mapping' unless @c.is_a?(Hash)
  end

  def expand(p)
    File.expand_path(p.to_s.sub(/\A~(?=\/|\z)/, Dir.home), @dir)
  end

  def section(name, allowed, required: true)
    s = @c[name]
    if s.nil?
      die "missing '#{name}'" if required
      return {}
    end
    die "'#{name}' must be a mapping" unless s.is_a?(Hash)
    bad = s.keys - allowed
    die "unknown key(s) under '#{name}': #{bad.join(', ')} (allowed: #{allowed.join(', ')})" unless bad.empty?
    s
  end

  def repo

    section('repo', REPO_KEYS)

  end
  def project
    section('project', PROJECT_KEYS)
  end

  def github
    repo['github'].to_s
  end

  def storage
    section('storage', STORAGE_KEYS)
  end
  def sessions
    section('sessions', SESSION_KEYS, required: false)
  end
  def claude
    (sessions['claude'] || {}).tap { |h| die "'sessions.claude' must be a mapping" unless h.is_a?(Hash) }
  end
  def display
    section('display', DISPLAY_KEYS, required: false)
  end

  def view_iterm
    display.key?('iterm') ? display['iterm'] : true
  end

  def view_primary
    (display['primary'] || roles.keys.first).to_s
  end

  def view_window
    (display['window'] || 'full').to_s
  end

  def owner
    (@c['owner'] || 'the owner').to_s
  end

  def prefix
    (sessions['prefix'] || 'team').to_s
  end
  def roles
    @c['roles']
  end

  def volume

    File.expand_path(storage['volume'].to_s.sub(/\A~(?=\/|\z)/, Dir.home))

  end
  def root
    storage['root'].to_s
  end
  def worktree_root
    File.join(volume, root)
  end
  def repo_path
    expand(repo['path'])
  end

  def role(id)
    r = roles[id]
    die "unknown role '#{id}' (roles: #{roles.keys.join(' ')})" if r.nil?
    r
  end

  def workdir_spec(id)

    role(id)['workdir']

  end
  def workdir_type(id)
    workdir_spec(id)['type']
  end
  def worktree_name(id)
    (workdir_spec(id)['name'] || "team-#{id}").to_s
  end
  def title(id)
    role(id)['title'].to_s
  end
  def session(id)
    (role(id)['session'] || "#{prefix}-#{id}").to_s
  end

  def workdir(id)
    w = workdir_spec(id)
    w['type'] == 'project' ? expand(w['path']) : File.join(worktree_root, worktree_name(id))
  end

  def read_prompt_file(rel)
    f = expand(rel)
    die "prompt file not found: #{f}" unless File.file?(f)
    File.read(f)
  end

  def role_prompt(id)
    r = role(id)
    r['prompt_text'] ? r['prompt_text'].to_s : read_prompt_file(r['prompt'])
  end

  def roster
    rows = roles.map do |id, r|
      "| #{id} | #{r['title']}#{r['summary'] ? ": #{r['summary']}" : ''} | #{session(id)} |"
    end
    (["| role id | seat | session |", '|---|---|---|'] + rows).join("\n")
  end

  def vars(id)
    {
      'TITLE' => title(id), 'ROLE' => id, 'SESSION' => session(id), 'PREFIX' => prefix,
      'SCRIPT' => ENV.fetch('TEAM_SCRIPT', 'factory.sh'), 'LOG' => ENV.fetch('TEAM_LOG', 'messages.log'),
      'REPO' => repo_path, 'WORKDIR' => workdir(id), 'WORKTREE_ROOT' => worktree_root,
      'VOLUME' => volume, 'GITHUB_REPO' => github, 'GITHUB_URL' => "https://github.com/#{github}",
      'PROJECT_NAME' => project['name'].to_s, 'PROJECT_URL' => project['url'].to_s, 'TEAM' => @c['team'].to_s, 'OWNER' => owner, 'ROSTER' => roster,
      'GATE_MAX_BLOCKS' => gate_max_blocks.to_s
    }
  end

  def subst(text, id)
    v = vars(id)
    out = text.gsub(/@@([A-Z_]+)@@/) { v.key?(Regexp.last_match(1)) ? v[Regexp.last_match(1)] : die("unknown placeholder @@#{Regexp.last_match(1)}@@ in a prompt") }
    out
  end

  def render(id)
    common = prompts_common
    own = role_prompt(id)
    own = "#{own.chomp}\n\n#{skills_section(id)}" unless skills(id).empty?
    subst(common + "\n" + own, id)
  end

  # roles.<id>.skills: each item is a skill name, or a one-entry mapping of a name to when to use
  # it. Returns [[name, note or nil], ...]; validate checks the shape first.
  def skills(id)
    (role(id)['skills'] || []).map { |s| s.is_a?(Hash) ? [s.keys.first.to_s, s.values.first.to_s] : [s.to_s, nil] }
  end

  # Seats load the owner's user-level and plugin skills, but which ones are installed differs per
  # machine, so the wording never assumes a listed skill is there and says what to do when it is not.
  def skills_section(id)
    head = ['## Skills',
            'These skills fit this role. Use one with the Skill tool when it applies, if it is installed (your',
            'session lists the skills it has). If one is not installed, work without it: do not install it.']
    (head + skills(id).map { |n, w| w ? "- `#{n}`: #{w}" : "- `#{n}`" }).join("\n") + "\n"
  end

  def validate_skills(id, list)
    die "roles.#{id}.skills must be a list" unless list.is_a?(Array)
    seen = {}
    list.each do |s|
      if s.is_a?(Hash)
        die "roles.#{id}.skills: a mapping entry must be one skill name and its note" unless s.size == 1
        name, note = s.first
        # The note is written into the prompt as is, so any control character (a newline, but also a
        # carriage return, tab or escape) would reach the seat raw.
        unless note.is_a?(String) && !note.strip.empty? && note !~ /[[:cntrl:]]/
          die "roles.#{id}.skills: the note for '#{name}' must be one line of text, with no control characters"
        end
      else
        name = s
      end
      die "roles.#{id}.skills: '#{name}' is not a skill name (letters, digits, . _ - and one plugin: prefix)" unless name.is_a?(String) && name =~ SKILL_RE
      die "roles.#{id}.skills: '#{name}' is listed twice" if seen[name]
      seen[name] = true
    end
  end

  def prompts_common
    p = @c['prompts']
    return '' if p.nil?

    read_prompt_file(p['common'])
  end

  def kickoff(id)
    r = role(id)
    tpl = r['kickoff'] || @c['kickoff'] ||
          'Team session started: you are the @@TITLE@@ (session @@SESSION@@). Your full role instructions are in your system prompt. ' \
          'Reply with one line confirming your role and working directory, then wait for a message from the EM or @@OWNER@@. ' \
          'Do not start any work until you receive one.'
    subst(tpl.to_s, id)
  end

  # A role's own value wins over sessions.claude. Neither set means the flag is omitted and the
  # seat inherits the user's claude settings (model and effortLevel in ~/.claude/settings.json).
  def model(id)
    (role(id)['model'] || claude['model'])&.to_s
  end

  def effort(id)
    (role(id)['effort'] || claude['effort'])&.to_s
  end

  def permission_mode(id)
    (role(id)['permission_mode'] || claude['permission_mode'])&.to_s
  end

  def args
    a = claude['args'] || []
    die "'sessions.claude.args' must be a list" unless a.is_a?(Array)
    a.map(&:to_s)
  end

  # The mode as `check` shows it. A legacy file sets it with a flag in args instead.
  def mode_label(id)
    return permission_mode(id) if permission_mode(id)
    return 'bypassPermissions (args)' if args.include?('--dangerously-skip-permissions')

    i = args.index { |a| a == '--permission-mode' || a.start_with?('--permission-mode=') }
    return '(inherit)' if i.nil?

    "#{args[i].include?('=') ? args[i].split('=', 2)[1] : args[i + 1]} (args)"
  end

  def claude_args(id)
    out = args
    out += ['--model', model(id)] if model(id)
    out += ['--effort', effort(id)] if effort(id)
    out += ['--permission-mode', permission_mode(id)] if permission_mode(id)
    out
  end

  # Generated prompts, launchers, settings and the message log live here.
  def state_dir
    File.expand_path(ENV['TEAM_STATE_DIR'] || File.join(INSTALL, '.state', @c['team'].to_s))
  end

  # A `permissions:` mapping (team level or a role's), checked. `where` names it in errors.
  def permission_section(h, where)
    return {} if h.nil?

    die "#{where} must be a mapping of deny, ask and allow lists" unless h.is_a?(Hash)
    bad = h.keys - PERMISSION_LISTS
    die "unknown key(s) under #{where}: #{bad.join(', ')} (allowed: #{PERMISSION_LISTS.join(', ')})" unless bad.empty?
    h.each do |list, rules|
      die "#{where}.#{list} must be a list of rules" unless rules.is_a?(Array)
      rules.each do |r|
        e = rule_error(r, list)
        die "#{where}.#{list}: invalid permission rule #{r.inspect}: #{e}" if e
      end
    end
    h
  end

  # The base branch without its remote (origin/main gives main), or nil when repo.base is not
  # <remote>/<branch>.
  def base_branch
    (repo['base'] || 'origin/main').to_s[%r{\A[^/]+/(.+)\z}, 1]
  end

  # Best effort, an early warning for a project whose base branch has no ruleset (the real control,
  # which makes this redundant where it exists): ask before any push whose destination is the base
  # branch, forced or not, since seats land changes through PRs. The character before the name (space, :, + or /) keeps a branch such as
  # "maintenance" from matching. Not caught: a bare `git push` while on the branch,
  # `git -C <dir> push`, a push from a script, or the GitHub API.
  def base_push_rules
    b = base_branch
    return [] if b.nil?

    [' ', ':', '+', '/'].flat_map { |c| ["Bash(git push *#{c}#{b})", "Bash(git push *#{c}#{b} *)"] }
  end

  # Patterns (escaped) for the files that change what a seat runs at its next start, or the rules it
  # runs under now: each path as configured and, when a symlink makes it differ, its real path too,
  # so neither spelling (nor the link itself) is left open. Every seat
  # gets an Edit deny on each (Edit also covers Write, NotebookEdit and shell redirects). This is not
  # a boundary: a script can still write them (see README, Safety, and #29).
  def protected_paths(id)
    home = Dir.home
    claude_home = File.join(home, '.claude')
    [
      # what factory.sh regenerates for each start (settings, launchers, prompts) and the message log
      *(GENERATED_DIRS + HOOK_DIRS).map { |d| File.join(state_dir, d, '**') },
      File.join(state_dir, 'messages.log'),
      # the team file and the prompts it loads into every seat
      @path,
      *([prompts_common_path] + roles.values.map { |r| r['prompt'] && expand(r['prompt']) }).compact,
      # the launcher itself, and the wrapper it runs claude through
      File.join(INSTALL, 'factory.sh'), File.join(INSTALL, 'lib', '**'), File.join(INSTALL, 'roles', '**'),
      *wrapper_path,
      # settings a worktree session reads from the main checkout's root, and the skills, agents and
      # commands it reads from there when its own checkout lacks them. Not all of .claude/: Claude
      # Code makes its own worktrees in .claude/worktrees/, and seats must be able to edit them.
      File.join(repo_path, '.claude', 'settings.json'), File.join(repo_path, '.claude', 'settings.local.json'),
      *%w[skills agents commands].map { |d| File.join(repo_path, '.claude', d, '**') },
      # what else a session at repo.path loads from the main checkout at its next start: the project's
      # MCP servers (commands Claude Code starts), the hook scripts its settings call, and the
      # instructions kept under .claude/. Seats change these in their worktrees, never here.
      File.join(repo_path, '.mcp.json'), File.join(repo_path, '.claude', 'hooks', '**'),
      File.join(repo_path, '.claude', 'CLAUDE.md'), File.join(repo_path, '.claude', 'rules', '**'),
      # project settings load from the seat's own folder without a trust prompt, hooks included;
      # the rest of its .claude/ (commands, agents, skills) is ordinary project work
      File.join(workdir(id), '.claude', 'settings.json'), File.join(workdir(id), '.claude', 'settings.local.json'),
      # the user's own settings, MCP servers, instructions and extensions (not all of ~/.claude,
      # where Claude Code's tools write legitimately)
      File.join(claude_home, 'settings.json'), File.join(home, '.claude.json'), File.join(claude_home, 'CLAUDE.md'),
      *%w[plugins skills agents commands hooks].map { |d| File.join(claude_home, d, '**') }
    ].flat_map do |p|
      glob = p.end_with?('/**')
      base = glob ? p[0...-3] : p
      [File.expand_path(base), real_path(base)].uniq.map { |b| glob ? "#{glob_escape(b)}/**" : glob_escape(b) }
    end.uniq
  end

  # The wrapper claude runs through, if one is set. Inside an .app bundle the whole bundle is
  # protected: the program it runs can come from anywhere in the bundle (its Info.plist, other
  # executables, frameworks), so the executable alone would not be enough.
  def wrapper_path
    w = claude['wrapper']
    return [] if w.nil?

    w = expand(w)
    app = w[%r{\A(.*?\.app)/}, 1]
    [app ? File.join(app, '**') : w]
  end

  def prompts_common_path
    p = @c['prompts']
    p && p['common'] ? expand(p['common']) : nil
  end

  # Every rule for a seat as [rule, list, source]: the team's, then the role's, then the ones
  # factory.sh adds itself.
  def permission_entries(id)
    out = []
    add = lambda do |h, source|
      PERMISSION_LISTS.each { |list| (h[list] || []).each { |r| out << [r, list, source] } }
    end
    add.call(permission_section(@c['permissions'], 'permissions'), 'team')
    add.call(permission_section(role(id)['permissions'], "roles.#{id}.permissions"), "roles.#{id}")
    add.call({ 'deny' => protected_paths(id).map { |p| "Edit(/#{p})" }, 'ask' => base_push_rules }, 'factory.sh')
    out
  end

  # The seat's merged deny, ask and allow lists. Merging only adds: a role cannot remove or weaken a
  # team rule. A role may make a team rule stronger (team ask, role deny); the weaker copy is dropped.
  # A rule that a stronger one at the same level or above makes useless is an error, since it would
  # silently do nothing: a team deny over a role ask, a team ask over a role allow, or the same rule
  # in two lists of one level.
  def merged_permissions(id)
    entries = permission_entries(id)
    rank = ->(list) { PERMISSION_LISTS.index(list) }
    above = ->(source) { source.start_with?('roles.') ? [source, 'team', 'factory.sh'] : ['team', 'factory.sh'] }
    entries.each do |rule, list, source|
      next if source == 'factory.sh'

      stronger = entries.find { |r, l, s| r == rule && rank.call(l) < rank.call(list) && above.call(source).include?(s) }
      next unless stronger

      die "permission rule #{rule.inspect} in #{source} #{list} has no effect: #{stronger[2]} #{stronger[1]} " \
          "has the same rule, and Claude Code checks #{stronger[1]} first"
    end
    PERMISSION_LISTS.map do |list|
      rules = entries.select { |r, l, _| l == list && entries.none? { |r2, l2, _| r2 == r && rank.call(l2) < rank.call(l) } }
      [list, rules.map(&:first).uniq]
    end.to_h
  end

  # The repo's pass/fail command, its time limit, and how many failed gates in a row send a seat
  # back before its stop goes through (see lib/stop_gate.sh).
  def gate
    repo['gate']&.to_s
  end

  def gate_timeout
    (repo['gate_timeout'] || 600).to_i
  end

  def gate_max_blocks
    (repo['gate_max_blocks'] || 3).to_i
  end

  def gate_on_stop?(id)
    role(id)['gate_on_stop'] == true
  end

  # The Stop hook that runs the gate when a seat with gate_on_stop ends a turn with uncommitted
  # changes. Exec form (args): each argument reaches the script as written, with no shell quoting.
  # The hook's own timeout is a backstop; the script enforces the gate's.
  def stop_gate_hook(id)
    { 'type' => 'command', 'command' => File.join(INSTALL, 'lib', 'stop_gate.sh'),
      'args' => [state_dir, id, workdir(id), gate, gate_timeout.to_s, gate_max_blocks.to_s],
      'timeout' => gate_timeout + 30 }
  end

  # The seat's Claude Code settings, written to <state>/settings/<id>.json and passed with
  # --settings. Later features add their own top-level keys (hooks, for example) here.
  def settings(id)
    perms = merged_permissions(id).reject { |_, rules| rules.empty? }
    mode = permission_mode(id)
    # A seat started in another mode cannot be switched into bypass from inside the session.
    perms['disableBypassPermissionsMode'] = 'disable' if mode && mode != 'bypassPermissions'
    out = perms.empty? ? {} : { 'permissions' => perms }
    # Claude Code's auto-updater reinstalls its package under a running seat, and macOS then cannot
    # tell which process the seat's claude is, so its privacy grants (the worktree volume) stop
    # working until a restart (#50). The launch script exports this too; a value here also outranks
    # one in a project's .claude/settings.json. Update deliberately instead (README).
    out['env'] = { 'DISABLE_AUTOUPDATER' => '1' }
    if gate_on_stop?(id)
      out['hooks'] = { 'Stop' => [{ 'hooks' => [stop_gate_hook(id)] }] }
      # --settings outranks project and local settings, so a disableAllHooks: true written in the
      # seat's .claude/ cannot switch the gate off. It also turns on the user's own hooks for this
      # seat if they had switched them all off in ~/.claude/settings.json.
      out['disableAllHooks'] = false
    end
    out
  end

  def permissions_report
    added_by = ->(e) { e[2] == 'factory.sh' }
    out = ["permissions per seat (they add to the rules in ~/.claude/settings.json and the repo's .claude/ settings, which still apply):"]
    roles.each_key do |id|
      merged = merged_permissions(id)
      factory = permission_entries(id).select(&added_by).map(&:first)
      mode = mode_label(id)
      out << "[#{id}] mode #{mode}"
      PERMISSION_LISTS.each do |list|
        own = merged[list] - factory
        out << format('    %-5s: %s', list, own.empty? ? '(none)' : own.join(', '))
      end
      added = merged['deny'].count { |r| factory.include?(r) }
      asks = merged['ask'].count { |r| factory.include?(r) }
      out << "    added: Edit deny on #{added} protected paths#{asks.positive? ? ", ask on #{asks} push-to-#{base_branch} patterns" : ''}"
      out << '    note : allow rules have no effect in bypassPermissions' if mode.start_with?('bypassPermissions') && !(merged['allow'] - factory).empty?
      out << '    note : ask rules are refused in dontAsk mode, not asked' if mode == 'dontAsk' && !merged['ask'].empty?
    end
    out << "note: no base-branch push rules (repo.base '#{repo['base']}' is not <remote>/<branch>)" if base_branch.nil?
    out << "the full generated file: ruby #{File.join(INSTALL, 'lib', 'team_config.rb')} #{@path} settings <role>"
    out
  end

  def validate
    bad = @c.keys - TOP_KEYS
    die "unknown top-level key(s): #{bad.join(', ')} (allowed: #{TOP_KEYS.join(', ')})" unless bad.empty?
    die "'team' is required" unless @c['team'].is_a?(String) && @c['team'] =~ PREFIX_RE
    die "repo.path is required" unless repo['path']
    die "repo.github must be owner/name, e.g. acme/widgets" unless github =~ %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}
    die "project.name is required" if project['name'].to_s.empty?
    die "project.url must be an https://github.com/ URL" unless project['url'].to_s.start_with?('https://github.com/')
    die "repo.path is not a directory: #{repo_path}" unless File.directory?(repo_path)
    die 'storage.volume is required (an absolute path such as /Volumes/MyDrive)' unless storage['volume'].to_s.start_with?('/', '~')
    die 'storage.root is required and must be relative to the volume' if storage['root'].to_s.empty? || storage['root'].to_s.start_with?('/')
    die 'storage.root must not contain ..' if storage['root'].to_s.split('/').include?('..')
    die "sessions.prefix must match #{PREFIX_RE.source}" unless prefix =~ PREFIX_RE
    die 'display.iterm must be true or false' unless [true, false].include?(view_iterm)
    die "display.window must be 'full' or 'keep'" unless %w[full keep].include?(view_window)
    die "display.primary '#{view_primary}' is not a role id (roles: #{roles.keys.join(' ')})" unless roles.key?(view_primary)
    bad = claude.keys - CLAUDE_KEYS
    die "unknown key(s) under 'sessions.claude': #{bad.join(', ')}" unless bad.empty?
    die 'repo.gate must be a non-empty command' if repo.key?('gate') && !(repo['gate'].is_a?(String) && !repo['gate'].strip.empty?)
    %w[gate_timeout gate_max_blocks].each do |k|
      next unless repo.key?(k)

      what = k == 'gate_timeout' ? 'a positive whole number of seconds' : 'a positive whole number'
      die "repo.#{k} must be #{what}" unless repo[k].is_a?(Integer) && repo[k].positive?
    end
    die "sessions.claude.effort must be one of #{EFFORTS.join(', ')}" if claude['effort'] && !EFFORTS.include?(claude['effort'].to_s)
    if claude.key?('permission_mode') && !PERMISSION_MODES.include?(claude['permission_mode'].to_s)
      die "sessions.claude.permission_mode must be one of #{PERMISSION_MODES.join(', ')}"
    end
    bad = (@c['prompts'] || {}).keys - PROMPT_KEYS
    die "unknown key(s) under 'prompts': #{bad.join(', ')}" unless bad.empty?
    die "'roles' must be a non-empty mapping" unless roles.is_a?(Hash) && !roles.empty?
    seen = {}
    roles.each do |id, r|
      die "role id '#{id}' must match #{ID_RE.source}" unless id.to_s =~ ID_RE
      die "role '#{id}' must be a mapping" unless r.is_a?(Hash)
      bad = r.keys - ROLE_KEYS
      die "unknown key(s) under roles.#{id}: #{bad.join(', ')} (allowed: #{ROLE_KEYS.join(', ')})" unless bad.empty?
      die "roles.#{id}.title is required" if r['title'].to_s.empty?
      die "roles.#{id} needs exactly one of 'prompt' (a file) or 'prompt_text'" unless r.key?('prompt') ^ r.key?('prompt_text')
      w = r['workdir']
      die "roles.#{id}.workdir must be a mapping with a type" unless w.is_a?(Hash)
      bad = w.keys - WORKDIR_KEYS
      die "unknown key(s) under roles.#{id}.workdir: #{bad.join(', ')}" unless bad.empty?
      die "roles.#{id}.workdir.type must be 'project' or 'worktree'" unless %w[project worktree].include?(w['type'])
      die "roles.#{id}.workdir.path is required for type project" if w['type'] == 'project' && w['path'].to_s.empty?
      die "roles.#{id}.workdir.path is not allowed for type worktree (it is derived from storage)" if w['type'] == 'worktree' && w['path']
      if w['name'] && w['name'].to_s !~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
        die "roles.#{id}.workdir.name must be a plain folder name"
      end
      die "roles.#{id}.workdir.path is not a directory: #{workdir(id)}" if w['type'] == 'project' && !File.directory?(workdir(id))
      die "roles.#{id}.effort must be one of #{EFFORTS.join(', ')}" if r['effort'] && !EFFORTS.include?(r['effort'].to_s)
      die "roles.#{id}.model must be a non-empty string" if r.key?('model') && r['model'].to_s.strip.empty?
      die "roles.#{id}.gate_on_stop must be true or false" if r.key?('gate_on_stop') && ![true, false].include?(r['gate_on_stop'])
      die "roles.#{id}.gate_on_stop needs repo.gate (the command to run)" if r['gate_on_stop'] == true && gate.nil?
      validate_skills(id, r['skills']) if r.key?('skills')
      if r.key?('permission_mode') && !PERMISSION_MODES.include?(r['permission_mode'].to_s)
        die "roles.#{id}.permission_mode must be one of #{PERMISSION_MODES.join(', ')}"
      end
      s = session(id)
      die "session name '#{s}' is used by both '#{seen[s]}' and '#{id}'" if seen[s]
      seen[s] = id
      role_prompt(id)
      kickoff(id)
    end
    prompts_common
    roles.each_key { |id| render(id) } # unknown @@placeholders fail here, not at launch
    any_mode = claude.key?('permission_mode') || roles.values.any? { |r| r.key?('permission_mode') }
    args.each do |a|
      flag = a.split('=', 2).first
      when_reserved, why = RESERVED_FLAGS[flag]
      next if when_reserved.nil? || (when_reserved == :with_mode && !any_mode)

      die "sessions.claude.args: #{flag} is reserved: #{why}"
    end
    roles.each_key { |id| merged_permissions(id) } # bad rules and useless duplicates fail here
    true
  end
end

path, cmd, *args = ARGV
die 'usage: team_config.rb <team.yaml> <command> [args]' if path.nil? || cmd.nil?
cfg = TeamConfig.new(path)

case cmd
when 'validate' then cfg.validate
when 'ids' then puts cfg.roles.keys
when 'get'
  key = args.fetch(0) { die 'get needs a key' }
  case key
  when 'team' then puts cfg.instance_variable_get(:@c)['team']
  when 'repo.path' then puts cfg.repo_path
  when 'repo.github' then puts cfg.github
  when 'project.name' then puts cfg.project['name']
  when 'project.url' then puts cfg.project['url']
  when 'repo.base' then puts(cfg.repo['base'] || 'origin/main')
  when 'storage.volume' then puts cfg.volume
  when 'storage.root' then puts cfg.root
  when 'storage.worktree_root' then puts cfg.worktree_root
  when 'sessions.prefix' then puts cfg.prefix
  when 'display.iterm' then puts cfg.view_iterm
  when 'display.primary' then puts cfg.view_primary
  when 'display.window' then puts cfg.view_window
  when 'sessions.wrapper' then puts(cfg.claude['wrapper'] ? cfg.expand(cfg.claude['wrapper']) : '')
  when 'state.dir' then puts cfg.state_dir
  when 'state.generated_dirs' then puts GENERATED_DIRS
  when 'repo.gate_summary'
    puts(cfg.gate ? "#{cfg.gate} (timeout #{cfg.gate_timeout}s; a seat may stop after #{cfg.gate_max_blocks} failed gates in a row)" : 'none')
  else die "unknown key '#{key}'"
  end
when 'role'
  id, key = args
  case key
  when 'title' then puts cfg.title(id)
  when 'session' then puts cfg.session(id)
  when 'workdir_type' then puts cfg.workdir_type(id)
  when 'worktree_name' then puts cfg.worktree_name(id)
  when 'model' then puts(cfg.model(id) || '(inherit)')
  when 'effort' then puts(cfg.effort(id) || '(inherit)')
  when 'permission_mode' then puts cfg.mode_label(id)
  when 'gate' then puts(cfg.gate_on_stop?(id) ? 'on-stop' : '-')
  else die "unknown role key '#{key}'"
  end
when 'workdir' then puts cfg.workdir(args.fetch(0) { die 'workdir needs a role id' })
when 'claude_args' then puts cfg.claude_args(args.fetch(0) { die 'claude_args needs a role id' })
when 'render' then puts cfg.render(args.fetch(0) { die 'render needs a role id' })
when 'kickoff' then puts cfg.kickoff(args.fetch(0) { die 'kickoff needs a role id' })
when 'settings' then puts JSON.pretty_generate(cfg.settings(args.fetch(0) { die 'settings needs a role id' }))
when 'permissions_report' then puts cfg.permissions_report
else die "unknown command '#{cmd}'"
end
