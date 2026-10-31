---
name: handoff
description: "For any seat, before a context reset, a compaction or the end of a session: rewrite your progress note so a fresh session can carry on, and commit work in progress on your own task branch, never on the base."
---

# Hand off to your next session

Your role prompt holds the rules: the progress note, its path and what goes in it; one task at a
time; checking the remote before a commit or a push; when you may push; and keeping a privately
tracked fix out of anything public. This skill is only the order to apply them in when a session is
about to lose its context. It does not restate them. Where the two differ, the role prompt wins.

## When to use
- Before `/clear` or `/compact`, when your context is nearly full, before you stop for the day, or
  when you are told your session will be restarted.
- Not as a status report to anyone: it writes your note and your branch, and sends nothing.

## Steps
1. **See where you are.**
   - `git status --short` shows uncommitted work. Read the file list, not only the count.
   - `git branch --show-current` shows the branch, and is empty when detached.
   - `git log --oneline -5` shows recent commits.

   Take the task from your progress note. If you have no task, write that in the note and stop.
2. **Commit work in progress,** if there is any, only on your own task branch.
   - **Base branch or detached:** if the branch is the base branch, or HEAD is detached, commit
     nothing. Instead, list the uncommitted files in the note, so the next session finds them.
   - **Check the remote:** run `git remote -v` first, as your role prompt says.
   - **Stage by path:** stage only files you changed for this task, by path (`git add <path> ...`).
     Not `git add -A` or `.`, which would sweep in scratch files, logs or anything secret. Leave
     out anything that must not be committed, and name it in the note.
   - **Commit:** `git commit -m "WIP: <what is done and what is not>"`, with the issue reference
     your role prompt uses (`Refs #<n>`). A WIP commit may leave tests red. Say so in the message.
   - **Private fixes:** for a fix tracked privately, the commit message must not describe the
     finding (your role prompt says what may be public).
3. **Push it only if all of these hold:**
   - the branch is yours;
   - your role prompt allows pushing it;
   - the work is not a privately tracked fix;
   - the branch has no open PR under review. A push there moves the PR's head under its reviewers.
     Check with `gh pr list -R <repo> --head <branch> --state open`.

   Push in its own command, naming the remote and the branch: `git push origin <branch>`. Never run
   a bare `git push`: a branch cut without `--no-track` has the base as its upstream. Otherwise
   leave the commit local, and say so in the note.
4. **Rewrite the progress note** last, with the Write or Edit tool. A fresh session must be able
   to carry on from it alone, so include:
   - the task (issue or PR URL), the branch, and the WIP commit (short SHA, pushed or local only);
   - the state, and the exact next step;
   - what you are waiting for, and from whom;
   - anything decided or verified this session that the repository does not show, and what is
     not verified yet.

   Keep it short. The session start shows only its first lines, and the repository holds the
   rest.

## What to report
One line in your session: the note is updated, the WIP commit (SHA, pushed or local), or why
nothing was committed. Send no message for a handoff alone. If you are waiting on someone, your
role prompt already says how to tell them.

## Stop and ask when
- The only place to commit is the base branch, or a branch that is not yours: leave the work
  uncommitted, and list it in the note.
- You cannot tell whether a file holds something secret or private: leave it out, and say so in the
  note.
