# fabrikito

**A team of Claude Code sessions for one software project: roles, review and guardrails, started from one
file.**

One Claude Code session does a lot, but a project has more than one job. Someone plans and assigns, someone
writes the change, someone reviews it with fresh eyes, someone tests it, someone looks at security. Run
those by hand as separate sessions and you juggle terminals, checkouts, prompts and permissions, and
nothing keeps two sessions out of each other's files or stops one from pushing straight to the base branch.

`fabrikito` sets that up from one YAML file. Each role becomes a persistent Claude Code session in a tmux
session of its own, in a git worktree of its own, told what its role is and who else is on the team. The
seats message each other, and one iTerm tab shows them all.

## What makes it different

- **A team is one file.** Roles, prompts, models, effort, permissions and where each seat works are keys in
  a team file. `check` validates the whole file before anything starts: unknown keys, missing prompt files
  and duplicate session names are errors, so a typo cannot silently fall back to a default. Every key is
  documented in [`teams/example.yaml`](teams/example.yaml).
- **The roles come with a working process.** The repository ships prompts for an engineering manager, a
  tech lead, engineers, QA and security (`roles/`), a set of rules every seat shares (`roles/common.md`:
  no change without an issue, one task at a time, report what you observed, never merge), and skills for
  the steps of the process: assigning an issue, starting a task, reviewing a PR at its exact head,
  verifying behavior, triaging a security point ([the plugin](docs/plugin.md)).
- **Seats are isolated and persistent.** A seat can have a git worktree of its own, created detached at your
  base ref (the example gives one to every seat but the manager), so engineers do not overwrite each
  other's files. Each runs in its own tmux session, so closing the iTerm tab only detaches; `down` is
  what stops a seat, and it keeps the worktree.
- **Seats talk, and the talk is on record.** Seats message each other by session name with Claude Code's
  own cross-session messaging. Every message a seat sends, and every message you send with `say`, is
  appended to a log, `.state/<team>/messages.log`.
- **Guardrails are generated, not hoped for.** Every `up` writes each seat a settings file with deny rules
  on the files that would change its own rules, and an ask on any push to the base branch. The example
  team also denies `gh pr merge` to every role but the manager, whose rule is an ask. `check` lists what
  each seat gets and warns about a role left open to a merge.
- **A seat can be held to your checks.** With `gate_on_stop`, a seat that stops with uncommitted work is
  sent back to work while the repository's own gate fails ([The gate](docs/gate.md)).
- **Few moving parts.** There is no server and no background service:
  `fabrikito` is a bash script that uses the system `ruby` (no gems) to read the YAML, tmux keeps the seats
  running, and everything generated sits in a git-ignored state folder you can read. Nothing is
  installed into your own Claude Code settings. See [How it works](docs/how-it-works.md).
- **Straight about its limits.** The rules guard against accidents. Every seat runs as your OS user with
  your GitHub credential, and a rule matches command text, so they are not a security boundary.
  [Safety](docs/safety.md) says what each rule covers and what it does not.

## What using it looks like

You write a team file for your project and run `./fabrikito up`. A new iTerm tab opens with the manager's
seat on the left at full height, since it is the one you talk to, and the other seats in rows beside it.
You tell the manager what you want. It turns the request into issues with acceptance criteria and hands
each to a seat as a written brief. The engineers work in their own worktrees and open pull requests, the
tech lead reviews them, QA checks the behavior, and the security seat looks at what is sensitive. You read
the summaries the manager gives you and merge. You can type into any seat, from the tab or with
`./fabrikito say <role> "..."`, and you can start only the seats a task needs, to keep the cost down
([Right-sizing a team](docs/right-sizing.md)).

## The workflow

The prompts and skills lay out one path for a change. The team file decides which roles exist, and you
can change any prompt.

1. **Issue.** No change starts without a GitHub issue; the manager files one when it is missing. This is a
   rule in the shared prompt, not something the launcher enforces ([How work is tracked](docs/workflow.md)).
2. **Assignment.** The manager assigns one issue to one seat as a brief: issue, objective, deliverable and
   definition of done, branch, tools, boundaries and reviewers.
3. **Pull request.** The engineer works on a branch in its worktree, runs the whole gate, and opens a PR
   with `Closes #<n>`. A seat held by `gate_on_stop` is also stopped at the gate.
4. **Review.** The tech lead reviews every PR against its issue and gives one verdict at an exact commit,
   `READY at <sha>` or `CHANGES NEEDED`.
5. **Verification.** QA runs the behavior in a throwaway environment and reports pass, fail or could not
   check, with evidence. The security seat reviews what is security-sensitive. A security point found in a
   review is sent privately to the security seat, and the PR gets a marker that the merge procedure
   treats as a hold until that seat clears it.
6. **Your merge.** The owner merges. The manager merges only a PR the owner told it to, and the
   `merge-train` skill that does it can be started only by the owner typing it in the manager's pane.

## The safety model

- Seat settings are generated at every `up` and passed to Claude Code with `--settings`. A role can add or
  tighten a rule and never loosen one.
- Protected files (the team file, prompts, launcher, plugin, generated state, Claude Code's own settings)
  are Edit-denied, and a seat may edit only its own progress note.
- When other teams run on the machine, their state is denied to every seat, and the message log is denied to every
  seat but the manager.
- Messages and their `[from <role>]` labels are claims, not identities. The prompt tells seats to act only
  on messages from roster names, and a kickoff is labelled `[from launcher]` so it never reads as you
  typing.
- Seats work in worktrees, and the throwaway-team rule keeps tests off the tmux server a real team runs on.
- Under all of it: these are accident guards. The page [Safety](docs/safety.md) lists what is covered and
  what is not, and [How it works](docs/how-it-works.md#what-the-rules-are-and-are-not) says why.

## Quick start

**You need** macOS, `tmux`, `claude` (Claude Code), `git` 2.36 or later, `gh` and the system `ruby`, iTerm2
for `view`, and a mounted volume for the seats' worktrees (the launcher never falls back to another disk).
See [Requirements](docs/commands.md#requirements).

```
git clone https://github.com/bgoleno/fabrikito.git
cd fabrikito
cp teams/example.yaml teams/team.yaml     # edit it: repo.path, repo.github, storage, project, the roles
./fabrikito check                        # validate the team file and show where everything lives
./fabrikito up                           # start the team (and open the iTerm tab)
./fabrikito view                         # open the iTerm tab again, any time
./fabrikito say em "What is the plan for today?"
./fabrikito down --yes                   # stop the seats (worktrees are kept)
```

Run `check` first and read what it prints. `up` also needs the main checkout's `origin` to name
`repo.github`. Your own team files in `teams/`, and anything under `projects/`, are git-ignored, so a
project's specifics stay out of this repository. To try a team without touching the one you work with,
see [Testing](docs/testing.md#live-tests) and [Throwaway teams](docs/commands.md#throwaway-teams).

## Documentation

The reference lives in [`docs/`](docs/README.md). Start with [How it works](docs/how-it-works.md), then:

| Read | To |
|---|---|
| [Commands](docs/commands.md) | Install and run a team: every command and option, which team file is used, the iTerm view. |
| [The team file](docs/team-file.md) | Set up a team: what each part does, what is checked, how a new worktree is prepared. |
| [Right-sizing a team](docs/right-sizing.md) | Choose the number of seats, effort and model per seat, and see the cost. |
| [How work is tracked](docs/workflow.md) | The issues-first rule, progress notes and held security points. |
| [The gate](docs/gate.md) | How a seat is held to the repository's checks, and one heavy run at a time. |
| [Safety](docs/safety.md) | What the permission rules cover, and what they cannot do. |
| [The fabrikito plugin](docs/plugin.md) | How fabrikito's skills reach every seat. |
| [Pinned releases](docs/pinned-release.md) | Run a team from a checkout fixed at a release. |
| [Updating Claude Code](docs/updating-claude-code.md) | Update Claude Code on a running team. |
| [Testing](docs/testing.md) | A live test on a private tmux server, and the end-to-end test. |
| [Troubleshooting](docs/troubleshooting.md) | Find what you see (an error, a refused message, a silent seat) and what to do. |

Messaging (how seats talk, `say`, the message log) is documented at the end of this file for now.

## Reporting a vulnerability

Report a vulnerability through GitHub's private vulnerability reporting:
<https://github.com/bgoleno/fabrikito/security/advisories/new>. Do not open a public issue for it.
See [SECURITY.md](SECURITY.md).

## Contributing

Every change starts as a GitHub issue, and its pull request links the issue and fills in the pull request
template. Nothing tracked may name a specific project, person, drive or path. Before a pull request, run
the gate: `bash -n fabrikito factory.sh test/e2e.sh lib/stop_gate.sh lib/session_start.sh lib/log_message.sh`,
`ruby -c lib/team_config.rb`, and `env -u TMUX TEST_VOLUME=/Volumes/<a mounted, writable volume> test/e2e.sh`.
See [Testing](docs/testing.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).

The `security-audit` plugin skill is a modified copy of Cloudflare's
[security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Messaging

The sections below hold the reference for messaging. They are moving to a page under `docs/`; Safety and
Updating Claude Code have already moved.

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
pane (see [Safety](docs/safety.md)).

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
message. The `[from <role>]` label goes in as a paste of its own, before the message
([#150](../../issues/150)). Claude Code hands a long paste, one it shows as `[Pasted text #N]`, to the
seat inside `<pasted_content>` tags, and seats doubted a label inside them. A paste as short as the
label stays plain text, outside the tags. `say` pastes the message only once the box holds just the
label, so a message never goes in without it. Anything else fails closed, with a reason:

- a seat that is not running claude (the text would run as a shell command);
- any dialog, prompt or menu, known or not, the held-message approval dialog included ("screen not
  recognised as ready"), where the Enter would pick an answer;
- an input box that already holds text (someone typing, or an earlier message that was not sent): see
  "A box that holds text" below for the back-off, the notice in `status` and `flush`;
- a pane in copy mode (someone scrolling);
- Claude Code's diff panel notice ("Resize your terminal to at least 110 columns to show the diff
  panel") in a pane of 13 rows or fewer, where it pushes the end of the input box off the screen.
  `say` grows such a pane and checks again (below), so this shows only if that fails. With 16 rows
  or more the notice is harmless (at 14 or 15 only a one-line message fits). Widen the pane to 110
  columns, give it 16 rows or more, or close the diff panel in the seat;
- a screen tmux cannot read;
- another `say` typing into the same seat that has not finished within 8 seconds. One `say` at a time
  types into a seat (an `flock` on `.state/<team>/say/<role>.lock`, released when that `say` exits,
  however it ends), so two messages never mix in one box. Anything other than a plain file at that
  path (a FIFO, a symlink) is refused at once: remove it.

Attach to the seat, deal with it, and send again. After the paste, `say` sends Enter only when the box
holds the message and nothing else: the whole message (whitespace aside, since the box wraps it), its
label and one placeholder, or the end of a message taller than the box (below). If it does not, if
the box does not hold just the label after the label's paste (then the message is not pasted at all),
or if the message's paste fails after its label's, no Enter is sent and
the text stays in the box, where it goes out with the next Enter; `say` says so, and says why: the
screen no longer ends with the box, dim text was drawn next to the message, the box shows fewer rows
than it can and not just the message (as when someone typed after it), too little of the message's
end is visible (under 40 characters, as with short last lines in a narrow pane), or the box does not
end with the message.

**A box that holds text ([#212](../../issues/212)).** A box that is not empty blocks every later
message to that seat, and senders used to retry in a loop. Now:

- the refusal is also written to `.state/<team>/say-refusals.log`, one line of time, sender, receiver
  and class (`box-text`, or `box-text-repeat` below), with no message and no hash;
- the same text from the same sender to the same seat, refused for its box and sent again within 300
  seconds while the box still holds text, is refused as a repeat, with a message that says to stop
  resending it and not to loop. Only a refusal for a box that holds text counts: a dialog, copy mode,
  a shell or a busy seat do not, and a different text is refused for the box as before. The window is
  kept per text (the last eight refused texts of each seat), so another sender's refusal in between, or
  alternating two texts, does not hide a repeat. A message to or from `sec` is never hashed, so it is
  refused for the box each time and not as a repeat. The `FACTORY_SAY_RESEND_WINDOW` environment variable
  changes the 300 seconds (a value that is not a whole number means the default);
- `status` prints one `NOTICE <role>` line for a seat once three sends to it were refused for its box
  (`FACTORY_SAY_NOTICE_COUNT`), however many more are refused. It says when the last refusal was: only a
  later `say` clears it, and `status` does not read the pane. Nothing is typed into any seat by it;
- the records of that seat (what `say` keeps for the two points above, mode 600 files in
  `.state/<team>/say/`, the hash of the text among them) are removed the moment its box is seen empty,
  or a delivery or a `flush` succeeds, so the resend after the remedy is not held back for the rest of
  the window.

Recovery for text `say` itself left in a box (a label, or the start of a message whose paste did not
finish) is `./fabrikito flush <role>`. It deletes nothing and sends no key but one Enter, so the
fragment goes to the seat as a turn and the sender is told to resend: `say` writes what it is about to
paste into `.state/<team>/say/paste-<role>` and removes it after the Enter, so a crash or a partial
paste leaves it. `flush` submits only when the box, with white space left out, is a non-empty start of
that record, or the record's label and one `[Pasted text #N]` placeholder. A message to or from `sec`
keeps only its label in the record (no body of it is kept, [#227](../../issues/227)), so only a
label left alone is matched there. Anything else is refused and left as it is: text someone typed is
never cleared or submitted. `flush` runs the same pane checks as `say` (a seat at a shell or a dialog is
refused), reads the box again right before the Enter and refuses if it changed, and sends one Enter, with
no retry. It writes one line to `messages.log` from the caller, with the status `FLUSHED`, `NOT-FLUSHED`
or `FLUSH-NOTHING` and the fixed message `[flush]`, never the box's text. Nothing here lets a seat edit
another seat's box by hand; the owner can still attach and clear text they find.

**Short panes ([#84](../../issues/84)).** A seat's pane takes the size of the iTerm pane attached to
it, and the team view makes them small: 89x13 with ten seats on a 77-row display, about 10 rows with
twelve. Under 110 columns a seat whose diff panel is open draws the notice above its box, which at 13
rows or fewer pushes the box off the screen; under 12 rows a paste grows the box past the bottom, and
even a multi-line paste collapses to a placeholder (all measured on 2.1.316). Most messages still fit,
so `say` runs its checks at the pane's own size. Only when one refuses (before the paste, or after it,
with the text already in the box) in a window under 110 columns or under 12 rows does `say` grow the
window to 220x50 (the size seats run at detached, where the checks above were measured and verified
live), run that check again there, and go on only if it passes; then it puts back exactly the size and
the window's `window-size` option it found. A window is grown at most once per message, and a window of
110x12 or more is never resized. So the view flashes only for a `say` that would otherwise be refused:
while the window is grown, the seat's pane shows a clipped part of the bigger window and Claude Code
redraws twice, for about a second. The traps put the window back however `say` ends, except SIGKILL;
a `say` killed that way can leave the window at 220x50 with `window-size` set to `manual`, and
`tmux set-option -w -u -t '=<session>:' window-size` puts it back to following the iTerm pane.
A message taller than the box (up to 800 characters and 3 lines, not counting its label; a longer
paste shows as a `[Pasted text #N]` placeholder) scrolls it, so only the message's end is visible. `say` then sends it only when
the box is full (floor((pane rows - 10) / 2) rows, at least 3) and its visible text is the message's
last 40 or more characters. Its label has scrolled out of view by then, which is why `say` checks the
label alone, before it pastes the message. Two gaps remain: if someone starts typing in the moment
between `say`'s empty-box check and the paste, and the message scrolls that text out of view, it goes
out with the message; and if the label is cleared from the box (Ctrl-C, Esc) in the moment between
`say`'s check of it and the message's paste, the message goes out without it.
The input box is recognised as Claude Code 2.1.316 draws it, so a CLI update that changes it makes `say`
refuse every seat until `fabrikito` is updated. A refused message is logged as NOT-DELIVERED. Messages
are labelled `[from <role>]`, and the owner's are `[from owner]`. The label is set by the sender (from
`TEAM_ROLE`, or `owner` when it is unset) and is not authenticated. When `TEAM_ROLE` is unset, `say`
run from inside a seat (found from the terminals of the processes that started it) is labelled with
that seat's role, never `[from owner]`; this stops a mislabel by accident, and the labels are still
not authenticated ([#29](../../issues/29)). When it cannot tell, `say` refuses rather than guess: when
`ps` cannot read its process or one of its ancestors, when its walk up them stops at 100 processes
before pid 1 ([#130](../../issues/130)), when tmux cannot list its panes, when it runs
inside a seat of another team on the same tmux server (any session `up` started, which sets
`TEAM_ROLE`), or when a tmux server other than the one `say` addresses is among its ancestors. The last
is a pane of another server, whose seats `say` cannot see ([#115](../../issues/115)). It refuses a seat of
any team on any other server, and the owner's own pane on such a server too. From a terminal outside tmux
the owner is still `[from owner]` (`TEAM_ROLE=owner` is refused). A background job that outlives the
command that started it, or a command a seat runs in a new tmux session on the server `say` addresses, is
not caught and is labelled `[from owner]` (the comment above `caller_seat` in `fabrikito` lists every such
way). A seat cannot `say` to itself. A `TEAM_ROLE` that is set must be one of the team's role ids, or
`live-test`: `say` refuses any other value, and the reserved `owner` and `launcher`, sending no keys and
logging NOT-DELIVERED. It refuses an empty or whitespace-only message the same way, before any tmux
command, for one seat and for `all` ([#157](../../issues/157)); with `TEAM_ROLE` unset, that refusal is
logged under the sender `?`.

`live-test` is the driver label. `test/live-env.sh run` sets `TEAM_ROLE=live-test`, so a live test that a
seat drives sends as `[from live-test]`, never as `[from owner]`. No role id can be `live-test`, since role
ids hold no hyphen. `say` refuses it when it addresses the default tmux server, where the real team runs,
even with `--default-socket`.
It works that out from `TMUX` and `TMUX_TMPDIR`, before any tmux command. The limit: a real team the owner
runs on a tmux server other than the default one is not told apart from a test team, and can receive
`[from live-test]`.

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
(`2026-10-30T14:05:09`), the sender (`TEAM_ROLE`, which is a role id or `live-test`; the seat `say` ran inside; `owner`; or `?` when `TEAM_ROLE` is unset and
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

`say` writes this line before it prints anything about the delivery, such as why a message was not
delivered (#128). A write to a terminal or a pipe can fail (with EINTR under heavy load, into a closed
stderr, or into a pipe whose reader has gone), and the failure ends `say`; written first, the record is
kept all the same. If the line itself cannot be appended, `say` still prints its reason, then says the
record could not be written and whether the message was delivered (so that a delivered message is not
sent again), and exits with status 1.

The log is never written through a link ([#194](../../issues/194)). When `messages.log` is a symlink, a
FIFO or a hard link (a file with a second name), `say` delivers nothing and writes no line: it prints
why, says the record could not be written, and exits with status 1. Only a seat could put one there;
do not delete the file (it may be the real one, with a second name made elsewhere): remove the other
name, or move this file aside. `lib/log_message.sh` (below) opens the log without following a symlink and
writes only to a regular file with one link, so there it costs that line.

Each `SendMessage` from a seat appends one line in the same format, written by `lib/log_message.sh`, a
`PostToolUse` and `PostToolUseFailure` hook on `SendMessage` in every seat's settings:

- the sender is the seat's role id, and the message is the text it sent, escaped as above. A message
  that is not a string is written as its JSON text. A lone UTF-16 surrogate escape in the hook input
  (`\ud800` with no low half after it, or a low half alone), which Ruby's JSON parser refuses, is read
  as U+FFFD (`�`); a valid pair is kept;
- the recipient is a role id when the `to` names a roster seat's session (`sf-tl`, or `sf-tl [3fa9c1]`)
  or is a `uds:` address whose process runs in a roster seat's pane, as a reply to a message does.
  Anything else, another team's session or a subagent, is written as given, and so is its message; an
  address no seat holds is written as given too, but without its message (below, [#227](../../issues/227));
- the outcome is `sent` when the message reached the receiver's inbox, and `NOT-SENT` when
  `SendMessage` returned `success: false` or failed. `sent` is not `delivered`: a receiver in another
  permission mode can still hold a message for its user's approval, or refuse it, and that comes back
  later as a notice to the sender, which the log does not see;
- a call with `notify_when_idle` and no message (or an empty one) sends nothing: it asks to be told when
  the receiver is idle. It is logged with the outcome `NOTIFY-WHEN-IDLE` and the message
  `<no message: notify when idle>` (`NOT-SENT` if the call failed), not as an empty message sent
  ([#247](../../issues/247));
- hook input that still cannot be read is logged as a line with the recipient `?`, the outcome
  `UNREADABLE` and the message `<hook input could not be read>`, so a message is never left out of
  the log without a trace.

The hook prints nothing and always exits 0, so a log it cannot write costs that line, never the message
or the tool result. Looking up the seat behind a `uds:` address (with `ps` and `tmux`) gives up after
2 seconds, killing what it started, and the address is then written as given. The message is written to
`messages.log` only, which holds every native message in full, private reports to the EM among them,
except a message to or from `sec` (below): every seat but `em` has a `Read` deny on it (see
[Safety](docs/safety.md)). A seat whose hooks are all off
(`disableAllHooks: true` in the user's settings, and no gate) logs nothing: `check` says which.
A message to or from `sec` is logged without its body ([#227](../../issues/227)): by `say` and by the
hook alike, the line keeps the time, the sender, the recipient and the outcome, and the text is replaced
by `[body not logged: sec]`. The hook is also closed on a doubt: a message to a `uds:` address that did not
resolve to a roster seat (the 2-second lookup ran out, or the sender is outside a roster pane) may be a reply
to `sec`, so its text is replaced by `[body not logged: unresolved address]`, and the other fields are as
usual. A security point can sit in such a message before it is rated, and
the log is read by more seats than `sec` and the EM (an observer's team, anyone who copies it). The
delivery checks read only the outcome, so they work as before. A `say all` from another seat is a message
to every seat, `sec` among them, and is logged in full, as the text is that seat's; send a private point to
`sec` by name. The seat id is `sec`, the one `lib/team_config.rb` calls `TRIAGE_WRITER`.
Messages a seat receives are logged by their sender, so traffic from outside the team is not logged.

## Safety

This section moved to [Safety](docs/safety.md): the rules generated into each seat's settings, how auto
memory is handled, and what the rules cannot do.

## Updating Claude Code

This section moved to [Updating Claude Code](docs/updating-claude-code.md): why an update needs care on
a running team, the team's own copy of claude that each seat runs, how to update, and how to remove old
copies.
