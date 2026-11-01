# The factory plugin

The Claude Code plugin that carries the factory's skills into every seat, and how it is loaded.

`plugin/` is a Claude Code [plugin](https://code.claude.com/docs/en/plugins) (`.claude-plugin/plugin.json`
and `skills/`) that `up` loads into every seat with `--plugin-dir <this checkout>/plugin`. Seats work in
the target project's folders, where this repository's own `.claude/` is never read, so this is how the
factory's skills reach them. Nothing is installed into your settings: a session the factory did not start
does not have the plugin. Its skills are namespaced by the plugin name and show as `/factory:<skill>`.

## Its skills

Its skills are procedures for a role (assigning an issue, for example), loaded only when used instead of
sitting in every prompt. The skill folders under [`plugin/skills/`](../plugin/skills/) are the list, and each
skill's `description` says whom it is for and when to use it. `/factory:ping` only proves the plugin loaded.
Every seat loads every skill. A skill reaches its role through its description and through that role's
`skills:` in the team file (`teams/example.yaml` names each one where it belongs). A skill only the owner
may start sets `disable-model-invocation`. A skill is the procedure. The rules it applies (a brief's
template, the review bar) stay in the role prompt, which the skill points to rather than copies, and a
skill stops if the prompt lacks them. `test/e2e/launch.sh` checks every skill's frontmatter, so adding
one needs no new test code.

### Skills a person starts

Two skills set `disable-model-invocation`, so a seat cannot start them itself; a person types them:
`/factory:ping` and `/factory:merge-train`. For `merge-train` the e2e fails if the flag is missing. The
owner types `/factory:merge-train <PR> [<PR>...] [--dry-run]` in the engineering manager's pane, and the
EM merges those PRs in order, each at one pinned head, after gating it stacked on the ones before it, and
stops at the first failure. When the EM may merge at all, and what a typed `/factory:merge-train`
covers, are rules in the EM's prompt, [`roles/em.md`](../roles/em.md); the skill is the procedure.

## Loading it

- It is on by default. A team file without `sessions.claude.plugin` gets the plugin at its next `up`, and
  with it every skill (and, later, every hook or agent) added to `plugin/` after that. Set
  `sessions.claude.plugin: false` to leave the flag out. `check` shows the plugin's path, or `off`.
- A `--plugin-dir` of your own in `sessions.claude.args` is allowed: the flag repeats, so both load. Your
  installed plugins load as usual alongside it.
- Seats get an `Edit` deny on `plugin/`, like `lib/` and `roles/` (see [Safety](../README.md#safety)),
  since it is code every seat runs at its next start, and on each plugin a team loads itself with
  `--plugin-dir` in `args` (the folder with everything under it, or the `.zip`; a relative path is taken
  from the seat's folder).
- What the plugin carries runs in or steers every seat: skills, agents, commands, hooks and MCP
  servers, including hooks and servers declared inline in `plugin.json`. So every pull request that
  changes anything under `plugin/`, `plugin.json` included, gets a security review as well as the
  usual one.
- Managed settings can turn `--plugin-dir` off (Claude Code's docs say so; not tried here), and then the
  seats have no factory skills.
