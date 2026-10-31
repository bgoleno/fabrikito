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
`up --default-socket` if that team is meant to run there. `down` (with or without `--yes`), `say`, `attach`
and `view` apply the same rule before any tmux call, because a copy of a real team file shares its session
prefix and would reach the real seats: kill them, type into them, or show them
([#105](../../issues/105)). Each takes `--default-socket` too (`say` and `attach`: as the first argument),
and `up --default-socket` passes it on to the view it opens. So a throwaway team file never goes in `teams/`,
neither this checkout's nor a worktree's copy of it: there every command takes it for a real one. Put it
in a temporary folder and run it on a private server.

## The iTerm view

`up` opens a new iTerm tab showing every running seat, unless `--no-view` is given or `display.iterm`
is `false`; `view` opens it any time. The primary seat (`display.primary`, default the first role) is
the left half at full height, since it is the one you talk to. The others fill rows on the right, two
per row, and an odd last seat gets a full-width row. The window is sized to the usable area of the
screen it is on (`display.window: full`). Each pane is a `tmux attach` to the seat's session, so
closing the tab detaches and never stops a seat. Each pane's header reads `<role> | <title> | <session>`:
the launcher sets tmux's `set-titles-string` on every seat (at start, and again by `view` or `titles`). The first run asks macOS for permission to control
iTerm.

## Right-sizing

Every seat is a separate Claude Code session with its own context, so token use grows with the number
of seats that are working, and with how long each works. Coding has fewer truly parallel tasks than it
seems: three focused seats often get more done than five scattered ones, and a team of three to five is
a good start.

- Start only the seats a task needs: `./factory.sh up em tl fs1`. Add one later with `up fs2`, and stop
  one that is done with `down --yes fs2` (its worktree is kept).
- An idle seat spends little (Claude Code's session recap and idle compaction can still use some
  tokens). A message delivered to it starts a turn that sends its whole conversation again, so a seat
  that is sent many messages keeps spending.
- Effort is the main cost and depth control (`effort` per role, or `sessions.claude.effort` for all).
  The example team runs the manager at `medium` and the seats that write, test and review code at
  `high`; keep `max` for a hard problem a seat works on unattended, such as a security hunt. A `model`
  per role works the same way. `./factory.sh check` shows each seat's model and effort, and
  `(inherit)` where the seat takes them from `~/.claude/settings.json`.
- To see what a team costs, run `/usage` in a seat. Its Session block counts that seat's own tokens
  (its dollar figure is a list-price estimate, meaningful on API billing). On a subscription it also
  shows the plan usage bars, which every seat draws on, and a breakdown (by skill, subagent, plugin
  and MCP server, with recommendations) of recent usage computed from this machine's session history.
  That covers all the seats together, but also every other Claude Code session on the machine, and it
  is not split by seat. See [Manage costs](https://code.claude.com/docs/en/costs).

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

Text is UTF-8 whatever the locale (`LC_ALL=C`, cron, `env -i`): the team and prompt files, and the
values the launcher fills in from outside them (`TEAM_SCRIPT`, `TEAM_LOG`, `TEAM_STATE_DIR`,
`CLAUDE_CONFIG_DIR`, the home folder, the team file's own path), so non-ASCII paths and names work in
prompts, kickoffs and settings. Invalid UTF-8 in any of them is an error that names where it came from.

## New worktrees

A worktree `up` creates is a fresh checkout of `repo.base`: none of the main checkout's git-ignored
files are there (an `.env`, local config), and nothing is installed. Two optional `repo` keys set it up
before its seat starts, the way Claude Code's own worktrees use `.worktreeinclude` and an install
command ([docs](https://code.claude.com/docs/en/worktrees)):

- `repo.copy`: paths relative to the main checkout, copied into the new worktree (files or folders;
  meant for small files). A path that does not exist is a warning; a file the worktree already has is
  left as it is. Paths must stay inside the checkout. Only real files and folders are copied: a path
  that is or contains a symlink, or that a symlinked folder would lead out of the checkout or out of
  the worktree, stops the setup.
- `repo.bootstrap`: a command run with bash in the new worktree after the copy, with no terminal input
  and with `TEAM_ROLE` (the seat's role id) and `TEAM_REPO` (the main checkout) set, for example
  `npm ci` or `uv sync`. Its output is shown, indented, as it runs. It runs without the messaging and
  tmux variables of a seat that runs `up` (`CLAUDE_CODE_MESSAGING_*`, `CLAUDECODE`, `TMUX`,
  `TMUX_PANE`), so a seat's messaging token does not reach an install script. There is no time limit.
  If it fails, or `up` is interrupted meanwhile (Ctrl-C, TERM, HUP), `up` stops the bootstrap and
  stops before starting the seat; a worktree it has just made is removed (by that exact path), so the
  next `up` starts over.

When both have finished, `up` marks the setup done (`<state>/setup/<role>`, with the worktree's path).
Every later `up` checks that mark for a worktree it finds, and redoes the copy and the bootstrap
before the seat starts when the mark is missing: after a start that was killed or crashed midway, or
when `repo.copy` or `repo.bootstrap` was added after the worktree was made. A failure there leaves
that existing worktree as it is (it may hold work). Neither runs for a `project` workdir. `check`
shows them.

`up` starts the roles in file order and stops at the first one it cannot start, this setup included:
the seats started before it keep running, and the next `up` starts the rest (it skips running seats).

Do not list real credentials in `repo.copy`: each copy is another file on the worktree volume that a
seat works in. Use development values, or have the bootstrap fetch what it needs. The team's `Read`
deny on `.env` files covers a copied `.env` like the original.

Package stores when worktrees are on another volume: tools that hard-link from a shared store
(pnpm, uv) can only link within one volume, so with the store on the internal disk and the worktrees
elsewhere each worktree gets full copies instead. Point the store at the worktree volume from the
bootstrap, for example `pnpm install --store-dir /Volumes/<drive>/.pnpm-store` or
`UV_CACHE_DIR=/Volumes/<drive>/.uv-cache uv sync`. A plain download cache (npm's) works from either disk.

## The factory plugin

`plugin/` is a Claude Code [plugin](https://code.claude.com/docs/en/plugins) (`.claude-plugin/plugin.json`
and `skills/`) that `up` loads into every seat with `--plugin-dir <this checkout>/plugin`. Seats work in
the target project's folders, where this repository's own `.claude/` is never read, so this is how the
factory's skills reach them. Nothing is installed into your settings: a session the factory did not start
does not have the plugin. Its skills are namespaced by the plugin name and show as `/factory:<skill>`.

Its skills are procedures for a role (assigning an issue, for example), loaded only when used instead of
sitting in every prompt. The skill folders under [`plugin/skills/`](plugin/skills/) are the list, and each
skill's `description` says whom it is for and when to use it. `/factory:ping` only proves the plugin loaded.
Every seat loads every skill. A skill reaches its role through its description and through that role's
`skills:` in the team file (`teams/example.yaml` names each one where it belongs). A skill only the owner
may start sets `disable-model-invocation`. A skill is the procedure. The rules it applies (a brief's
template, the review bar) stay in the role prompt, which the skill points to rather than copies, and a
skill stops if the prompt lacks them. `test/e2e.sh` checks every skill's frontmatter, so adding one needs no
new test code.

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
- Claude Code's diff panel notice ("Resize your terminal to at least 110 columns to show the diff
  panel") in a pane of 13 rows or fewer, where it pushes the end of the input box off the screen.
  With 16 rows or more the notice is harmless and `say` delivers (at 14 or 15 only a one-line
  message fits). Widen the pane to 110 columns, give it 16 rows or more, or close the diff panel in
  the seat;
- a screen tmux cannot read.

Attach to the seat, deal with it, and send again. If the box does not show the message after the paste,
no Enter is sent and the text stays in the box, where it goes out with the next Enter; `say` says so.
A message taller than the box (up to 800 characters and 3 lines; a longer paste shows as a `[Pasted
text #N]` placeholder) scrolls it, so only the message's end is visible. `say` then sends it only when
the box is full (floor((pane rows - 10) / 2) rows, at least 3) and its visible text is the message's
last 40 or more characters. One gap remains: if someone starts typing in the moment between `say`'s
empty-box check and the paste, and the message scrolls that text out of view, it goes out with the
message.
The input box is recognised as Claude Code 2.1.316 draws it, so a CLI update that changes it makes `say`
refuse every seat until `factory.sh` is updated. A refused message is logged as NOT-DELIVERED. Messages
are labelled `[from <role>]`, and the owner's are `[from owner]`. The label is set by the sender (from
`TEAM_ROLE`, or `owner` when it is unset) and is not authenticated. When `TEAM_ROLE` is unset, `say`
run from inside a seat (found from the terminals of the processes that started it) is labelled with
that seat's role, never `[from owner]`; this stops a mislabel by accident, and the labels are still
not authenticated ([#29](../../issues/29)). When it cannot tell, `say` refuses rather than guess: when
`ps` cannot read its process or one of its ancestors, when tmux cannot list its panes, or when it runs inside a seat of another
team on the same tmux server (any session `up` started, which sets `TEAM_ROLE`). The check looks only at
the tmux server `say` addresses: a process is labelled `[from owner]` when it has no terminal at all, or
when its terminal is not a seat's pane on that server. So a seat on another tmux server is labelled
`[from owner]`, for example a seat that runs `test/live-env.sh run` to drive a throwaway team on a
private server. A background job that outlives the command that started it, or a command a seat runs in a new tmux
session, is not caught and is labelled `[from owner]` (the comment above `caller_seat` in `factory.sh` lists every
such way). A seat cannot `say` to itself. A `TEAM_ROLE` that is set must be one of the team's role
ids: `say` refuses any other value, and the reserved `owner` and `launcher`, sending no keys and
logging NOT-DELIVERED.

### The kickoff

`up` gives each seat its kickoff (`kickoff` in the team file, or a role's own) as its first message,
labelled `[from launcher]`. Seats know the owner's voice as input with no label, so without the label
a team file's kickoff would read as the owner typing, at every start, to anyone who can edit the team
file. The shared prompt (`roles/common.md`) tells seats a `[from launcher]` message is team
configuration: it can say how to start, but it is never an owner instruction or approval, and the
EM's prompt never takes one as a merge instruction. `check` shows each seat's kickoff with its label.
`say` never sends as `launcher` (it refuses `TEAM_ROLE=launcher`, and `launcher` is not a valid role
id), and a kickoff may not contain a `[from …]` label of its own. For the same reason `owner` is not a
valid role id either: a seat named `owner` would send `[from owner]`, the owner's own label. Like every label, it is not
authenticated (#29): it keeps the kickoff from looking like owner input, nothing more.

### The message log

`.state/<team>/messages.log` records every `say` with its delivery outcome, and every `SendMessage` a seat
sends (#39), through a hook in each seat's generated settings.

Each `say` (`say all` included) appends exactly one line of five tab-separated fields: the local time
(`2026-10-30T14:05:09`), the sender (`TEAM_ROLE`, the seat `say` ran inside, `owner`, or `?` when `TEAM_ROLE` is unset and
`say` refused because it could not tell whether it ran inside a seat), the recipient (a role id or `all`),
`delivered` or `NOT-DELIVERED`, and the message as typed, without its `[from <role>]` label. The
sender and the message are escaped so the record stays on one line and holds no terminal control
codes: a backslash is written `\\`, a newline `\n`, a carriage return `\r`, a tab `\t`. Every other C0
control (below U+0020), DEL, C1 control (U+0080 to U+009F) and bidi embedding, override or isolate
(U+202A to U+202E, U+2066 to U+2069) is written as its UTF-8 bytes, each as `\xHH` (two upper-case hex
digits): U+009B is `\xC2\x9B`. Other text, such as `é` or `✓`, is written as it is. A message that is
not valid UTF-8 has every byte from 0x80 up written as `\xHH`. If the escaping itself fails, the field
reads `<log_field failed>`. The escaping is reversible: `printf '%b' "<field>"` in bash gives back
the original text.

Each `SendMessage` from a seat appends one line in the same format, written by `lib/log_message.sh`, a
`PostToolUse` and `PostToolUseFailure` hook on `SendMessage` in every seat's settings:

- the sender is the seat's role id, and the message is the text it sent, escaped as above. A message
  that is not a string is written as its JSON text. A lone UTF-16 surrogate escape in the hook input
  (`\ud800` with no low half after it, or a low half alone), which Ruby's JSON parser refuses, is read
  as U+FFFD (`�`); a valid pair is kept;
- the recipient is a role id when the `to` names a roster seat's session (`sf-tl`, or `sf-tl [3fa9c1]`)
  or is a `uds:` address whose process runs in a roster seat's pane, as a reply to a message does.
  Anything else, another team's session, a subagent or an address no seat holds, is written as given;
- the outcome is `sent` when the message reached the receiver's inbox, and `NOT-SENT` when
  `SendMessage` returned `success: false` or failed. `sent` is not `delivered`: a receiver in another
  permission mode can still hold a message for its user's approval, or refuse it, and that comes back
  later as a notice to the sender, which the log does not see;
- hook input that still cannot be read is logged as a line with the recipient `?`, the outcome
  `UNREADABLE` and the message `<hook input could not be read>`, so a message is never left out of
  the log without a trace.

The hook prints nothing and always exits 0, so a log it cannot write costs that line, never the message
or the tool result. Looking up the seat behind a `uds:` address (with `ps` and `tmux`) gives up after
2 seconds, killing what it started, and the address is then written as given. The message is written to
`messages.log` only, which holds every native message in full, private reports to the EM among them:
every seat but `em` has a `Read` deny on it (see [Safety](#safety)). A seat whose hooks are all off
(`disableAllHooks: true` in the user's settings, and no gate) logs nothing: `check` says which.
Messages a seat receives are logged by their sender, so traffic from outside the team is not logged.

## Safety

Each seat starts with a generated settings file, `.state/<team>/settings/<role>.json`, passed with
`--settings` and rewritten read-only on every `up`. It holds the team's `permissions` merged with the
role's (team first; a role can add or tighten a rule, never loosen one), plus what factory.sh adds:

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
  this ask is redundant;
- an `Edit` allow on the seat's own progress note (see [Progress notes](#progress-notes)), which is
  outside its working directory and would otherwise prompt in a mode other than bypass, and an `Edit`
  deny on every other seat's note: a note is put into its seat's context at each start, so a seat
  that could write another's would have a lasting channel into it;
- a `Read` deny on the message log, `.state/<team>/messages.log` (both spellings, when a symlink makes
  them differ), for every seat but the role with id `em`: the log holds every `SendMessage` in full. A
  team with no `em` role has the deny on every seat. This is an accident guard, not a boundary: every
  seat runs as the same OS user (#29), and a command that reads the file some other way is not stopped.

`permission_mode` (in `sessions.claude`, or per role) picks the mode; the example uses `auto`.
`bypassPermissions` skips every prompt and is meant for an isolated machine only. Deny rules hold in
every mode, bypass included, and ask rules still prompt there, so a seat that hits one waits until
someone answers. `say` will not deliver to a seat at a permission prompt or any other dialog (see
[`say`](#say)): attach and answer it yourself. These rules add to the ones in `~/.claude/settings.json`
and the repo's `.claude/` settings, which still apply. `check` shows each seat's mode and rules, and is
where load-time errors (unknown modes, malformed rules, a permission flag in `args`) are reported.
It also warns, without stopping a start, about seats whose modes would hold messages between them
([Which messages are held](#which-messages-are-held)), and about any role whose rules have neither a
deny nor an ask on each of the merge patterns, unless that role is marked `may_merge: true` (a YAML
boolean, so an unquoted `yes` or `on` also counts as true). The patterns, the ones `teams/example.yaml`
denies or asks on ([#85](../../issues/85)):

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
the main checkout's path ([#108](../../issues/108)). Claude Code names the folder after that path, with
every non-alphanumeric character turned into `-`; a name over 200 characters is matched by its first
200 and a `*`, because Claude Code appends a hash to it. As with the other denies, Bash redirects, `tee`
and `cp` into the folder are stopped too, and a script that opens the file itself is not (checked on
Claude Code 2.1.314). `check` names the deny in each seat's `added:` line. The deny covers only that
default folder: if you set `autoMemoryDirectory` in your settings, your sessions load memory from the
folder it names, and the deny keeps protecting a folder nobody reads, with no warning.

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
- Claude Code matches permission rules against each part of a compound command (`;`, `&&`, `|`), but
  against the whole command text when it can't parse the command (for example `"$(...)"` in an
  argument, or `${...}` next to quotes). In default mode, a subshell `( ... )` or a command it can't
  parse prompts even when no rule matches (the reason varies: "can't be checked before it runs",
  "shell operators that require approval"); in bypass mode it prompts only when a rule matches
  (measured on 2.1.316, [#103](../../issues/103); other modes not measured). So seats run `git push`
  as its own simple command: chained with an unparseable part, a `main` elsewhere in the command makes
  it match the base-branch ask.

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
  the turn normally. Committed work is gated again when the reviewer runs the gate on the PR. A
  `git status` that fails (a corrupt index, say) counts as uncommitted work: the gate runs, and a
  send-back says status failed. The hook's git calls do not run a repository's fsmonitor program;
  clean filters stay on, because status needs them for a correct answer ([#104](../../issues/104)).
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

## Progress notes

Each seat keeps a short progress note, `.state/<team>/notes/<role>.md`: its current task, branch,
state, next step and what it is waiting for. The shared prompt tells it to rewrite the note whenever
a task changes state and to work on one task at a time. The note is outside the worktree, so it
survives `down` and `up` and a recreated worktree; `up` only makes the folder, and nothing removes a
note.

Every seat's generated settings have a `SessionStart` hook (`lib/session_start.sh`, no matcher, so
it runs at startup, on resume, after `/clear` and after a compaction). It prints the note (cut at 80
lines or 6000 bytes), the branch, uncommitted files and the last 10 commits of the seat's working
directory, and Claude Code adds that to the seat's context. The default kickoff asks a seat to name
the note's task and next step in its first reply. The note is the seat's own writing, so treat it as
a reminder, not a record: when it and the repository disagree, the repository wins.

- Control characters other than tab and newline (and DEL) are dropped from everything the hook
  prints, so a terminal escape in a note or a commit subject arrives as plain text.
- `git status` and `git log` each have their own time limit (4s and 3s), well inside the hook's 10s,
  and a repository's fsmonitor program is not run. Claude Code drops all of a hook's output when the
  hook runs past its timeout, so a slow status on a cold volume costs the seat its file list, not its
  note.
- Each seat may edit only its own note: the others are denied (see [Safety](#safety)).
- The hook is a convenience, not a control, so it does not override a user who switched every hook
  off: with `disableAllHooks: true` in `~/.claude/settings.json`, a seat without a gate gets no note,
  and `check` prints a `hooks` line naming those seats.

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
test/live-env.sh run "$d" tmux ls                          any command, with TMUX_TMPDIR=$d/tmux and
                                                           TEAM_STATE_DIR=$d/state (absolute), TEAM_VIEW=0,
                                                           and TMUX and a seat's TEAM_CONFIG, TEAM_ROLE and
                                                           TEAM_SCRIPT unset (so factory.sh without -c never
                                                           finds the seat's real team)
test/live-env.sh down "$d"                                 stop its tmux server, remove the folder
```

Each call checks the folder on its own (made by `new`, its tmux folder not `/tmp`), so it works from a fresh
shell each time. Setting `TMUX_TMPDIR` by hand is easy to get wrong: tmux 3.7 follows `$TMUX` when it is set,
and falls back to the default server, silently, when `TMUX_TMPDIR` is empty or names a folder that does not
exist. A throwaway team's worktrees on the volume are not removed by `down`; remove them by their paths.

`TEST_VOLUME=/Volumes/YourDrive test/e2e.sh` runs the launcher against a throwaway repo with a stand-in
`claude` on a private tmux server. It covers worktree placement on the volume, per-role model and
effort (and the example team's effort per role), message delivery, migrating a legacy worktree (clean and dirty), and refusing to run when the
volume is not mounted. It also covers the generated settings files (merged rules, protected paths,
base-branch rules, permission mode and launch flags), the factory plugin (its manifest, `--plugin-dir`
with the plugin's real path, `sessions.claude.plugin: false`, a bad value, a missing manifest, a team's
own `--plugin-dir` in `args`), the kickoff's `[from launcher]` label (in the rendered file, as the seat
receives it, in `check`, `say` refusing to send as `launcher`, a kickoff with a label of its own, a role
named `launcher` or `owner`), the load-time checks on modes, rules and `args`,
`say` delivering only to a seat whose input box is showing (dialogs captured from Claude Code
2.1.316, an unknown dialog, text in the box, copy mode, an unreadable screen), and the gate: the
generated Stop hook, its load-time checks, and `lib/stop_gate.sh` itself (clean tree, failure, the
limit, a new turn or session, a pass, a timeout that kills the gate's process group), progress notes
(the `SessionStart` hook in every seat, `disableAllHooks` only where gated, the own-note allow and
the other-note denies, `check`'s hooks line, a note surviving `down` and `up`, and
`lib/session_start.sh` itself: no note, a note, a detached HEAD, no repository, a missing folder, a
long note, a non-UTF-8 note under `LC_ALL=C`, control characters, a hanging `git status`), and the
auto-updater being off in every seat and nowhere else, and the seats' own copy of claude (made by
`up`, never the shared file; still intact after the shared file is replaced; `REPLACED` when its own
file is swapped; a copy that cannot be made, or a shared install caught mid-reinstall, stops the
start). It also covers `up` refusing a throwaway team on the default tmux server (TMUX and TMUX_TMPDIR
unset, `/tmp` by two spellings, an empty or missing TMUX_TMPDIR, a relative one under CDPATH, TMUX naming
the default socket) before any tmux call, going ahead on a private server, for a team file in `teams/` and
with `--default-socket`; `down`, `down --yes`, `say`, `attach` and `view` refusing a copy of a running
team's file there before any tmux call, with the seats left as they were (a stand-in tmux passes every call
to the test's private server), and going ahead for a file in `teams/` or with `--default-socket`; and
`test/live-env.sh` (its environment, with a seat's TEAM_CONFIG, TEAM_ROLE and
TEAM_SCRIPT unset and the folders resolved, its private socket, and refusing a missing folder, one `new`
did not make, one whose tmux folder resolves to `/tmp`, and one whose socket folder or socket is a link).

The exit code is authoritative: `test/e2e.sh` exits 0 only when it reaches the end with every
assertion passed (`RESULT pass=<n> fail=0`), and non-zero when any assertion fails or the run stops
early (a setup error, a signal). A run that stops early still removes what it made and says
`ABORTED` on stderr. That makes it safe as a `repo.gate` command, which is judged by its exit code.
