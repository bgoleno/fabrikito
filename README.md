# fabrikito

Run a team of Claude Code sessions on one project: an engineering manager, a tech lead, engineers, QA,
security, or whatever roles you define. `fabrikito` starts each one as a persistent tmux session in a git
worktree of its own, tells it its role, lets it message the other seats, and shows them all together in one
iTerm tab.

- **One YAML file defines the team.** Roles, prompts, models, effort, permissions and where each seat's
  files live are in a team file per project, so different projects get different teams. Every key is
  documented in [`teams/example.yaml`](teams/example.yaml).
- **No server, no background service.** `fabrikito` is a bash script (with the system `ruby` to read the
  YAML, no gems). It generates each seat's prompt, settings and launch script and starts the seat; tmux
  keeps it running and Claude Code's own cross-session messaging carries the messages. See
  [How it works](docs/how-it-works.md).
- **Seats work in separate worktrees.** Each seat has its own working directory, so engineers do not
  overwrite each other's files, and the team's work lands through pull requests.
- **Rules are generated into each seat's settings.** Deny rules on the files that would change a seat's own
  rules, and an ask on any push to the base branch, are written into its settings file at every `up`. They
  guard against accidents, not against a determined seat or user: read [Safety](docs/safety.md) for what they
  cover and what they do not.
- **A seat can be held to your gate.** With `gate_on_stop`, a seat that stops with uncommitted work is held
  until the repository's checks pass. See [The gate](docs/gate.md).

## Quick start

You need macOS, `tmux`, `claude` (Claude Code), `git` 2.36 or later, `gh` and the system `ruby`. See
[Requirements](docs/commands.md#requirements) for the details.

```
git clone https://github.com/bgoleno/fabrikito.git
cd fabrikito
cp teams/example.yaml teams/team.yaml     # edit it: your repository, project, storage and roles
./fabrikito check                        # validate the team file and show where everything lives
./fabrikito up                           # start the team
./fabrikito view                         # open an iTerm tab with every running seat
./fabrikito say em "What is the plan for today?"
./fabrikito down --yes                   # stop the seats (worktrees are kept)
```

Run `check` first. Your own team files in `teams/`, and anything under `projects/`, are git-ignored, so a
project's specifics stay out of this repository. Every command and option is in
[Commands](docs/commands.md). To decide how many seats to run and what they cost, see
[Right-sizing a team](docs/right-sizing.md).

## Documentation

| Read | To |
|---|---|
| [How it works](docs/how-it-works.md) | See how the parts fit together: what `up` does, what a seat is made of, hooks, messaging. |
| [Commands](docs/commands.md) | Install and run a team: every command and option, which team file is used, throwaway teams, the iTerm view. |
| [The team file](docs/team-file.md) | Set up a team: what each part does, what is checked, how a new worktree is prepared, and temp files. |
| [Right-sizing a team](docs/right-sizing.md) | Choose the number of seats, effort and model per seat, and see the cost. |
| [The fabrikito plugin](docs/plugin.md) | See how fabrikito's skills reach every seat. |
| [How work is tracked](docs/workflow.md) | The issues-first rule and the seats' progress notes. |
| [The gate](docs/gate.md) | How a seat is held to the repository's checks when it stops. |
| [Pinned releases](docs/pinned-release.md) | Run a team from a checkout fixed at a release. |
| [Safety](docs/safety.md) | What the permission rules in each seat's settings cover, and what they cannot do. |
| [Updating Claude Code](docs/updating-claude-code.md) | Update Claude Code on a running team, and remove old copies of claude. |
| [Testing](docs/testing.md) | Run a live test on a private tmux server, and the end-to-end test. |
| [Troubleshooting](docs/troubleshooting.md) | Find what you see (an error, a refused message, a silent seat) and what to do. |

The full index is [docs/README.md](docs/README.md). Messaging (how seats talk, `say`, the message log),
[Safety](docs/safety.md) and [Updating Claude Code](docs/updating-claude-code.md) have moved to `docs/`.

## Reporting a vulnerability

Report a vulnerability through GitHub's private vulnerability reporting:
<https://github.com/bgoleno/fabrikito/security/advisories/new>. Do not open a public issue for it.
See [SECURITY.md](SECURITY.md).

## Contributing

Every change starts as a GitHub issue, and its pull request links the issue and fills in the pull request
template. Nothing tracked may name a specific project, person, drive or path. Before a pull request, run
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
