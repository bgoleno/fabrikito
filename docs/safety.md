# Safety

What the permission rules in each seat's generated settings cover, and what they cannot do.

Each seat starts with a generated settings file, `.state/<team>/settings/<role>.json`, passed with
`--settings` and rewritten read-only on every `up`. It holds the team's `permissions` merged with the
role's (team first; a role can add or tighten a rule, never loosen one), plus what fabrikito adds:

- an `Edit` deny on the files that would change a seat's next start or its live rules: the generated
  settings, launchers and prompts, the message log and the gate's state, the team file and its
  prompts, the launcher (`fabrikito`, `lib/`, `roles/`, `plugin/`), any plugin given with `--plugin-dir`
  in `args`, and the claude `wrapper` (its whole `.app` bundle, if it is in one), the main checkout's `.mcp.json`, `.claude/settings.json`,
  `.claude/settings.local.json`, `.claude/CLAUDE.md`, and `.claude/hooks/`, `rules/`, `skills/`,
  `agents/` and `commands/` (not the root `CLAUDE.md`, which is project work), the
  seat's own `.claude/settings.json` and `settings.local.json`, and Claude Code's user settings, MCP
  config, instructions, user-level rules (`rules/`) and extensions under `~/.claude` and in `~/.claude.json` (and, when
  `CLAUDE_CONFIG_DIR` is set where `up` runs, under that folder too, with the `.claude.json` inside
  it; each seat's launch script pins the same value, so a seat uses a folder its rules protect, and
  the default folder stays protected for sessions started without the variable). `.claude/worktrees/` stays editable: Claude
  Code puts the worktrees it makes there, including those of a worktree seat's subagents, which land
  under the main checkout. A path that runs through a symlink is denied both as configured and as its
  real path, which stops `rm` and `mv` of a protected link; repointing a link with `ln -sf` is not a
  file command Claude Code checks, and is not stopped (checked on 2.1.316). The seat's own `.mcp.json`
  stays editable as project work; its servers normally need approval in a startup dialog, but with a
  user setting such as `enableAllProjectMcpServers` on they load unprompted at the next start;
- an `ask` on any push to the base branch (from `repo.base`), forced or not, since changes land through
  PRs. It is an early warning for a project whose base branch has no protection. The real control is a
  ruleset on the base branch that blocks force-push and deletion and requires a PR; where one exists,
  this ask is redundant;
- an `Edit` allow on the seat's own progress note (see [Progress notes](workflow.md#progress-notes)), which is
  outside its working directory and would otherwise prompt in a mode other than bypass, and an `Edit`
  deny on every other seat's note: a note is put into its seat's context at each start, so a seat
  that could write another's would have a lasting channel into it;
- a `Read` deny on the message log, `.state/<team>/messages.log` (both spellings, when a symlink makes
  them differ), and on the `say/` folder next to it (what `say` keeps of a message it has pasted and not
  yet submitted, #212), for every seat but the role with id `em`: the log holds every `SendMessage` in full. A
  team with no `em` role has the deny on every seat. This is an accident guard, not a boundary: every
  seat runs as the same OS user (#29), and a command that reads the file some other way is not stopped;
- rules on the security-triage record folder, `.state/<team>/triage/` (#138), where the
  `fabrikito:security-triage` skill has `sec` write its records. A record can hold an unfixed
  medium-or-higher finding. The folder is outside every working directory, so without a rule each
  write and read would prompt in a mode other than bypass. The role with id `sec` gets an `Edit` and
  a `Read` allow on `triage/**`, the role with id `em` a `Read` allow (and an `Edit` deny), and every
  other seat an `Edit` and a `Read` deny, all in both spellings. `up` makes the folder (mode 700,
  set on an existing folder too) when the team has a `sec` role; nothing deletes a record. The role
  id is fixed: a team whose security seat has another id gets no record folder, every seat but `em`
  is denied it, and `check` warns about a role other than `sec` that lists the skill. Like the log's, these denies are an
  accident guard, not a boundary. As with any settings change, a `sec` seat that is already running
  when `up` writes these rules keeps its old settings until it restarts;
- denies on **other teams' state folders** (#197), when more than one team runs on the machine. For each
  other team's folder, every seat gets a `Read` deny on its `triage/**` and an `Edit` deny on all of
  it, plus a `Read` deny on its `messages.log` and `notes/**` unless the seat's role observes that team.
  All are written in both spellings. The other teams' folders come from two places:
  - **Found:** every real folder beside this team's own in the state root (`.state/`) that holds
    `settings/`, `launch/` and `prompts/`. A symlink there is never followed. `check` names the links
    it skips: list one under `other_teams` if it is another team's state.
  - **Listed:** `other_teams` in the team file, for a state folder elsewhere (a pinned team's, see
    [Pinned releases](pinned-release.md)), each with its `observers`. These are the roles of this
    team the owner allows to read that team's log and notes, never its triage records:

    ```yaml
    other_teams:
      - { state: /path/to/other/state, observers: [qa2] }
    ```

  A listed folder may not be, hold or sit inside this team's own state folder, its repository, its
  worktree folder or a seat's working directory, whether or not it exists yet. The one exception is a
  team's state folder whose parent is a real folder named `.state`, which may sit inside them once that
  team has run `up` (a pinned team working on fabrikito lists `<install>/.state/<team>`). If
  it exists, it must be a team's state folder itself (holding `settings/`, `launch/` and `prompts/`),
  not its checkout or `.state/` above it. Outside them, one that doesn't exist yet, or is still empty,
  is accepted, and `check` says so. `check` lists the
  other teams found and listed, and each seat's denies. Settings are written at `up`, so a team that starts
  after a seat does is covered from that seat's next restart. Teams on one machine still share the
  machine user, so these denies are an accident guard, like the others: a command that reads or
  writes another way is not stopped. They also share the tmux server and the shared `claude`
  executable the copies come from.

  An observer may read the observed team's message log, which records that team's messages in full
  except those to or from `sec` (their body is not logged, [#227](../../../issues/227)), so it can still
  carry the private reports its seats send to the EM: an unfixed security point among them, before it is
  rated ([#222](../../../issues/222)). An observer treats everything in that log
  under rule 5 of its prompt ([`roles/common.md`](../roles/common.md)): it never quotes the log anywhere,
  and sends `sec` and the EM only a pointer to what it saw: the team and the time of the log line, and
  its line number when several lines share that time.

`permission_mode` (in `sessions.claude`, or per role) picks the mode; the example uses `auto`.
`bypassPermissions` skips every prompt and is meant for an isolated machine only. Deny rules hold in
every mode, bypass included, and ask rules still prompt there, so a seat that hits one waits until
someone answers. `say` will not deliver to a seat at a permission prompt or any other dialog (see
[`say`](../README.md#say)): attach and answer it yourself. These rules add to the ones in `~/.claude/settings.json`
and the repo's `.claude/` settings, which still apply. `check` shows each seat's mode and rules, and is
where load-time errors (unknown modes, malformed rules, a permission flag in `args`) are reported.
It also warns, without stopping a start, about seats whose modes would hold messages between them
([Which messages are held](../README.md#which-messages-are-held)), and about any role whose rules have neither a
deny nor an ask on each of the merge patterns, unless that role is marked `may_merge: true` (a YAML
boolean, so an unquoted `yes` or `on` also counts as true). The patterns, the ones `teams/example.yaml`
denies or asks on ([#85](../../../issues/85)):

- `Bash(gh pr merge *)`: `gh pr merge`, with or without arguments.
- `Bash(gh pr -* merge *)` and `Bash(gh pr -* merge)`: the same with a flag before the subcommand
  (`gh pr -R o/r merge 5`, `--repo o/r`, `--repo=o/r`). The space after `merge` keeps
  `gh pr -R o/r view 5 --json mergeable` out.
- `Bash(gh api *pulls/*/merge*)` and `Bash(gh api graphql*mergePullRequest*)`: the REST and GraphQL merge.
- `Bash(gh api graphql*enablePullRequestAutoMerge*)`: auto-merge.
- `Bash(gh api graphql*mergeBranch*)` and `Bash(gh api *repos/*/merges*)`: merging a branch without a PR.

A team file written before these were added gets the warning until it has them. Known false matches:
a `gh pr -R o/r <subcommand>` whose later text has ` merge ` in it, and `gh api` reads whose path or
query names these. Not covered: a GraphQL query read from a file or stdin (`-F query=@q.graphql`,
`--input`), `curl` or other HTTP clients against the API, `gh` aliases, extensions and scripts, a
`git push` of a merge commit to the base branch (the base-branch push ask covers that), and other
hosts' CLIs.

Claude Code's auto memory is off in every seat: the generated settings set `autoMemoryEnabled: false`
and `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, and the launch script exports the variable. Auto memory lives
in one folder per repository (`<config>/projects/<repo>/memory/`), shared by all its worktrees, and its
`MEMORY.md` loads into every session there, the owner's own in the main checkout included
([docs](https://code.claude.com/docs/en/memory#storage-location)). A seat's note there would reach every
other seat and the owner without review, outside the PR process. Set `auto_memory: true` under
`sessions.claude`, or on a role, to leave it to Claude Code's own settings (that seat's launch script
unsets the variable, so it is not inherited from a tmux server started inside a seat). `check` shows it per seat
in the MEMORY column.

Turning auto memory off stops a seat from writing memory by itself, but not from editing that folder
with its file tools. So every seat with auto memory off also gets an `Edit` deny (which covers the
Write tool too) on the repository's auto-memory folder, in every config folder and both spellings of
the main checkout's path ([#108](../../../issues/108)). Claude Code names the folder after that path, with
every non-alphanumeric character turned into `-`; a name over 200 characters is matched by its first
200 and a `*`, because Claude Code appends a hash to it. As with the other denies, Bash redirects, `tee`
and `cp` into the folder are stopped too, and a script that opens the file itself is not (checked on
Claude Code 2.1.314). `check` names the deny in each seat's `added:` line. The deny covers only that
default folder: if you set `autoMemoryDirectory` in your settings, your sessions load memory from the
folder it names, and the deny keeps protecting a folder nobody reads, with no warning.

These rules are an accident guard, not a security boundary: every seat runs as the owner's OS user,
with the owner's GitHub credential, and can change what loads. [#29](../../../issues/29) tracks making
them a boundary.

What the rules cannot do:

- A Bash rule matches the command text. The same program under another path (`/usr/bin/gh`), inside
  `sh -c`, in a script, or reached another way is not matched: for example `git -C <dir> push`, a bare
  `git push` while on the base branch, or `gh api` with a PATCH or DELETE on `git/refs/heads/<base>`.
- A `Read` deny covers Claude's file tools and the file commands it recognises in Bash (`cat`, `head`,
  `tail`, `sed`, `tee`, redirects). It does not cover `grep -r` over a folder, `git show` of a committed
  file, or a Python or Node script that opens the file itself. A `Read` deny on `.env` files keeps a
  seat from opening one by accident; it does not keep a value out of its reach (the Read tool and `cat`
  were refused, while `git show` and a recursive grep returned a dummy value, on Claude Code 2.1.316,
  [#248](../../../issues/248)). Keep real credentials out of the repository and the worktrees.
- The protected-path `Edit` denies stop the file tools, redirects, and `cp`, `mv` and `rm` with a
  protected file as the target (checked on Claude Code 2.1.316). They match the command text Claude
  writes, so they do not stop the same command run through another shell or a script (`sh -c 'cp …'`,
  which qa checked gets through), or a program that writes the file itself, such as a Python or Node
  script.
- A subagent a seat starts with worktree isolation runs under the seat's own rules, not under the
  `.claude/settings.json` in its worktree (checked on Claude Code 2.1.316, [#53](../../../issues/53)):
  the worktree's file held a deny, yet the subagent's matching command ran with no denial, because the
  parent session had no deny loaded. Editing a worktree's settings therefore does not change what such a
  subagent may do. Two paths were not checked: `EnterWorktree`, which moves the session itself into a
  worktree, and a separate `claude` process a seat starts from Bash. That process loads the project
  settings of its own folder and does not get the seat's generated `--settings` file at all, which is
  the general limit above: the rules guard against accidents. Severity as sec rated it: low.
- "Never force-push a branch you did not create" cannot be written as a pattern. Engineers keep
  force-pushing their own branches; only the EM is asked.
- Any process running as this user can type into a seat's pane, so an ask rule guards against
  accidents. It is not a gate that only the owner can pass.
- Seats act with the owner's GitHub rights, so they can change a ruleset or branch protection through
  the API. No rule here stops that (an ask that matched it would also stall seats reading the
  settings); [#29](../../../issues/29) tracks the fix.
- Settings above these files apply as well: managed settings, and, depending on the account, installed
  mods, which can approve calls these rules would stop.
- Paths in Read and Edit rules: `//path` is absolute, `~/path` is under the home folder, `./path` or a
  bare name is relative to the seat's folder. A single leading `/` anchors at the folder that holds the
  generated file, so it is refused.
- Claude Code matches permission rules against each part of a compound command (`;`, `&&`, `|`), but
  against the whole command text when it can't parse the command (for example `"$(...)"` in an
  argument, such as a PR body from `$(cat <<EOF ...)`, or `${...}` next to quotes). In default mode, a
  subshell `( ... )` or a command it can't parse prompts even when no rule matches (the reason varies:
  "can't be checked before it runs", "shell operators that require approval"); in bypass mode it
  prompts only when a rule matches (measured on 2.1.316, [#103](../../../issues/103); other modes not
  measured). So seats run `git push` as its own simple command: chained with an unparseable part, a
  `main` elsewhere in the command makes it match the base-branch ask. A prompt that names a rule
  (`Permission rule ... requires confirmation`) means the command's text matched an ask rule, even
  when the reason it shows is about parsing ("expansion obfuscation", "shell operators that require
  approval"): that reason only says why Claude Code could not narrow the prompt to the matching part.
  The shared prompt keeps the instructions (push alone, avoid a subshell, a named rule means a match)
  and leaves this mechanism here ([#117](../../../issues/117)).
- Seats push with `git push origin <branch>:<branch>` on a branch cut with `--no-track`. A branch cut
  with `git switch -c <branch> origin/main` has the base as its upstream, so under
  `push.default=upstream` a bare `git push`, or even `git push origin <branch>`, would push to the base.

The [sandbox](https://code.claude.com/docs/en/sandboxing) is the OS-level control that would hold
whatever the command text, but the launcher does not turn it on: seats run without one unless settings
that apply to them enable it. The hard rules in the shared prompt (`roles/common.md`) still apply;
read them before changing them. A seat started in a folder Claude Code has not seen stops at a trust
dialog until a human answers it once; `up` reports which seats those are.
