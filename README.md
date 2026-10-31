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
./factory.sh say <role|all> "..."         type a message into a seat (this is how seats talk)
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
  retarget a team.
- `storage`: `volume` and `root`. Every worktree is created under `<volume>/<root>/`. The volume must be
  mounted, checked from the mount table when a worktree is created; the launcher never falls back to
  another disk.
- `sessions`: tmux name prefix, an optional claude `wrapper`, `args`, and an optional default `model` and
  `effort`. Unset means the flag is omitted and the seat inherits `~/.claude/settings.json`.
- `prompts.common` and a per-role `prompt` (file) or `prompt_text` (inline). Placeholders such as
  `@@ROSTER@@`, `@@GITHUB_REPO@@`, `@@PROJECT_URL@@` and `@@WORKTREE_ROOT@@` are filled in per seat.
- `roles`: ordered; each has `title`, `workdir` (`project` folder or `worktree`), a prompt, and
  optional `model`, `effort`, `session`, `kickoff`, `summary`.

Unknown keys, missing prompt files, duplicate session names and unknown placeholders are errors at load
time, before anything starts.

## Issues first

Every change starts as an issue. The shared prompt (`roles/common.md`) makes this a hard rule for every
seat: no change starts without an issue, and the engineering manager files one when it is missing. A
pull request closes its issue with `Closes #<n>` (see `.github/pull_request_template.md`), so the issue
closes exactly when its change lands and the board stays honest.

## How seats talk

`say` types a message into another seat's tmux pane by bracketed paste. It refuses to deliver to a seat
that is not running claude (the text would run as a shell command) or that is waiting at a startup
dialog (the Enter would pick "No, exit"). Every message is logged with its delivery outcome to
`.state/<team>/messages.log`. Messages are labelled `[from <role>]`; the human's are `[from owner]`.

## Safety

The example team runs `claude --dangerously-skip-permissions`: there are no permission prompts, so the
hard rules in the shared prompt (`roles/common.md`) are the only guardrail. Read them before changing
them. A seat started in a folder Claude Code has not seen stops at a trust dialog until a human answers
it once; `up` reports which seats those are.

## Tests

`TEST_VOLUME=/Volumes/YourDrive test/e2e.sh` runs the launcher against a throwaway repo with a stand-in
`claude` on a private tmux server. It covers worktree placement on the volume, per-role model and
effort, message delivery, migrating a legacy worktree (clean and dirty), and refusing to run when the
volume is not mounted.
