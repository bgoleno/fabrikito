# Documentation

Reference documentation for fabrikito. The [README](../README.md) introduces the project.

| Page | Read it to |
|---|---|
| [How it works](how-it-works.md) | See how the parts fit together: what `up` does, what a seat is made of, the hooks, how seats talk, the gate, progress notes and the plugin skills. |
| [Commands](commands.md) | Install and run a team: requirements, every `fabrikito` command and option, which team file is used, throwaway teams, and the iTerm view. |
| [The team file](team-file.md) | Set up a team: what each part of the team file does, what is checked when it loads, and how a new worktree is prepared (`repo.copy`, `repo.bootstrap`). Every key is documented in [`teams/example.yaml`](../teams/example.yaml). |
| [Right-sizing a team](right-sizing.md) | Decide how many seats to run, set effort and model per seat, and see what a team costs. |
| [The fabrikito plugin](plugin.md) | See how fabrikito's skills reach every seat, which skills run only when typed, and how the plugin is loaded and protected. |
| [How work is tracked](workflow.md) | See the issues-first rule, how a seat's progress note is kept and shown back at every start, and how a security point found in a review holds a merge until `sec` clears it. |
| [The gate](gate.md) | See how a seat with `gate_on_stop` is held to the repository's gate when it stops with uncommitted work, and what the gate does not catch. |
| [Pinned releases](pinned-release.md) | Run a team from a checkout of its own, fixed at a release, so changes here do not reach its running seats: the one-time move of its state, a rolling upgrade, and removing an old release. |
| [Messaging](messaging.md) | See how seats message each other: which messages Claude Code holds, what `say` checks before it types into a seat, the kickoff, and the format of the message log. |
| [Safety](safety.md) | See what the generated permission rules cover (protected files, the base-branch push ask, the message log, other teams' state, auto memory) and what they cannot do. |
| [Updating Claude Code](updating-claude-code.md) | Update Claude Code on a running team: why seats run the team's own copy of claude, how to update, and how to remove old copies. |
| [Project facts](facts.md) | Describe the project elsewhere (a site, a talk) without overclaiming: checked statements on what it is, what it does, what it needs, the safety model, known limits and status, each with its source. |
| [Testing](testing.md) | Run a live test on a private tmux server, and run, extend or read the end-to-end test. |
| [Troubleshooting](troubleshooting.md) | Find what you see (an error, a refused message, a silent seat) and what to do about it. |
