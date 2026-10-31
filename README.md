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
  `~/.claude/settings.json`.
- `permissions` (`deny`, `ask`, `allow`), at the top level and per role: see [Safety](#safety).
- `prompts.common` and a per-role `prompt` (file) or `prompt_text` (inline). Placeholders such as
  `@@ROSTER@@`, `@@GITHUB_REPO@@`, `@@PROJECT_URL@@` and `@@WORKTREE_ROOT@@` are filled in per seat.
- `roles`: ordered; each has `title`, `workdir` (`project` folder or `worktree`), a prompt, and
  optional `model`, `effort`, `session`, `kickoff`, `summary`.

Unknown keys, missing prompt files, duplicate session names and unknown placeholders are errors at load
time, before anything starts.

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
| Seat to seat, different classes (a role with its own `permission_mode`) | Held. An approval dialog opens in the receiver's pane, and if nobody answers it the message is dropped after `dialogExpiry` (5 minutes by default). In an unattended team, that means it is lost. `check` does not warn about this yet (#36). |
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
`TEAM_ROLE`, or `owner` when it is unset) and is not authenticated.

### The message log

`.state/<team>/messages.log` records every `say` with its delivery outcome. Until #39 lands (a hook that
logs `SendMessage` too), it records `say` traffic only: read `SendMessage` traffic in each session's
transcript (`ctrl+o` in an attached seat).

## Safety

Each seat starts with a generated settings file, `.state/<team>/settings/<role>.json`, passed with
`--settings` and rewritten read-only on every `up`. It holds the team's `permissions` merged with the
role's (team first; a role can add or tighten a rule, never loosen one), plus two sets factory.sh adds:

- an `Edit` deny on the files that would change a seat's next start or its live rules: the generated
  settings, launchers and prompts, the message log, the team file and its prompts, the launcher
  (`factory.sh`, `lib/`, `roles/`) and the claude `wrapper` (its whole `.app` bundle, if it is in
  one), the main checkout's `.claude/settings.json`, `settings.local.json`, `skills/`, `agents/` and
  `commands/`, the seat's own `.claude/settings.json` and `settings.local.json`, and Claude Code's user
  settings, MCP config, instructions and extensions under `~/.claude`. `.claude/worktrees/` stays
  editable: Claude Code puts the worktrees it makes there, including those of a worktree seat's
  subagents, which land under the main checkout;
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
  settings); #29 tracks the fix.
- Settings above these files apply as well: managed settings, and, depending on the account, installed
  mods, which can approve calls these rules would stop.
- Paths in Read and Edit rules: `//path` is absolute, `~/path` is under the home folder, `./path` or a
  bare name is relative to the seat's folder. A single leading `/` anchors at the folder that holds the
  generated file, so it is refused.

The [sandbox](https://code.claude.com/docs/en/sandboxing) is the boundary that holds whatever the
command text. The hard rules in the shared prompt (`roles/common.md`) still apply; read them before
changing them. A seat started in a folder Claude Code has not seen stops at a trust dialog until a
human answers it once; `up` reports which seats those are.

## The gate

`repo.gate` is the repository's pass/fail command. A role with `gate_on_stop: true` gets a Stop hook in
its generated settings (`lib/stop_gate.sh`): whenever the seat ends a turn with uncommitted changes in
its working tree, the hook runs the gate there, and if it fails the seat is sent back to work with the
command, the last 60 lines of its output and the path of the full log (`.state/<team>/gate/<role>.log`).
Roles without the switch never run it. The example gives it to the engineers and qa.

- Only uncommitted work is gated at a stop: a clean tree, including committed but unpushed work, ends
  the turn normally. Committed work is gated again when the reviewer runs the gate on the PR.
- A seat also stops on purpose: to wait for an answer or a review, or with a test red before the fix.
  After `repo.gate_max_blocks` (default 3) failed gates in a row in one session, the stop goes through
  with a note that the gate is still failing, and the seat is told to say so in its report. The count
  is in the state folder, which seats cannot edit, and a passing gate or a clean tree resets it. Claude
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

## Tests

`TEST_VOLUME=/Volumes/YourDrive test/e2e.sh` runs the launcher against a throwaway repo with a stand-in
`claude` on a private tmux server. It covers worktree placement on the volume, per-role model and
effort, message delivery, migrating a legacy worktree (clean and dirty), and refusing to run when the
volume is not mounted. It also covers the generated settings files (merged rules, protected paths,
base-branch rules, permission mode and launch flags), the load-time checks on modes, rules and `args`,
`say` delivering only to a seat whose input box is showing (dialogs captured from Claude Code
2.1.316, an unknown dialog, text in the box, copy mode, an unreadable screen), and the gate: the
generated Stop hook, its load-time checks, and `lib/stop_gate.sh` itself (clean tree, failure, the
limit, a new turn or session, a pass, a timeout that kills the gate's process group).
