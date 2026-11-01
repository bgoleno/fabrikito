# Documentation

Reference documentation for software-factory. The [README](../README.md) introduces the project.

| Page | Read it to |
|---|---|
| [How it works](how-it-works.md) | See how the parts fit together: what `up` does, what a seat is made of, the hooks, how seats talk, the gate, progress notes and the plugin skills. |
| [Commands](commands.md) | Install and run a team: requirements, every `factory.sh` command and option, which team file is used, throwaway teams, and the iTerm view. |
| [The team file](team-file.md) | Set up a team: what each part of the team file does, what is checked when it loads, and how a new worktree is prepared (`repo.copy`, `repo.bootstrap`). Every key is documented in [`teams/example.yaml`](../teams/example.yaml). |
| [The factory plugin](plugin.md) | See how the factory's skills reach every seat, which skills run only when typed, and how the plugin is loaded and protected. |
| [Pinned releases](pinned-release.md) | Run a team from a checkout of its own, fixed at a release, so changes here do not reach its running seats: the one-time move of its state, a rolling upgrade, and removing an old release. |
| [Testing](testing.md) | Run a live test on a private tmux server, and run, extend or read the end-to-end test. |
| [Troubleshooting](troubleshooting.md) | Find what you see (an error, a refused message, a silent seat) and what to do about it. |

The rest of the reference is in the [README](../README.md): safety and permissions, messaging,
the gate, progress notes and updating Claude Code.
