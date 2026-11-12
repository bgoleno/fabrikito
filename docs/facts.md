# Project facts

A short page of checked statements about fabrikito, for someone who describes the project elsewhere (a
site, a talk, an article). Each statement names the page or the code it rests on. If you need a claim
that is not here, check it there first, and leave it out if you cannot find it.

## What it is

fabrikito is a launcher that starts a team of Claude Code sessions on one project from one YAML team
file: each role runs as a persistent tmux session, in a git worktree of its own, told its role and able
to message the other seats. It is a bash script with no server and no background service: tmux keeps
the seats running, and Claude Code's own cross-session messaging carries their messages.

Source: [How it works](how-it-works.md), first paragraph; the [README](../README.md), introduction.

## What it does today

| It does this | Source |
|---|---|
| Validates the whole team file before any command that uses it acts (`run-exclusive` reads no team file), and `check` shows where everything lives. | [What `up` does](how-it-works.md#what-up-does); [Checked at load time](team-file.md#checked-at-load-time) |
| Starts each role as a tmux session running `claude`, in file order, and skips a seat that is already running. | [What `up` does](how-it-works.md#what-up-does), step 4 |
| Gives a `worktree` seat its own git worktree on the storage volume you name, and can copy files into a new one and run an install command there. An existing worktree is never reset. | [New worktrees](team-file.md#new-worktrees) |
| Generates, for each seat, a prompt (shared rules, role prompt, roster), a read-only settings file and a launch script. | [What a seat is made of](how-it-works.md#what-a-seat-is-made-of) |
| Writes permission rules into each seat's settings: denies on the files that would change a seat's own rules, a deny on a typed `tmux kill-server` or `tmux kill-session`, and an ask on a push to the base branch. | [Safety](safety.md), first list |
| Lets seats message each other by session name with Claude Code's `SendMessage`, and lets you (or a script) type a message into a seat with `say`. | [How seats talk](how-it-works.md#how-seats-talk) |
| Records every `say` and every `SendMessage` a seat sends in one message log per team. The text of a message to or from the security seat (`sec`) is left out. | [The message log](messaging.md#the-message-log) |
| Shows each seat its own progress note, branch, uncommitted files and last commits at every start and after every compaction. | [Progress notes](workflow.md#progress-notes) |
| Holds a seat with `gate_on_stop` to the repository's pass/fail command when it ends a turn with uncommitted work. | [The gate](gate.md) |
| Runs one heavy command at a time across every team on the host, in arrival order (`run-exclusive`). | [One heavy run at a time](gate.md#one-heavy-run-at-a-time) |
| Loads a plugin of skills into every seat: procedures such as assigning an issue, starting a task, reviewing a pull request, verifying behaviour and merging a reviewed stack. | [The fabrikito plugin](plugin.md); the folders under `plugin/skills/` |
| Runs every seat on the team's own copy of the `claude` executable, so an update elsewhere does not replace the file under a running seat. | [Updating Claude Code](updating-claude-code.md) |
| Shows every running seat in one iTerm tab, one pane per seat. | [The iTerm view](commands.md#the-iterm-view) |
| Can run a team from a checkout fixed at a release, with its state folder kept outside that checkout. | [Pinned releases](pinned-release.md) |

The commands are `check`, `up`, `status`, `view`, `titles`, `say`, `flush`, `attach`, `migrate`, `down`
and `run-exclusive`. Source: [Commands](commands.md); the `case` at the end of `fabrikito`.

## What it needs

- macOS, `tmux`, `claude` (Claude Code), `git` 2.36 or later, `gh`, and the system `ruby` (no gems).
  Source: [Requirements](commands.md#requirements).
- iTerm is optional. It is used only for the view of all seats: `up --no-view`, or `display.iterm:
  false` in the team file, runs a team without it, and `attach` works in any terminal. Source:
  [The iTerm view](commands.md#the-iterm-view); `cmd_view` in `fabrikito`.
- Every seat is a separate Claude Code session with its own context, so token use grows with the
  number of seats that are working. Source: [Right-sizing a team](right-sizing.md).
- A C compiler, only to run the project's own end-to-end test. Source:
  [Requirements](commands.md#requirements).

## How a team is defined

- One YAML file per team: the repository and its GitHub project, the owner, where worktrees go, the
  session settings, permission rules, prompts and an ordered list of roles. Source:
  [The team file](team-file.md#its-parts).
- Roles are yours to define. The repository ships generic prompts for an engineering manager, a tech
  lead, a full-stack engineer, QA, a security engineer and a technical writer, and an example team that
  uses the first five and holds a writer seat commented out; a project can use its own prompts
  instead. Source: `roles/`; [`teams/example.yaml`](../teams/example.yaml).
- A team file can list documentation repositories (`repo.docs_repos`) that a writer seat may also
  change. fabrikito makes no checkout of them and adds no permission rules for them: against a push
  to such a repository's default branch, the writer prompt is the only guard the team provides. Source: [The team file](team-file.md#its-parts); [Safety](safety.md).
- Each role can have its own model, effort, permission mode, permission rules, skills, kickoff message
  and temp folder. Source: [The team file](team-file.md#its-parts); `teams/example.yaml` documents every
  key.
- A seat with a temp folder of its own may edit files there without being asked, in a permission mode
  that prompts: its settings carry an `Edit` allow on that folder and on no other role's. A temp folder
  that overlaps another role's, the state folder, the repository, a working directory or the worktree
  folder is refused when the team file loads. Source: [Temp files](team-file.md#temp-files).
- Your own team files and project prompts are git-ignored, so a project's specifics stay out of the
  fabrikito repository. Source: [Which team file](commands.md#which-team-file).

## The safety model

Say these as the docs say them. Do not strengthen them.

- "These rules are an accident guard, not a security boundary: every seat runs as the owner's OS user,
  with the owner's GitHub credential, and can change what loads." Source: [Safety](safety.md).
- A permission rule matches command text, so a command written another way gets past it. The page
  lists what the rules do not cover. Source: [Safety](safety.md), "What the rules cannot do".
- The launcher does not turn on Claude Code's sandbox: seats run without one unless settings that
  apply to them enable it. Source: [Safety](safety.md), last paragraph.
- Deny rules hold in every permission mode, `bypassPermissions` included, and an ask rule still
  prompts there. `bypassPermissions` skips every other prompt and is meant for an isolated machine
  only. Source: [Safety](safety.md), the paragraph on `permission_mode`.
- Merging is not blocked by the launcher. The example team file denies the `gh` merge commands for
  every role but the engineering manager, who is asked, and `check` warns about a role whose rules have
  neither a deny nor an ask on them, unless it is marked `may_merge`. The shared prompt tells every seat
  never to merge; the engineering manager's prompt lets it merge only on the owner's instruction.
  Source: [Safety](safety.md), the merge patterns; `teams/example.yaml`; `roles/common.md`, hard rule
  1; `roles/em.md`.
- Session names and `[from ...]` labels on messages are claims, not identities: nothing authenticates a
  sender. Source: [How seats talk](how-it-works.md#how-seats-talk).
- Auto memory is off in every seat by default, and such a seat also gets an `Edit` deny (which covers
  the Write tool too) on the repository's auto-memory folder. Reading the folder is not denied, a
  script that opens the file itself is not stopped, and the deny covers only Claude Code's default
  folder, not one named by `autoMemoryDirectory`. Source: [Safety](safety.md), the paragraphs on auto
  memory.
- The hard rules in the shared prompt (never merge, confirm the remote, no secrets in anything written,
  no change without an issue, and the rest) are prompt text. Only the ones a team file also writes as
  permission rules are enforced by Claude Code, and those too only as an accident guard. Source:
  `roles/common.md`, "Hard rules"; [What the rules are, and are not](how-it-works.md#what-the-rules-are-and-are-not).
- Report a vulnerability privately, not in a public issue. Source: [SECURITY.md](../SECURITY.md).

## Known limits

- **macOS only.** The requirements name macOS, and parts of the launcher use macOS tools (the iTerm
  view runs `osascript`). Source: [Requirements](commands.md#requirements).
- **One machine, one OS user.** Every seat of every team on a machine runs as the same user, shares
  the tmux server and the GitHub credential, and can be typed into by any process of that user.
  Source: [Safety](safety.md).
- **`say` depends on how Claude Code draws its input box.** It recognises the box as Claude Code
  2.1.316 draws it, and refuses rather than guess, so a Claude Code update that changes the box makes
  `say` refuse every seat until fabrikito is updated. Source: [`say`](messaging.md#say).
- **Messages between permission classes are held by default.** The launcher sets no
  `crossSessionInbound`, and with no such setting in force Claude Code holds a message between a seat
  in `bypassPermissions` and a seat in any other mode: it waits for a human in the receiver's pane, and
  is dropped if nobody answers. `check` warns when the team file's seats fall into both classes. Source:
  [Which messages are held](messaging.md#which-messages-are-held).
- **Running seats do not know a seat added later.** A seat's roster is written into its prompt when it
  starts, so after a role is added to the team file the seats already running do not know it, and will
  not act on its messages, until each is restarted. Source: [What `up` does](how-it-works.md#what-up-does),
  step 4.
- **Separate temp folders are not a boundary between seats.** A role's own temp folder keeps files apart
  by accident guard only: every seat runs as the same user. Source: [Temp files](team-file.md#temp-files).
- **A seat at a dialog waits for a human.** A trust dialog in a folder Claude Code has not seen, or a
  prompt from an ask rule, stops that seat until someone answers; `say` does not type into a dialog.
  Source: [Safety](safety.md), last paragraph; [Troubleshooting](troubleshooting.md).
- **The gate catches mistakes, not a seat that edits the gate.** It runs scripts from the seat's own
  tree, and gates only uncommitted work in the seat's configured working tree. The reviewer's run of
  the gate on the pull request is the real check. Source: [How it behaves](gate.md#how-it-behaves).
- **The stop gate does not take the `run-exclusive` lock yet.** Source:
  [How it behaves](gate.md#how-it-behaves), last item.
- **The workflow rules are prompts and skills.** Who reviews, who merges and the hold on a security
  point are text the seats follow, not mechanisms: the launcher does not enforce them. Source: [How work is tracked](workflow.md).
- **Cost is not capped or reported by fabrikito.** You read it per seat with Claude Code's `/usage`.
  Source: [Right-sizing a team](right-sizing.md).
- **Behaviour measured on specific Claude Code versions.** Where a page says "checked on 2.1.316" (or
  another version), the statement was measured there and may differ on a later one. Source: the
  version notes in [Safety](safety.md) and [`say`](messaging.md#say).

## Status

- The latest release is the git tag `v0.3.0`. There is no GitHub Release entry and nothing to download:
  the way to get it is to clone the repository and check out the tag
  ([Set up a release checkout](pinned-release.md#set-up-a-release-checkout)).
  [Release notes: 0.3.0](release-0.3.0.md) lists what changed since `v0.2.0`. A change merged to
  `main` after the tag is in no release yet. The launcher has no version command of its own: `check`
  prints the checkout it runs from and its `git describe`. Source: `git tag`; `gh release list`
  prints nothing; `install_line` in `fabrikito`.
- The repository is public, at <https://github.com/bgoleno/fabrikito>, under the Apache License 2.0.
  The `security-audit` skill is a modified copy of an MIT-licensed skill. Source:
  [LICENSE](../LICENSE); [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
- Every change starts as a GitHub issue and lands through a pull request that links it. Source:
  [Contributing](../README.md#contributing); [Issues first](workflow.md#issues-first).

## What not to say

These read well and are not true of the code on `main`:

- That seats are sandboxed, kept out of each other's files, or unable to reach your files or
  credentials. A worktree of its own keeps a seat's work apart from the others'; it does not stop a
  seat from reaching another's.
- That a seat cannot merge, push to the base branch or change its own rules. The rules make these an
  accident a seat is stopped or asked at, not something it cannot do.
- That messages are authenticated, or that the message log proves who sent what.
- That it runs on Linux or Windows, or without tmux.
- That more seats mean faster work or lower cost. [Right-sizing a team](right-sizing.md) says token
  use grows with the seats that are working, and that a team of three to five is a good start.
