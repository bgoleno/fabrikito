# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# Rendered prompt budget, effort per role, locale.
echo "--- rendered prompts stay short"
# Every line of a seat's prompt is loaded on every task; the best-practice guidance is to stay under
# about 200 lines and move procedures into skills. Measured on the example team, which uses the
# shipped roles/ prompts. A project's own prompts add to these, so this leaves them room.
for r in $(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml ids); do
  n=$(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render "$r" 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] && [ "$n" -lt 200 ] && ok "example seat $r renders a prompt under 200 lines ($n)" || bad "example seat $r renders a prompt of ${n:-?} lines (limit 199)"
done
# em's prompt is the longest and the one most often added to: #117 brought it to 180 lines or fewer,
# so the next change to it has room. Make room by moving procedure out, not by raising this.
n=$(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render em 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -gt 0 ] && [ "$n" -le 180 ] && ok "example seat em renders at most 180 lines ($n)" || bad "example seat em renders ${n:-?} lines (limit 180, #117)"
# A push chained with other commands can be matched as one text, when Claude Code cannot split it
# (an expansion or heredoc in a later part): `git push origin <feature>; gh pr create --base main
# --body "$(cat <<EOF ...)"` then hits the base-branch ask through the later `main` (#91, #103).
flat=$(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render fs1 2>&1 | tr '\n' ' ' | tr -s ' ')
# The push names its refspec, and the branch is cut without tracking: a branch cut with
# `git switch -c <b> origin/main` has the base as its upstream, so under push.default=upstream a bare
# `git push` (or `git push origin <b>`) would go to the base branch (sec, #117).
echo "$flat" | grep -qF 'run `git push origin <branch>:<branch>` as a command of its own, never chained' && echo "$flat" | grep -qF '`gh pr create --base <base>`' \
  && echo "$flat" | grep -qF '`git switch --no-track -c <branch> origin/main`' \
  && ok "the shared prompt says to run git push origin <branch>:<branch> alone, never chained (gh pr create named), on a branch cut with --no-track" || bad "the shared prompt does not say to run git push origin <branch>:<branch> alone, or to cut with --no-track"
echo "--- the example team sets effort per role"
# Effort is the main cost and depth control: the manager coordinates at medium, the seats that
# write, test and review code run at high. Read from the flags each seat would be launched with.
for pair in em:medium tl:high fs1:high fs2:high qa:high sec:high; do
  r=${pair%%:*}; want=${pair#*:}
  got=$(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml claude_args "$r" 2>&1 | grep -A1 -x -- --effort | tail -1)
  [ "$got" = "$want" ] && ok "example seat $r launches with --effort $want" || bad "example seat $r launches with --effort '${got}' (want $want)"
done
echo "--- prompts render the same whatever the locale"
# Under LC_ALL=C, or with no locale at all (cron, env -i), ruby would read files as US-ASCII and the
# first non-ASCII byte in a prompt would stop the render (#72). The output must not depend on it.
# env -i drops TEAM_SCRIPT, TEAM_LOG and TEAM_STATE_DIR, which the prompts name (the state folder
# through @@NOTE@@), so every run gets the same values.
pin="TEAM_SCRIPT=factory.sh TEAM_LOG=messages.log TEAM_STATE_DIR=$T/state"
for r in $(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml ids); do
  want=$(env $pin LC_ALL=en_US.UTF-8 ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render "$r" 2>&1)
  c=$(env $pin LC_ALL=C ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render "$r" 2>&1); rc=$?
  none=$(env -i PATH="$PATH" HOME="$HOME" $pin ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render "$r" 2>&1); rn=$?
  [ $rc = 0 ] && [ $rn = 0 ] && [ -n "$want" ] && [ "$c" = "$want" ] && [ "$none" = "$want" ] \
    && ok "example seat $r renders the same under LC_ALL=C and with no locale" || { bad "example seat $r under LC_ALL=C (rc=$rc) or no locale (rc=$rn)"; echo "$c" | tail -2; }
done
e2e_end=prompts # the last line: test/e2e.sh checks that the file ran to here
