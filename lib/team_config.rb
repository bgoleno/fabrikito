#!/usr/bin/env ruby
# frozen_string_literal: true

# Answers the questions factory.sh asks about a team definition file.
#
#   team_config.rb <team.yaml> validate
#   team_config.rb <team.yaml> ids                 role ids, in file order (start order)
#   team_config.rb <team.yaml> get <dotted.key>    e.g. storage.volume, sessions.prefix
#   team_config.rb <team.yaml> role <id> <key>     title | session | workdir_type | worktree_name | model | effort
#   team_config.rb <team.yaml> workdir <id>        absolute working directory of a seat
#   team_config.rb <team.yaml> claude_args <id>    the seat's claude arguments, one per line
#   team_config.rb <team.yaml> render <id>         the seat's full system prompt
#   team_config.rb <team.yaml> kickoff <id>        the seat's first message
#
# Ruby is used because it ships with macOS and parses YAML without installing anything.
# Unknown keys are an error, not ignored: a misspelled `volume:` that silently fell back to a
# default would put worktrees on the wrong disk.
require 'yaml'

def die(msg)
  warn "team config error: #{msg}"
  exit 1
end

TOP_KEYS = %w[team owner repo project storage sessions prompts kickoff roles].freeze
PROJECT_KEYS = %w[name url].freeze
EFFORTS = %w[low medium high xhigh max].freeze
REPO_KEYS = %w[path github base].freeze
STORAGE_KEYS = %w[volume root].freeze
SESSION_KEYS = %w[prefix claude].freeze
CLAUDE_KEYS = %w[wrapper args model effort].freeze
PROMPT_KEYS = %w[common].freeze
ROLE_KEYS = %w[title summary workdir prompt prompt_text kickoff session model effort].freeze
WORKDIR_KEYS = %w[type path name].freeze
ID_RE = /\A[a-z][a-z0-9]*\z/.freeze
PREFIX_RE = /\A[a-z0-9][a-z0-9-]*\z/.freeze

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
      'PROJECT_NAME' => project['name'].to_s, 'PROJECT_URL' => project['url'].to_s, 'TEAM' => @c['team'].to_s, 'OWNER' => owner, 'ROSTER' => roster
    }
  end

  def subst(text, id)
    v = vars(id)
    out = text.gsub(/@@([A-Z_]+)@@/) { v.key?(Regexp.last_match(1)) ? v[Regexp.last_match(1)] : die("unknown placeholder @@#{Regexp.last_match(1)}@@ in a prompt") }
    out
  end

  def render(id)
    common = prompts_common
    subst(common + "\n" + role_prompt(id), id)
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

  def claude_args(id)
    a = claude['args'] || []
    die "'sessions.claude.args' must be a list" unless a.is_a?(Array)
    out = a.map(&:to_s)
    out += ['--model', model(id)] if model(id)
    out += ['--effort', effort(id)] if effort(id)
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
    bad = claude.keys - CLAUDE_KEYS
    die "unknown key(s) under 'sessions.claude': #{bad.join(', ')}" unless bad.empty?
    die "sessions.claude.effort must be one of #{EFFORTS.join(', ')}" if claude['effort'] && !EFFORTS.include?(claude['effort'].to_s)
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
      s = session(id)
      die "session name '#{s}' is used by both '#{seen[s]}' and '#{id}'" if seen[s]
      seen[s] = id
      role_prompt(id)
      kickoff(id)
    end
    prompts_common
    roles.each_key { |id| render(id) } # unknown @@placeholders fail here, not at launch
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
  when 'sessions.wrapper' then puts(cfg.claude['wrapper'] ? cfg.expand(cfg.claude['wrapper']) : '')
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
  else die "unknown role key '#{key}'"
  end
when 'workdir' then puts cfg.workdir(args.fetch(0) { die 'workdir needs a role id' })
when 'claude_args' then puts cfg.claude_args(args.fetch(0) { die 'claude_args needs a role id' })
when 'render' then puts cfg.render(args.fetch(0) { die 'render needs a role id' })
when 'kickoff' then puts cfg.kickoff(args.fetch(0) { die 'kickoff needs a role id' })
else die "unknown command '#{cmd}'"
end
