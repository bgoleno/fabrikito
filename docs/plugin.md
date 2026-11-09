# The fabrikito plugin

The Claude Code plugin that carries fabrikito's skills into every seat, and how it is loaded.

`plugin/` is a Claude Code [plugin](https://code.claude.com/docs/en/plugins) (`.claude-plugin/plugin.json`
and `skills/`) that `up` loads into every seat with `--plugin-dir <this checkout>/plugin`. Seats work in
the target project's folders, where this repository's own `.claude/` is never read, so this is how
fabrikito's skills reach them. Nothing is installed into your settings: a session fabrikito did not start
does not have the plugin. Its skills are namespaced by the plugin name and show as `/fabrikito:<skill>`.

## Its skills

Its skills are procedures for a role (assigning an issue, for example), loaded only when used instead of
sitting in every prompt. The skill folders under [`plugin/skills/`](../plugin/skills/) are the list, and each
skill's `description` says whom it is for and when to use it. `/fabrikito:ping` only proves the plugin loaded.
Every seat loads every skill. A skill reaches its role through its description and through that role's
`skills:` in the team file (`teams/example.yaml` names each one where it belongs). Two skills run only
when typed: see [Skills started by typing them](#skills-started-by-typing-them). A skill is the
procedure. The rules it applies (a brief's fields, the review bar) stay in the role prompt, which the
skill points to rather than copies, and a skill stops if the prompt lacks them. `test/e2e/launch.sh`
checks every skill's frontmatter, so adding one needs no new test code.

### The security-audit skill

`/fabrikito:security-audit` is a modified copy of the MIT-licensed
[security-audit-skill](https://github.com/cloudflare/security-audit-skill) from Cloudflare. It is for the
security engineer (`sec`) only: its description says so, and `teams/example.yaml` lists it for `sec` alone
(`test/e2e/audit.sh` checks that no other role's prompt lists it). Every seat still loads it, as every
seat loads every skill. It gives security guidance by default, which writes nothing. A full audit runs
only with the owner's say-so passed through the EM, and its output goes to the team's triage folder,
never into a repository, an issue or a pull request. The team's rules for it are in
[`FABRIKITO-PROCESS.md`](../plugin/skills/security-audit/FABRIKITO-PROCESS.md) in the skill's folder,
which wins over the upstream text where they differ. [`UPSTREAM.md`](../plugin/skills/security-audit/UPSTREAM.md)
there names the upstream commit that was copied and lists every change, and
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) holds the copyright notice and license.

### Skills started by typing them

Two skills set `disable-model-invocation`: `/fabrikito:ping` and `/fabrikito:merge-train`. A seat cannot
start them with its Skill tool; they run when typed as the session's own input. That is not a boundary:
any process running as you can type into a seat's pane (see [Safety](../README.md#safety)). For
`merge-train` the e2e fails if the flag is missing, and the skill's step 1 checks for itself that the
command arrived as the session's own input, with no `[from ...]` label.

The owner types `/fabrikito:merge-train <PR> [<PR>...] [--dry-run]` in the engineering manager's pane, and
the EM merges those PRs in order, each at one pinned head, after gating it stacked on the ones before it,
and stops at the first failure. The EM's prompt, [`roles/em.md`](../roles/em.md), also lets the EM follow
the skill's steps under a standing instruction from the owner. When the EM may merge at all, and what a
typed `/fabrikito:merge-train` covers, are rules in that prompt; the skill is the procedure.

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
  seats have no fabrikito skills.
