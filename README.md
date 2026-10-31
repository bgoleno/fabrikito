# software-factory

Starts a team of Claude Code sessions for a software project. Each seat (engineering manager, tech
lead, engineers, QA, security, or whatever you define) runs in its own persistent tmux session, is
told its role, works in its own git worktree, and can message the other seats.

The team is defined in one YAML file per project, so different projects can have different teams,
prompts, models and storage.

## Requirements

macOS, `tmux`, `claude` (Claude Code), `git`, `gh`, and the system `ruby` (it parses the YAML; it ships
with macOS). Optional: a wrapper program that runs claude (see `sessions.claude.wrapper`). A C compiler
is needed only for `test/e2e.sh`.

## Use

```
cp teams/example.yaml teams/team.yaml     then edit it: repo, project, storage, roles
./factory.sh check                        validate the team file, show where everything lives
./factory.sh up [role...]                 start the team (all roles, in file order)
./factory.sh status                       which seats are up, and where each works
./factory.sh view                         open an iTerm tab with every running seat in a pane
./factory.sh titles                       set each running seat's terminal title (role | title | session)
./factory.sh say <role|all> "..."         type a message into a seat (seats use SendMessage)
./factory.sh attach <role>                attach your terminal (detach: ctrl-b d)
./factory.sh migrate [role...]            remove clean worktrees that are not on the storage volume
./factory.sh down --yes [role...]         kill seats (worktrees are kept)
./factory.sh -c path/to/other.yaml up     use a different team file
```

The team file is `-c`, else `$TEAM_CONFIG`, else `teams/team.yaml`. `teams/example.yaml` documents every
key. Team files other than the example, and anything under `projects/`, are git-ignored so each
project's specifics stay out of this repository. Keep a project's own prompts under `projects/<name>/`
and point the team file at them.

`up` takes a team file outside `teams/` for a throwaway one (a test) and will not start its seats on your
default tmux server, where a real team runs: run it on a private server (see Tests), or pass
`up --default-socket` if that team is meant to run there.

## The iTerm view

`up` opens a new iTerm tab showing every running seat, unless `--no-view` is given or `display.iterm`
is `false`; `view` opens it any time. The primary seat (`display.primary`, default the first role) is
the left half at full height, since it is the one you talk to. The others fill rows on the right, two
per row, and an odd last seat gets a full-width row. The window is sized to the usable area of the
screen it is on (`display.window: full`). Each pane is a `tmux attach` to the seat's session, so
closing the tab detaches and never stops a seat. Each pane's header reads `<role> | <title> | <session>`:
the launcher sets tmux's `set-titles-string` on every seat (at start, and again by `view` or `titles`). The first run asks macOS for permission to control
iTerm.

## The team file

- `repo`, `project`, `owner`: the local checkout, its GitHub repo (`owner/name`), the GitHub Project the
  team tracks work on, and the human it works for. The prompts name them, so this is the only edit to
  retarget a team. `repo.gate` is the repo's pass/fail command: see [The gate](#the-gate).
- `storage`: `volume` and `root`. Every worktree is created under `<volume>/<root>/`. The volume must be
  mounted, checked from the mount table when a worktree is created; the launcher never falls back to
  another disk.
- `sessions`: tmux name prefix, an optional claude `wrapper`, `args`, and an optional default `model`,
  `effort` and `permission_mode`. Unset means the flag is omitted and the seat inherits
  `~/.claude/settings.json`. `sessions.claude.plugin` (default `true`) loads the factory plugin into
  every seat: see [The factory plugin](#the-factory-plugin).
- `permissions` (`deny`, `ask`, `allow`), at the top level and per role: see [Safety](#safety).
- `prompts.common` and a per-role `prompt` (file) or `prompt_text` (inline). Placeholders such as
  `@@ROSTER@@`, `@@GITHUB_REPO@@`, `@@PROJECT_URL@@` and `@@WORKTREE_ROOT@@` are filled in per seat.
- `roles`: ordered; each has `title`, `workdir` (`project` folder or `worktree`), a prompt, and
  optional `model`, `effort`, `session`, `kickoff`, `summary`, `skills`.
- `skills` (per role): skills to name in that seat's prompt, each a name (`plugin:name` for a plugin's
  skill) with an optional note on when to use it. They are listed after the role's prompt with a note
  that a skill may not be installed; naming one installs nothing. The example team lists commonly
  useful ones from the superpowers plugin and Claude Code's bundled skills.

Unknown keys, missing prompt files, duplicate session names and unknown placeholders are errors at load
time, before anything starts.

## The factory plugin

`plugin/` is a Claude Code [plugin](https://code.claude.com/docs/en/plugins) (`.claude-plugin/plugin.json`
and `skills/`) that `up` loads into every seat with `--plugin-dir <this checkout>/plugin`. Seats work in
the target project's folders, where this repository's own `.claude/` is never read, so this is how the
factory's skills reach them. Nothing is installed into your settings: a session the factory did not start
does not have the plugin. Its skills are namespaced by the plugin name and show as `/factory:<skill>`. For
now it holds one placeholder, `/factory:ping`, which only proves the plugin loaded.

- It is on by default. A team file without `sessions.claude.plugin` gets the plugin at its next `up`, and
  with it every skill (and, later, every hook or agent) added to `plugin/` after that. Set
  `sessions.claude.plugin: false` to leave the flag out. `check` shows the plugin's path, or `off`.
- A `--plugin-dir` of your own in `sessions.claude.args` is allowed: the flag repeats, so both load. Your
  installed plugins load as usual alongside it.
- Seats get an `Edit` deny on `plugin/`, like `lib/` and `roles/` (see [Safety](#safety)), since it is
  code every seat runs at its next start, and on each plugin a team loads itself with `--plugin-dir` in
  `args` (the folder with everything under it, or the `.zip`; a relative path is taken from the seat's
  folder).
- What the plugin carries runs in or steers every seat: skills, agents, commands, hooks and MCP
  servers, including hooks and servers declared inline in `plugin.json`. So every pull request that
  changes anything under `plugin/`, `plugin.json` included, gets a security review as well as the
  usual one.
- Managed settings can turn `--plugin-dir` off (Claude Code's docs say so; not tried here), and then the
  seats have no factory skills.

## Issues first

Every change starts as an issue. The shared prompt (`roles/common.md`) makes this a hard rule for every
seat: no change starts without an issue, and the engineering manager files one when it is missing. A
pull request that completes its issue says `Closes #<n>`, and one that does not says `Refs #<n>` (see
`.github/pull_request_template.md`), so the issue closes exactly when its change lands and the board
stays honest.

## How seats talk

Seats message each other with Claude Code's
[cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging): `SendMessage` to a
session name, and `ListAgents` to see which sessions are up. `up` starts every seat with `-n <session>`,
so the names are the roster's session column, and the shared prompt (`roles/common.md`) tells seats to
use them. A message arrives between tool calls without interrupting a running tool. It cannot answer a
permission prompt or change settings, and bursts and loops are throttled. A seat waiting on another can
ask for one notice when that seat next goes idle (`notify_when_idle`) instead of polling it.

Session names are not authenticated: a sender's name is a claim, not an identity. Claude Code's own
held-message notice shows the sender as a verified process id and the name it claims ("peer claims
name"). Every Claude session on the machine, other teams' seats included, can message a seat, and any
local process can start a session under a seat's name. A delivered message carries the sender's address
in `from` and its session name in `from-name`. The prompt tells seats to act only on a `from-name` that
exactly matches a roster name, and to report any other sender, or two sessions sharing a roster name, to
the EM. That guards against mistakes, not impersonation, which is the same limit as for `say` and the
pane (see [Safety](#safety)).

### Which messages are held

The launcher sets no `crossSessionInbound`, so Claude Code decides per message from the two sessions'
permission modes. `bypassPermissions` is one class, and every other mode (`auto`, `acceptEdits`,
`dontAsk`, `default`) is the other.

| From, to | What happens |
|---|---|
| Seat to seat, both in one class (one `permission_mode` for every seat) | Delivered. |
| Seat to seat, different classes (a role with its own `permission_mode`) | Held. An approval dialog opens in the receiver's pane, and if nobody answers it the message is dropped after `dialogExpiry` (5 minutes by default). In an unattended team, that means it is lost. `check` warns when the seats fall into both classes, naming the roles in each. |
| The owner's own Claude session to a seat | The same rule: delivered when both are in one class, held otherwise. |
| Any other Claude session on the machine to a seat | The same rule. |
| The owner typing into an attached seat, or `say` | Not a cross-session message, so it is never held. |

The sender gets a notice when a message is held, refused or expires. The prompt tells a seat never to
resend the content with `say`: a refusal is the receiver's decision, and a hold waits for a human in
that pane. While a message to a seat is held, the sender does not use `say` to that seat at all, because
its pane is showing the approval dialog; it waits for the notice that the message was delivered or
expired. A refused or expired message is reported to the EM with `SendMessage`, or with `say em` if the
EM was the receiver or the report was refused or expired too, and never with `say em` while a hold to
the EM is pending. `say` is the seats' fallback only for a running seat that `ListAgents` does not show.

To change the default, set `crossSessionInbound` to `accept`, `hold` or `refuse`. It is read from managed
settings, then the `--settings` file, then user settings, and the first value found applies. A project or
local value applies only when it is stricter. `accept` in user settings delivers every message to every
session you run, from any local session, so think twice before using it with bypass seats. The team file
has no key for it. `dialogExpiry` (`60s`, `5m`, `10m` or `never`) can be set only in user or managed
settings.

### `say`

`say` is how the owner and scripts reach a seat, and the seats' fallback for a seat that `SendMessage`
cannot reach. It types a message into the seat's tmux pane by bracketed paste, then presses Enter. It
types only when the bottom of the seat's screen is Claude Code's input box, empty or showing only one
dim line (a hint or a suggested prompt), and presses Enter only when the box then holds just the
message. Anything else fails closed, with a reason:

- a seat that is not running claude (the text would run as a shell command);
- any dialog, prompt or menu, known or not, the held-message approval dialog included ("screen not
  recognised as ready"), where the Enter would pick an answer;
- an input box that already holds text (someone typing, or an earlier message that was not sent);
- a pane in copy mode (someone scrolling);
- a screen tmux cannot read.

Attach to the seat, deal with it, and send again. If the box does not show the message after the paste,
no Enter is sent and the text stays in the box, where it goes out with the next Enter; `say` says so.
The input box is recognised as Claude Code 2.1.316 draws it, so a CLI update that changes it makes `say`
refuse every seat until `factory.sh` is updated. A refused message is logged as NOT-DELIVERED. Messages
are labelled `[from <role>]`, and the owner's are `[from owner]`. The label is set by the sender (from
`TEAM_ROLE`, or `owner` when it is unset) and is not authenticated. When `TEAM_ROLE` is unset, `say`
run from inside a seat (found from the terminals of the processes that started it) is labelled with
that seat's role, never `[from owner]`; this stops a mislabel by accident, and the labels are still
not authenticated ([#29](../../issues/29)).

### The message log

`.state/<team>/messages.log` records every `say` with its delivery outcome. Until #39 lands (a hook that
logs `SendMessage` too), it records `say` traffic only: read `SendMessage` traffic in each session's
transcript (`ctrl+o` in an attached seat).

Each `say` (`say all` included) appends exactly one line of five tab-separated fields: the local time
(`2026-10-30T14:05:09`), the sender (`TEAM_ROLE`, the seat `say` ran inside, or `owner`), the recipient (a role id or `all`),
`delivered` or `NOT-DELIVERED`, and the message as typed, without its `[from <role>]` label. The
sender and the message are escaped so the record stays on one line and holds no terminal control
codes: a backslash is written `\\`, a newline `\n`, a carriage return `\r`, a tab `\t`. Every other C0
control (below U+0020), DEL, C1 control (U+0080 to U+009F) and bidi embedding, override or isolate
(U+202A to U+202E, U+2066 to U+2069) is written as its UTF-8 bytes, each as `\xHH` (two upper-case hex
digits): U+009B is `\xC2\x9B`. Other text, such as `é` or `✓`, is written as it is. A message that is
not valid UTF-8 has every byte from 0x80 up written as `\xHH`. If the escaping itself fails, the field
reads `<log_field failed>`. The escaping is reversible: `printf '%b' "<field>"` in bash gives back
the original text. The hook that will log `SendMessage` traffic (#39) is to write this same format.

## Safety

Each seat starts with a generated settings file, `.state/<team>/settings/<role>.json`, passed with
`--settings` and rewritten read-only on every `up`. It holds the team's `permissions` merged with the
role's (team first; a role can add or tighten a rule, never loosen one), plus two sets factory.sh adds:

- an `Edit` deny on the files that would change a seat's next start or its live rules: the generated
  settings, launchers and prompts, the message log and the gate's state, the team file and its
  prompts, the launcher (`factory.sh`, `lib/`, `roles/`, `plugin/`), any plugin given with `--plugin-dir`
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
  this ask is redundant.

`permission_mode` (in `sessions.claude`, or per role) picks the mode; the example uses `auto`.
`bypassPermissions` skips every prompt and is meant for an isolated machine only. Deny rules hold in
every mode, bypass included, and ask rules still prompt there, so a seat that hits one waits until
someone answers. `say` will not deliver to a seat at a permission prompt or any other dialog (see
[`say`](#say)): attach and answer it yourself. These rules add to the ones in `~/.claude/settings.json`
and the repo's `.claude/` settings, which still apply. `check` shows each seat's mode and rules, and is
where load-time errors (unknown modes, malformed rules, a permission flag in `args`) are reported.
It also warns, without stopping a start, about seats whose modes would hold messages between them
([Which messages are held](#which-messages-are-held)), and about any role whose rules have neither a
deny nor an ask on each of the three merge patterns (`Bash(gh pr merge *)`, `Bash(gh api *pulls/*/merge*)`,
`Bash(gh api graphql*mergePullRequest*)`), unless that role is marked `may_merge: true` (a YAML boolean, so an unquoted `yes` or `on`
also counts as true).

These rules are an accident guard, not a security boundary: every seat runs as the owner's OS user,
with the owner's GitHub credential, and can change what loads. [#29](../../issues/29) tracks making
them a boundary.

What the rules cannot do:

- A Bash rule matches the command text. The same program under another path (`/usr/bin/gh`), inside
  `sh -c`, in a script, or reached another way is not matched: for example `git -C <dir> push`, a bare
  `git push` while on the base branch, or `gh api` with a PATCH or DELETE on `git/refs/heads/<base>`.
- A `Read` deny covers Claude's file tools and the file commands it recognises in Bash (`cat`, `head`,
  `tail`, `sed`, `tee`, redirects). It does not cover `grep -r` over a folder, or a Python or Node
  script that opens the file itself.
- The protected-path `Edit` denies stop the file tools, redirects, and `cp`, `mv` and `rm` with a
  protected file as the target (checked on Claude Code 2.1.316). They match the command text Claude
  writes, so they do not stop the same command run through another shell or a script (`sh -c 'cp …'`,
  which qa checked gets through), or a program that writes the file itself, such as a Python or Node
  script.
- "Never force-push a branch you did not create" cannot be written as a pattern. Engineers keep
  force-pushing their own branches; only the EM is asked.
- Any process running as this user can type into a seat's pane, so an ask rule guards against
  accidents. It is not a gate that only the owner can pass.
- Seats act with the owner's GitHub rights, so they can change a ruleset or branch protection through
  the API. No rule here stops that (an ask that matched it would also stall seats reading the
  settings); [#29](../../issues/29) tracks the fix.
- Settings above these files apply as well: managed settings, and, depending on the account, installed
  mods, which can approve calls these rules would stop.
- Paths in Read and Edit rules: `//path` is absolute, `~/path` is under the home folder, `./path` or a
  bare name is relative to the seat's folder. A single leading `/` anchors at the folder that holds the
  generated file, so it is refused.

The [sandbox](https://code.claude.com/docs/en/sandboxing) is the OS-level control that would hold
whatever the command text, but the launcher does not turn it on: seats run without one unless settings
that apply to them enable it. The hard rules in the shared prompt (`roles/common.md`) still apply;
read them before changing them. A seat started in a folder Claude Code has not seen stops at a trust
dialog until a human answers it once; `up` reports which seats those are.

## The gate

`repo.gate` is the repository's pass/fail command. A role with `gate_on_stop: true` gets a Stop hook in
its generated settings (`lib/stop_gate.sh`): whenever the seat ends a turn with uncommitted changes in
its working tree, the hook runs the gate there, and if it fails the seat is sent back to work with the
command, the last 60 lines of its output and the path of the full log (`.state/<team>/gate/<role>.log`).
Roles without the switch never run it. The example gives it to the engineers and qa.

- Only uncommitted work is gated at a stop: a clean tree, including committed but unpushed work, ends
  the turn normally. Committed work is gated again when the reviewer runs the gate on the PR.
- Only the seat's configured working tree is checked. Work left in another tree, such as a worktree
  Claude Code made for a subagent or for `EnterWorktree` under `<repo>/.claude/worktrees/`, is not
  gated.
- The gate catches mistakes, not a seat that edits the gate. It runs the scripts in the seat's own tree
  (a Makefile, test scripts), at the stop and outside Claude Code's permission rules: no prompt, no
  deny or ask rule, no auto-mode classifier. A seat that changes those files decides whether its gate
  passes and what runs at its next stop, so for a seat that is not in bypass mode, permission to edit
  its tree becomes commands that run unprompted at the stop. The reviewer's own run of the gate on the
  PR stays the real check.
- A seat also stops on purpose: to wait for an answer or a review, or with a test red before the fix.
  After `repo.gate_max_blocks` (default 3) failed gates in a row in one turn, the next stop in that turn
  goes through without running the gate again, with a note that the gate is still failing, and the seat
  is told to say so in its report. Each new turn starts from zero, so a seat that lives for days is
  never gated off for good. The count is in the state folder, which seats cannot edit through Claude
  Code's tools; a passing gate or a clean tree resets it. A script can still write it, or run the hook
  with made-up input, like every other "a script can do it" limit under [Safety](#safety). Run by hand
  with no hook input, `lib/stop_gate.sh` runs the gate and reports but leaves the count alone. Claude
  Code also ends such a loop itself after 8 continuations with no tool call in between (raise it with
  `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).
- The gate runs with a time limit (`repo.gate_timeout`, default 600 s) in a process group of its own,
  which is killed whole when the time is up. A program that detaches from that group (a daemon, a tmux
  server) is not killed.
- The hook inherits the seat's environment, which runs inside tmux: a gate that must not touch the
  team's tmux server unsets `TMUX` itself, as this repository's does.
- The gate runs at every such stop, so a slow gate (this repository's e2e takes over a minute) makes
  those stops slow.
- A gated seat's settings set `disableAllHooks: false`, so a `.claude/settings.json` in the project
  cannot switch the gate off. That also turns the user's own hooks back on for that seat if
  `~/.claude/settings.json` had switched them all off.

## Updating Claude Code

Claude Code's updater replaces its shared executable (the npm package's `bin/claude.exe`), even with
the same version, and every Claude Code session on the machine runs it, not only this team's seats.
macOS then can no longer identify a seat still running the old file, and the privacy grants it runs
under (a removable volume holding the worktrees, for example) stop working until the seat restarts
(#50). So:

- **Each seat runs the team's own copy of claude**, `.state/<team>/bin/claude-<version>/claude`. `up`
  makes it from the shared executable when it is missing: an APFS clone where the state folder is on
  the same file system (it takes no space while the shared file exists), else a plain copy. It is
  checked (size, `--version`) before use, and if it cannot be made, `up` stops instead of running the
  shared file. Nothing but `up` writes there, and seats cannot edit it.
- **The seats' own updater is off** (`DISABLE_AUTOUPDATER=1`, in the launch script and the generated
  settings), so the seats do not add reinstalls of their own.
- `check` names the shared executable, its version and the copy seats will run, and lists every copy
  with the running seats that use it. `status` shows each running seat's executable, or `REPLACED`
  when the file it runs has been swapped under it; `up` prints an ATTENTION line for such a seat.
  Restart it (`down --yes <role>`, then `up <role>`).

To update: `claude update` in your own shell (a manual update works with the variable set), then
`./factory.sh down --yes` and `./factory.sh up`. The next `up` copies the new version, and every seat
starts on it.

Old copies are never removed automatically. Once the shared file has moved on, each one holds about
310 MB. When `check` lists a copy with no running seat, remove that folder by its exact path, for
example `rm -r .state/<team>/bin/claude-2.1.314`.

## Tests

A live test (a throwaway team with a real `claude`, or anything else that starts tmux sessions) runs on a
private tmux server through `test/live-env.sh`, never on the server you work in:

```
d=$(test/live-env.sh new)                                  a private folder: tmux/, state/
test/live-env.sh run "$d" ./factory.sh -c /path/to/throwaway.yaml up
test/live-env.sh run "$d" tmux ls                          any command, with TMUX unset, TMUX_TMPDIR=$d/tmux,
                                                           TEAM_STATE_DIR=$d/state and TEAM_VIEW=0
test/live-env.sh down "$d"                                 stop its tmux server, remove the folder
```

Each call checks the folder on its own (made by `new`, its tmux folder not `/tmp`), so it works from a fresh
shell each time. Setting `TMUX_TMPDIR` by hand is easy to get wrong: tmux 3.7 follows `$TMUX` when it is set,
and falls back to the default server, silently, when `TMUX_TMPDIR` is empty or names a folder that does not
exist. A throwaway team's worktrees on the volume are not removed by `down`; remove them by their paths.

`TEST_VOLUME=/Volumes/YourDrive test/e2e.sh` runs the launcher against a throwaway repo with a stand-in
`claude` on a private tmux server. It covers worktree placement on the volume, per-role model and
effort, message delivery, migrating a legacy worktree (clean and dirty), and refusing to run when the
volume is not mounted. It also covers the generated settings files (merged rules, protected paths,
base-branch rules, permission mode and launch flags), the factory plugin (its manifest, `--plugin-dir`
with the plugin's real path, `sessions.claude.plugin: false`, a bad value, a missing manifest, a team's
own `--plugin-dir` in `args`), the load-time checks on modes, rules and `args`,
`say` delivering only to a seat whose input box is showing (dialogs captured from Claude Code
2.1.316, an unknown dialog, text in the box, copy mode, an unreadable screen), and the gate: the
generated Stop hook, its load-time checks, and `lib/stop_gate.sh` itself (clean tree, failure, the
limit, a new turn or session, a pass, a timeout that kills the gate's process group), and the
auto-updater being off in every seat and nowhere else, and the seats' own copy of claude (made by
`up`, never the shared file; still intact after the shared file is replaced; `REPLACED` when its own
file is swapped; a copy that cannot be made, or a shared install caught mid-reinstall, stops the
start). It also covers `up` refusing a throwaway team on the default tmux server (TMUX and TMUX_TMPDIR
unset, `/tmp` by two spellings, an empty or missing TMUX_TMPDIR, TMUX naming the default socket) before any
tmux call, going ahead on a private server, for a team file in `teams/` and with `--default-socket`, and
`test/live-env.sh` (its environment and private socket, and refusing a missing folder, one `new` did not
make, and one whose tmux folder resolves to `/tmp`).
