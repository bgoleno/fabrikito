# Right-sizing a team

How many seats to run, and how to see and control what they cost.

Every seat is a separate Claude Code session with its own context, so token use grows with the number
of seats that are working, and with how long each works. Coding has fewer truly parallel tasks than it
seems: three focused seats often get more done than five scattered ones, and a team of three to five is
a good start.

- Start only the seats a task needs: `./fabrikito up em tl fs1`. Add one later with `up fs2`, and stop
  one that is done with `down --yes fs2` (its worktree is kept).
- Add a Technical Writer seat (`dw`, commented in `teams/example.yaml`) when the project's docs fall
  behind its changes or a documentation repository needs its own PRs; a team that rarely changes
  behaviour users can see does not need one.
- An idle seat spends little (Claude Code's session recap and idle compaction can still use some
  tokens). A message delivered to it starts a turn that sends its whole conversation again, so a seat
  that is sent many messages keeps spending.
- Effort is the main cost and depth control (`effort` per role, or `sessions.claude.effort` for all).
  The example team runs the manager at `medium` and the seats that write, test and review code at
  `high`; keep `max` for a hard problem a seat works on unattended, such as a security hunt. A `model`
  per role works the same way. `./fabrikito check` shows each seat's model and effort, and
  `(inherit)` where the seat takes them from `~/.claude/settings.json`.
- To see what a team costs, run `/usage` in a seat. Its Session block counts that seat's own tokens
  (its dollar figure is a list-price estimate, meaningful on API billing). On a subscription it also
  shows the plan usage bars, which every seat draws on, and a breakdown (by skill, subagent, plugin
  and MCP server, with recommendations) of recent usage computed from this machine's session history.
  That covers all the seats together, but also every other Claude Code session on the machine, and it
  is not split by seat. See [Manage costs](https://code.claude.com/docs/en/costs).
