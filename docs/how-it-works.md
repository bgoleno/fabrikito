# How it works

software-factory turns one YAML team file into a team of Claude Code sessions. There is no server
and no background service: `factory.sh` (bash) and `lib/team_config.rb` (the system ruby, no gems)
generate each seat's prompt, settings and launch script, and start each seat in a tmux session of its
own. After that, tmux keeps the seats running, Claude Code's own messaging carries their messages,
and three small hook scripts run inside the seats. Each command (`up`, `say`, `down` and the rest)
does its work and exits; `attach` returns when you detach.

This page shows how the parts fit together. Each section links to the page with the exact rules.

## The parts

| Part | What it is |
|---|---|
| `factory.sh` | The launcher. Every command (`check`, `up`, `view`, `titles`, `status`, `say`, `attach`, `migrate`, `down`) is a function in it. |
| `lib/team_config.rb` | Reads and validates the team file, and generates what each seat is started with: its prompt, kickoff, settings (permission rules and hooks) and claude flags. `factory.sh` calls it for every value. |
| `lib/session_start.sh` | A `SessionStart` hook: shows a seat its progress note and the state of its working directory. |
| `lib/log_message.sh` | A `PostToolUse` and `PostToolUseFailure` hook on `SendMessage`: writes each message a seat sends to the message log. |
| `lib/stop_gate.sh` | A `Stop` hook: runs the repository's gate when a seat ends a turn with uncommitted work. |
| `lib/screen_bounds.js` | Finds the usable area of the screen, for sizing the iTerm window. |
| `roles/` | Generic prompts: `common.md`, shared by every seat, and one for each standard role (`em`, `tl`, `fs`, `qa`, `sec`). A project can use its own prompts instead. |
| `plugin/` | The factory plugin: skills that every seat loads. |
| `teams/example.yaml` | The documented example team file. Your own team files sit beside it and are git-ignored. |
| `.state/<team>/` | Everything generated for a team (settings, launch scripts, prompts, the team's copy of claude), plus the message log, progress notes and the gate's state. Git-ignored. `TEAM_STATE_DIR` moves it. |
| `test/e2e.sh`, `test/live-env.sh` | The end-to-end test's entry point (the shared setup, the count and the cleanup), and the helper that runs a live test on a private tmux server. |
| `test/e2e/` | The end-to-end cases, one file per area, which `test/e2e.sh` sources in the order of its `AREAS` list; `lib.sh` holds the helpers more than one area uses, and `fake-claude.c` is the stand-in for `claude`. |

## What `up` does

Every command first validates the whole team file: unknown keys, missing prompt files, duplicate
session names, unknown placeholders and invalid UTF-8 stop the command before anything starts. Then
`up`:

1. **Refuses a throwaway team on the default tmux server.** A team file outside `teams/` looks like a
   test copy, and a copy shares the real team's session names. Unless `--default-socket` is given,
   `up` stops before any tmux call. See [Throwaway teams](commands.md#throwaway-teams).
2. **Makes the state folders**, the progress-note folder and, when the team has a `sec` role, the
   security-triage record folder.
3. **Makes the team's own copy of claude.** It finds `claude` on the `PATH`, reads its version and,
   if `.state/<team>/bin/claude-<version>/claude` is missing, clones or copies the executable there
   and checks the copy. Seats run this copy, so a Claude Code update in another session does not
   replace the file under them. See [Updating Claude Code](../README.md#updating-claude-code).
4. **Starts each role in turn,** in file order or in the order given on the command line, and stops
   at the first role it cannot start. A role whose tmux session already exists is skipped and left
   alone; if the claude file it runs was replaced under it, `up` prints an `ATTENTION` line saying
   to restart it. For each other role it:
   - **Makes the worktree,** for a `worktree` seat that has none. No worktree of the same name may be
     registered elsewhere (`migrate` moves an old one); the volume must be mounted and the folder must
     be on it; the main checkout's `origin` must name `repo.github`; `up` fetches the base
     and runs `git worktree add --detach` at `repo.base`, then copies `repo.copy` and runs
     `repo.bootstrap`. A worktree that exists is never reset or changed, because it may hold a seat's
     work. Only its setup is redone, if it was never marked done. See
     [New worktrees](team-file.md#new-worktrees).
   - **Writes the seat's settings** to `.state/<team>/settings/<role>.json`, read-only. They hold the
     merged permission rules, the hooks and a few environment settings. See [Safety](../README.md#safety).
   - **Renders the seat's prompt:** `prompts.common`, then the role's prompt, then a Skills section
     when the role lists `skills`, with every `@@PLACEHOLDER@@` filled in for that seat (its title,
     session, working directory, the roster, the note's path and the rest). It also renders the
     kickoff, the seat's first message.
   - **Writes a launch script,** `.state/<team>/launch/<role>.sh`. It changes to the seat's folder,
     sets or clears the environment the seat needs (`CLAUDE_CONFIG_DIR`, `DISABLE_AUTOUPDATER`, the
     auto-memory switch), and runs the team's copy of claude, through the `wrapper` if one is set
     and present, with the role's flags, `--settings <file>`, `-n <session>`, the prompt as
     `--append-system-prompt` and the kickoff as the first message.
   - **Starts a tmux session** named for the seat, in the seat's folder, with `TEAM_ROLE`,
     `TEAM_CONFIG` and `TEAM_SCRIPT` set, gives it its title, and types the launch script's path
     into its shell.
5. **Reports seats that need a human.** A seat started in a folder Claude Code has not seen stops at
   a trust dialog until someone answers it once; `up` prints an `ATTENTION` line for each seat whose
   screen is not its input box.
6. **Opens the iTerm view,** a tab with every running seat in a pane, when it started at least one
   seat, unless `--no-view` is given, `display.iterm` is `false` or `TEAM_VIEW=0` is set
   (the tests use it). See [The iTerm view](commands.md#the-iterm-view).

A seat's tmux session is a shell that runs claude. Quitting claude leaves the shell and the session
alive, and `up` then skips that seat; run `down --yes <role>` first to start it fresh. `down` kills the
tmux session and keeps the worktree, and closing the iTerm tab only detaches from the seats.

## What a seat is made of

- **A role.** Its prompt is appended to Claude Code's system prompt, so it survives a compaction. It
  holds the shared rules from `roles/common.md`, the role's own prompt and the roster: a table of
  every seat's role id, title and session name.
- **A working directory.** Either a git worktree of its own, `<storage.volume>/<storage.root>/team-<role>`
  by default (`workdir.name` changes the folder name), created detached at the base ref, or an
  existing folder (`workdir.type: project`). See [The team file](team-file.md).
- **A settings file,** passed with `--settings`. It holds the team's and the role's permission rules
  merged (a role can add or tighten a rule, never loosen one), the denies and allows `factory.sh` adds,
  and the hooks below. Its single values, such as `env`, win over the user, project and local
  settings files. Its permission rules do not replace theirs: Claude Code applies the rules of every
  settings file together, deny first, then ask, then allow, so an `allow` in the project's or the
  user's settings still approves a call this file neither denies nor asks on. Managed settings, and,
  depending on the account, installed mods apply above all of them.
  When a seat's permission mode is set and is not `bypassPermissions`, the file also sets
  `disableBypassPermissionsMode`, so the seat cannot be switched into bypass from inside the session.
- **The factory plugin,** loaded with `--plugin-dir` unless `sessions.claude.plugin` is `false`. See
  [The factory plugin](plugin.md).
- **A progress note,** `.state/<team>/notes/<role>.md`, outside the working directory, so it survives
  a restart and a recreated worktree. See [Progress notes](workflow.md#progress-notes).

## The hooks

Every hook is a script in `lib/`, written into the seat's generated settings with its arguments. No
hook is installed into your own settings.

| Hook | Script | When it runs | Which seats |
|---|---|---|---|
| `SessionStart` | `lib/session_start.sh` | At startup, on resume, after `/clear` and after a compaction (no matcher). | Every seat. |
| `PostToolUse` and `PostToolUseFailure`, matcher `SendMessage` | `lib/log_message.sh` | After each `SendMessage` the seat sends, whether it succeeded or failed. | Every seat. |
| `Stop` | `lib/stop_gate.sh` | Each time the seat ends a turn. | Only roles with `gate_on_stop: true`. |

- **`session_start.sh`** prints the seat's progress note, its branch, its uncommitted files and its
  last 10 commits, and Claude Code adds that to the seat's context. So a seat that restarts, or loses
  detail to a compaction, sees its task and next step again. See
  [Progress notes](workflow.md#progress-notes).
- **`log_message.sh`** appends one line per message to `.state/<team>/messages.log`, in the same
  format `say` uses. It never blocks or changes the message, and it always exits 0. See
  [The message log](../README.md#the-message-log).
- **`stop_gate.sh`** runs `repo.gate` in the seat's working directory when the seat stops with
  uncommitted changes. If the gate fails, the seat is sent back to work with the failure. See
  [The gate](#the-gate) below.

A user setting of `disableAllHooks: true` switches hooks off, with an exception for gated seats:
see [Progress notes](workflow.md#progress-notes) and [The gate](../README.md#the-gate).

## How seats talk

Seats message each other with Claude Code's
[cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging). Because `up`
starts each seat with `-n <session>`, a seat's name is its session name in the roster, and the shared
prompt tells seats to send with `SendMessage` to that name and to check `ListAgents` for who is up.

- **Held messages.** Claude Code decides whether to deliver a message from the two sessions'
  permission modes. Seats in one class (all `bypassPermissions`, or all other modes) get each other's
  messages at once; across classes a message waits for a human to approve it in the receiver's pane.
  `check` warns when a team's seats fall into both classes. See
  [Which messages are held](../README.md#which-messages-are-held).
- **`say`** is how the owner and scripts reach a seat, and the seats' fallback when `SendMessage`
  cannot reach one. It types the message into the seat's tmux pane, labelled `[from <role>]`, and it
  types only when it sees Claude Code's input box ready for input, so it does not type into a dialog
  or a shell it can see. A dialog that appears in the moment between its checks and its keys is not
  caught. See [`say`](../README.md#say).
- **The kickoff** is each seat's first message, labelled `[from launcher]`, so it never reads as the
  owner typing. See [The kickoff](../README.md#the-kickoff).
- **The message log,** `.state/<team>/messages.log`, records every `say` with whether it was
  delivered, and every `SendMessage` a seat sends (through the hook above). Every seat but `em` has a
  `Read` deny on it, an accident guard like the other rules (see [Safety](../README.md#safety)). See
  [The message log](../README.md#the-message-log).

Session names and `[from …]` labels are claims, not identities. The prompt tells seats to act only on
roster names, which guards against mistakes, not impersonation. See
[How seats talk](../README.md#how-seats-talk).

## The gate

`repo.gate` is the repository's pass/fail command. A seat with `gate_on_stop: true` runs it through the
`Stop` hook each time it ends a turn with uncommitted changes, and is sent back to work while it
fails, up to a limit. The shared prompt also tells every seat to run the whole gate
before new work. The reviewer's own run of the gate on the pull request is the real check. See
[The gate](../README.md#the-gate).

## Progress notes

Each seat keeps a short note of its current task, branch, state, next step and what it waits for, and
rewrites it when the task changes state. The `SessionStart` hook shows it back at every start and
after every compaction. A seat may edit only its own note: the generated settings allow its own note
and deny every other seat's. See [Progress notes](workflow.md#progress-notes).

## The plugin skills

The skills under `plugin/skills/` are procedures for a role, such as assigning an issue
(`factory:assign`), starting a task (`factory:start-task`) or reviewing a pull request
(`factory:review-pr`). A skill is loaded only when it is used, instead of sitting in every prompt.
The rules a skill applies, such as the brief's fields or the review bar, stay in the role prompt,
and the skill points to them. See [The factory plugin](plugin.md).

## What the rules are, and are not

The permission rules in each seat's settings, and the hard rules in the shared prompt, guard against
accidents. They are not a security boundary: every seat runs as the owner's OS user, with the owner's
GitHub credential, and a rule matches command text, so a command written another way gets past it.
The launcher does not turn on Claude Code's sandbox. See [Safety](../README.md#safety).
