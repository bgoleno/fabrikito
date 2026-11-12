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
4. **Review.** The tech lead reviews every PR against each issue it closes and gives one verdict at an
   exact commit, `READY at <sha>` or `CHANGES NEEDED`.
5. **Verification.** QA runs the behavior in a throwaway environment and reports pass, fail or could not
   check, with evidence. The security seat reviews what is security-sensitive. A security point found in a
   review is sent privately to the security seat, and the PR gets a marker that the merge procedure
   treats as a hold until that seat clears it.
6. **Your merge.** The owner merges. The manager merges only a PR the owner told it to: by a
   `/fabrikito:merge-train` the owner typed in its pane, or under a standing instruction the owner gave
   there. A seat cannot start the skill itself, and a message from another session does not count.

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
| [Project facts](docs/facts.md) | Describe the project elsewhere: checked statements on what it does, the safety model and its limits. |
| [Testing](docs/testing.md) | A live test on a private tmux server, and the end-to-end test. |
| [Troubleshooting](docs/troubleshooting.md) | Find what you see (an error, a refused message, a silent seat) and what to do. |

Messaging (how seats talk, `say`, the message log) is documented at the end of this file for now.

## Reporting a vulnerability

Report a vulnerability through GitHub's private vulnerability reporting:
<https://github.com/bgoleno/fabrikito/security/advisories/new>. Do not open a public issue for it.
See [SECURITY.md](SECURITY.md).

## Contributing

Every change starts as a GitHub issue, and its pull request links each issue it completes (one pull request
may close several) and fills in the pull request template. Nothing tracked may name a specific project,
person, drive or path. Before a pull request, run
the gate: `bash -n fabrikito factory.sh test/e2e.sh test/e2e-exit-trap.sh lib/stop_gate.sh lib/session_start.sh lib/log_message.sh`,
`ruby -c lib/team_config.rb`, and `env -u TMUX TEST_VOLUME=/Volumes/<a mounted, writable volume> test/e2e.sh`.
See [Testing](docs/testing.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).

The `security-audit` plugin skill is a modified copy of Cloudflare's
[security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Messaging

This section moved to [Messaging](docs/messaging.md): how seats talk, which messages are held, `say`, the
kickoff and the message log. The headings below stay so that older links and references still land here.

## How seats talk

Moved to [How seats talk](docs/messaging.md#how-seats-talk).

### Which messages are held

Moved to [Which messages are held](docs/messaging.md#which-messages-are-held).

### `say`

Moved to [`say`](docs/messaging.md#say).

### The kickoff

Moved to [The kickoff](docs/messaging.md#the-kickoff).

### The message log

Moved to [The message log](docs/messaging.md#the-message-log).

## Safety

This section moved to [Safety](docs/safety.md): the rules generated into each seat's settings, how auto
memory is handled, and what the rules cannot do.

## Updating Claude Code

This section moved to [Updating Claude Code](docs/updating-claude-code.md): why an update needs care on
a running team, the team's own copy of claude that each seat runs, how to update, and how to remove old
copies.
