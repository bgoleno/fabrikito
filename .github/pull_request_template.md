Closes #
<!-- Use "Refs #" instead of "Closes #" when this PR does not complete the issue.
GitHub closes an issue on merge when a closing keyword (close, closes, closed, fix, fixes, fixed, resolve,
resolves, resolved) comes right before its reference, whatever the words around it: "does not close #N" and
"will not fix #N" close it too. Write a closing keyword only before an issue this PR completes. For any
other issue use "Refs #N", and do not name it after a closing keyword anywhere in this body, the title or a
commit message. Before asking for review, check what GitHub will close:
gh pr view <pr> --json closingIssuesReferences -->

## What changed

## How it was tested
<!-- The commands you ran and what they printed. This repository's gate is all three of:
bash -c 'rc=0; for f in "$@"; do bash -n "$f" || rc=1; done; exit $rc' gate fabrikito factory.sh lib/*.sh test/*.sh test/e2e/*.sh
bash -c 'rc=0; for f in "$@"; do ruby -c "$f" || rc=1; done; exit $rc' gate lib/*.rb
env -u TMUX TEST_VOLUME=/Volumes/<a mounted, writable volume> test/e2e.sh   (all assertions must pass)
The first two run one check for each file: "bash -n a b" and "ruby -c a b" check only a.
Run the e2e with TMUX unset, as CLAUDE.md requires, so it never touches the tmux server you work in.
This text is public: write commands and log paths with placeholders (/Volumes/YourDrive, $TMPDIR/gate.log),
never with a local path, a drive name or a user name. -->

## Not verified
<!-- What you did not check or could not check, and why. Write "Nothing" only if that is true. -->
