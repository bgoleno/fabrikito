# The team file

A team is one YAML file. This page explains its parts and how a new worktree is set up.
[`teams/example.yaml`](../teams/example.yaml) documents every key in comments: it is
the reference for each key, and the file to copy.

## Its parts

- `repo`, `project`, `owner`: the local checkout, its GitHub repo (`owner/name`), the GitHub Project the
  team tracks work on, and the human it works for. The prompts name them, so this is the only edit to
  retarget a team. `repo.gate` is the repo's pass/fail command: see [The gate](gate.md).
- `storage`: `volume` and `root`. Every worktree is created under `<volume>/<root>/`. The volume must be
  mounted, checked from the mount table when a worktree is created; the launcher never falls back to
  another disk.
- `sessions`: tmux name prefix, an optional claude `wrapper`, `args`, and an optional default `model`,
  `effort` and `permission_mode`. Unset means the flag is omitted and the seat inherits
  `~/.claude/settings.json`. `sessions.claude.plugin` (default `true`) loads the factory plugin into
  every seat: see [The factory plugin](plugin.md).
- `permissions` (`deny`, `ask`, `allow`), at the top level and per role: see
  [Safety](../README.md#safety).
- `other_teams`: other teams' state folders that aren't beside this team's own, each with the
  `observers` allowed to read its log and notes: see [Safety](../README.md#safety).
- `prompts.common` and a per-role `prompt` (file) or `prompt_text` (inline). Placeholders such as
  `@@ROSTER@@`, `@@GITHUB_REPO@@`, `@@PROJECT_URL@@` and `@@WORKTREE_ROOT@@` are filled in per seat.
- `prompts.project` (optional): a file with your project's specifics, such as what the product is,
  folders that are off limits, a running instance never to touch, the gate and the merge procedure.
  Every seat's prompt is the common prompt, then this file, then the role's prompt and skills, so a
  team can keep the shipped prompts and add only this. It takes the same placeholders, may not
  contain a `[from ...]` label, and seats may not edit it. `check` shows it, with the longest rendered
  prompt, and warns when a seat's prompt goes over 199 lines. Without it, prompts are unchanged.
- `roles`: ordered; each has `title`, `workdir` (`project` folder or `worktree`), a prompt, and
  optional `model`, `effort`, `session`, `kickoff`, `summary`, `skills`.
- `skills` (per role): skills to name in that seat's prompt, each a name (`plugin:name` for a plugin's
  skill) with an optional note on when to use it. They are listed after the role's prompt with a note
  that a skill may not be installed; naming one installs nothing. The example team lists commonly
  useful ones from the superpowers plugin and Claude Code's bundled skills.

## Checked at load time

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
  tmux variables of a seat that runs `up`: every variable whose name starts with
  `CLAUDE_CODE_MESSAGING_` (today `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN`,
  and any that a later Claude Code adds), `CLAUDECODE`, `TMUX` and `TMUX_PANE`. So a seat's messaging
  token does not reach an install script. Every other variable of the shell that runs `up` does reach it, and an
  install command runs third-party scripts (package install hooks, for example) with them. There is no
  time limit. If it fails, or `up` is interrupted meanwhile
  (Ctrl-C, TERM, HUP), `up` stops the bootstrap and stops before starting the seat; a worktree it has
  just made is removed (by that exact path), so the next `up` starts over.

When both have finished, `up` marks the setup done (`<state>/setup/<role>`, with the worktree's path).
Every later `up` checks that mark for a worktree it finds, and redoes the copy and the bootstrap
before the seat starts when the mark is missing: after a start that was killed or crashed midway, or
when `repo.copy` or `repo.bootstrap` was added after the worktree was made. A failure there leaves
that existing worktree as it is (it may hold work). Neither runs for a `project` workdir. `check`
shows them.

`up` starts the roles in file order and stops at the first one it cannot start, this setup included:
the seats started before it keep running, and the next `up` starts the rest (it skips running seats).

### Credentials

Do not list real credentials in `repo.copy`: each copy is another file on the worktree volume that a
seat works in. Use development values, or have the bootstrap fetch what it needs. The example team's
`Read` deny on `.env` files covers a copied `.env` like the original.

### Package stores

When worktrees are on another volume, tools that hard-link from a shared store (pnpm, uv) can only
link within one volume, so with the store on the internal disk and the worktrees elsewhere each
worktree gets full copies instead. Point the store at the worktree volume from the bootstrap, for
example `pnpm install --store-dir /Volumes/<drive>/.pnpm-store` or
`UV_CACHE_DIR=/Volumes/<drive>/.uv-cache uv sync`. A plain download cache (npm's) works from either
disk.
