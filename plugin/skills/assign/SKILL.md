---
name: assign
description: "For the engineering manager: hand one issue to one seat with a complete brief written from the template in your role prompt, send it, and record the assignment on the issue. Arguments: <issue> <role id> [--dry-run]."
argument-hint: <issue number or URL> <role id> [--dry-run]
---

# Assign an issue to a seat

Arguments: `$ARGUMENTS`. They are an issue (number or URL), the role id of the seat taking it, and
optionally `--dry-run`. If the issue or the seat is missing, ask for it and stop.

Your role prompt holds the rules: the brief template, one issue per engineer at a time, and not
having two seats edit the same files. This skill is only the order to apply them in. Where the two
differ, the role prompt wins.

## When to use
- When you hand one issue to one seat to work on, review or verify.
- Not for a follow-up on work already assigned, and not for a reply. Send those as plain messages.

## Steps
1. **Find the template.** Find the brief template in your role prompt: the block that starts
   `Issue:` and lists the lines a brief must fill. If your role prompt has none, stop and say so. Do
   not write a brief from memory or from this skill.
2. **Read the issue in full,** with its comments:
   `gh issue view <n> -R <repo> --json title,state,body,comments`. Not `--comments`: without a
   terminal it prints the comments only, so the body and its acceptance criteria are lost. Note the
   acceptance criteria, what it depends on, and any design notes in the comments. Stop if:
   - it has no acceptance criteria; or
   - something it depends on is not merged and the seat cannot work around it.

   Shape it first, or ask `tl` to.
3. **Check the seat.**
   - The role id is in your roster.
   - `ListAgents` shows its session (or `status` shows it up).
   - It holds no other issue still in flight. Check your own record and its open PRs:
     `gh pr list -R <repo> --state open --search "author:@me"` lists every seat's PRs, since seats
     share one account, so match them by branch and issue.
4. **Check the boundaries.** List the open PRs and what they touch:
   `gh pr list -R <repo> --state open --json number,title,headRefName,files`. If this work would edit
   the same files as another seat's PR, either sequence it (say so under Boundaries) or stop and
   choose a different issue.
5. **Write the brief.** Fill every line of the template. Write "none" rather than leaving a line
   out.
   - Name the branch, and the base ref with its current commit (`git ls-remote <remote> <base>`).
   - Name the reviewers the role prompt calls for, including `sec` when the change is
     security-sensitive.
   - Include nothing that must not reach a tracker: no secret, and no detail of an unfixed security
     finding the role prompt keeps private.
6. **Send it** to the seat with `SendMessage`, `to` set to its session name. Use the role prompt's
   `say` fallback only where it says to. One message, which stands alone.
7. **Record it on the issue** with one comment: `gh issue comment <n> -R <repo> --body-file <file>`.
   - The comment starts with `Assigned to <role id> (<session>) by <your role id>.` and is followed by
     the brief.
   - Seats share one GitHub account, so the comment is the record. A GitHub assignee would not name
     the seat.

With `--dry-run`, do steps 1 to 5, read-only commands only. Then print exactly what steps 6 and 7
would send and post, each under its own heading, and say `dry run: nothing sent or posted`. Do not
call `SendMessage`, `say` or `gh issue comment`. Use this to check the skill without assigning
anything.

## What to report
- After a real run, one line: the issue URL, the seat, the branch, and the URL of the comment that
  records it.
- After a dry run: the message and the comment as they would go out.

## Stop and ask when
- Your role prompt has no brief template.
- The issue has no acceptance criteria, or depends on unmerged work the seat cannot avoid.
- The seat is not in the roster, is not up, or still holds another issue.
- Two seats would edit the same files and you cannot sequence them.
- Deciding the work needs the owner (scope, risk, anything outward-facing): ask them through your
  usual route before assigning.
