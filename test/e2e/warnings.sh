# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# check's warnings: held seat-to-seat messages (#36), merging (#58).
echo "--- check warnings: held seat-to-seat messages (#36) and merging (#58)"
# held <what> <expect: yes|no|note> : runs check on v.yaml and looks for the held-message lines.
held() {
  local out; out=$($S -c $T/v.yaml check 2>&1) || { bad "$1: check failed"; echo "$out" | tail -2; return; }
  case $2 in
    yes) echo "$out" | grep -qF "warning: seat-to-seat messages will be held. Prompting for permissions: $3. Bypassing them: $4." && echo "$out" | grep -qF "from a bypass seat to a prompting seat, and from a prompting seat to a bypass seat" && ok "$1: warns, naming each class and both directions" || { bad "$1: held warning"; echo "$out" | grep -A2 -E "^(warning|note)"; } ;;
    no) echo "$out" | grep -qE "^(warning: seat-to-seat|note: check cannot see)" && { bad "$1: unexpected held warning"; echo "$out" | grep -A2 -E "^(warning|note)"; } || ok "$1: no held-message warning" ;;
    note) echo "$out" | grep -qF "note: check cannot see the permission mode of $3 (inherited from settings)" && ! echo "$out" | grep -qF "warning: seat-to-seat" && ok "$1: notes the seats whose mode check cannot see, without a warning" || { bad "$1: inherit note"; echo "$out" | grep -A2 -E "^(warning|note)"; } ;;
  esac
}
w9() { echo "  w9: { title: N, workdir: { type: project, path: $T/proj }, prompt_text: \"p\"${1:+, $1} }" >> $T/v.yaml; }
# The merge spellings tl chose in #85, in MERGE_PATTERNS order: as a YAML list (guard), and as
# check names them (all; rest is all but the first).
guard='"Bash(gh pr merge *)", "Bash(gh pr -* merge *)", "Bash(gh pr -* merge)", "Bash(gh api *pulls/*/merge*)", "Bash(gh api *repos/*/merges*)", "Bash(gh api graphql*mergePullRequest*)", "Bash(gh api graphql*enablePullRequestAutoMerge*)", "Bash(gh api graphql*mergeBranch*)"'
rest='Bash(gh pr -* merge *), Bash(gh pr -* merge), Bash(gh api *pulls/*/merge*), Bash(gh api *repos/*/merges*), Bash(gh api graphql*mergePullRequest*), Bash(gh api graphql*enablePullRequestAutoMerge*), Bash(gh api graphql*mergeBranch*)'
all="Bash(gh pr merge *), $rest"
mk "permission_mode: bypassPermissions" "$(rule ask "$guard")"; w9 "permission_mode: auto"
held "a bypass team with one auto seat" yes "w9 (auto)" "em (bypassPermissions)"
mk "permission_mode: bypassPermissions" "$(rule ask "$guard")"; w9 "permission_mode: plan"
held "plan mode in a role (bypass switched off by its settings)" yes "w9 (plan)" "em (bypassPermissions)"
mk "permission_mode: auto" "$(rule ask "$guard")" ", permission_mode: bypassPermissions"; w9 "permission_mode: dontAsk"
held "a role in bypass on an auto team" yes "w9 (dontAsk)" "em (bypassPermissions)"
mk "permission_mode: auto" "$(rule ask "$guard")"; w9 "permission_mode: acceptEdits"
held "auto and acceptEdits (one class)" no
mk "permission_mode: bypassPermissions" "$(rule ask "$guard")"; w9
held "every seat in bypass" no
mk "" "$(rule ask "$guard")"; w9
held "every seat inheriting its mode" no
mk "" "$(rule ask "$guard")"; w9 "permission_mode: auto"
held "one seat inheriting beside one with a mode" note "em"
# Merging: every role needs a deny or an ask on each merge pattern, unless it may merge.
mo=$(ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml warnings 2>&1)
[ -z "$mo" ] && ok "the example team as shipped has no warnings" || { bad "example team warnings"; echo "$mo"; }
mk "permission_mode: auto" "$(rule deny "$guard")"; w9
$S -c $T/v.yaml check 2>&1 | grep -qF "warning: " && bad "team-wide merge deny: unexpected warning" || ok "a team-wide deny on the merge patterns: no merge warning"
mk "permission_mode: auto" "" ", permissions: { ask: [$guard] }"; w9
mw=$($S -c $T/v.yaml check 2>&1)
echo "$mw" | grep -qF "warning: w9 could merge a PR without being asked: no deny or ask rule matches $all." && ! echo "$mw" | grep -q "warning: em could merge" && ok "a role added without a merge deny or ask is named, with every missing pattern" || { bad "merge warning for w9"; echo "$mw" | grep warning; }
mk "permission_mode: auto" "" ", permissions: { ask: [$guard] }"; w9 "may_merge: true"
$S -c $T/v.yaml check 2>&1 | grep -qF "could merge" && bad "may_merge: true still warned" || ok "a role marked may_merge: true is not warned about"
mk "permission_mode: auto" "" ', permissions: { deny: ["Bash(gh pr merge *)"] }'
mw=$($S -c $T/v.yaml check 2>&1)
echo "$mw" | grep -qF "no deny or ask rule matches $rest. " && ok "a partial merge deny: only the patterns still open are named" || { bad "partial merge deny"; echo "$mw" | grep warning; }
mk "permission_mode: auto" "" ', permissions: { deny: ["Bash(gh *)"] }'
$S -c $T/v.yaml check 2>&1 | grep -qF "could merge" && bad "a broader deny (Bash(gh *)) still warned" || ok "a broader rule that covers the patterns (Bash(gh *)) counts"
mk "permission_mode: auto" "" ', permissions: { deny: ["Bash(gh pr merge 12*)", "Bash(gh api repos/x/y/pulls/1/merge*)", "Bash(gh api graphql -f q=mergePullRequest*)"] }'
$S -c $T/v.yaml check 2>&1 | grep -qF "warning: em could merge a PR without being asked: no deny or ask rule matches $all." && ok "narrower rules that leave other merges open do not count" || bad "narrower merge rules counted as covering"
# The legacy :* form keeps the space before *: Bash(ls:*) is Bash(ls *) (permissions docs), so a rule
# that stops mid-word covers nothing here, and the whole-word ones still cover.
mk "permission_mode: auto" "" ', permissions: { deny: ["Bash(gh pr mer:*)", "Bash(gh ap:*)", "Bash(gh api graphq:*)"] }'
$S -c $T/v.yaml check 2>&1 | grep -qF "warning: em could merge a PR without being asked: no deny or ask rule matches $all." && ok "legacy :* rules that stop mid-word (gh pr mer:*, gh ap:*, gh api graphq:*) do not count" || bad "legacy mid-word :* rules counted as covering"
mk "permission_mode: auto" "" ', permissions: { deny: ["Bash(gh pr merge:*)", "Bash(gh pr -* merge:*)", "Bash(gh pr -* merge)", "Bash(gh api:*)"] }'
$S -c $T/v.yaml check 2>&1 | grep -qF "could merge" && bad "whole-word legacy rules (gh pr merge:*, gh pr -* merge:*, gh api:*) not counted" || ok "whole-word legacy :* rules (gh pr merge:*, gh pr -* merge:*, gh api:*) count"
reject "a non-boolean may_merge" "roles.em.may_merge must be true or false" "" "" ", may_merge: yes please"
# Which commands the example team's merge rules catch (#85), through matching_rules, which reads a
# rule as the permissions docs describe it. tl denies; em has the team-wide ask.
mr() { ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml matching_rules "$@"; }
spell() { local want=$1; shift; [ "$(mr tl "$1")" = "deny $want" ] && ok "merge spelling caught: $1 (deny $want)" || { bad "merge spelling not caught as $want: $1"; mr tl "$1"; }; }
spell 'Bash(gh pr merge *)' 'gh pr merge 5 --squash'
spell 'Bash(gh pr merge *)' 'gh pr merge'
spell 'Bash(gh pr -* merge *)' 'gh pr -R o/r merge 5'
spell 'Bash(gh pr -* merge *)' 'gh pr --repo o/r merge 5'
spell 'Bash(gh pr -* merge *)' 'gh pr --repo=o/r merge 5 --squash'
spell 'Bash(gh pr -* merge)' 'gh pr -R o/r merge'
spell 'Bash(gh api *pulls/*/merge*)' 'gh api -X PUT repos/o/r/pulls/5/merge'
spell 'Bash(gh api *repos/*/merges*)' 'gh api -X POST repos/o/r/merges -f base=main -f head=x'
spell 'Bash(gh api graphql*mergePullRequest*)' 'gh api graphql -f query="mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }"'
spell 'Bash(gh api graphql*enablePullRequestAutoMerge*)' 'gh api graphql -f query="mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"x\"}) { clientMutationId } }"'
spell 'Bash(gh api graphql*mergeBranch*)' 'gh api graphql -f query="mutation { mergeBranch(input: {repositoryId: \"x\", base: \"main\", head: \"y\"}) { clientMutationId } }"'
[ "$(mr em 'gh pr -R o/r merge 5')" = "ask Bash(gh pr -* merge *)" ] && ok "merge spelling: em gets the team-wide ask" || { bad "em merge ask"; mr em 'gh pr -R o/r merge 5'; }
for c in 'gh pr comment 83 --body "ready to merge"' 'gh pr view 5 --json mergeable,mergeStateStatus' 'gh pr -R o/r view 5 --json mergeable' 'gh pr comment 83 --body "gh pr merge 5 after review"'; do
  [ -z "$(mr tl "$c")" ] && ok "innocent command not caught: $c" || { bad "innocent command caught: $c"; mr tl "$c"; }
done
# A quoted "yes" is a string, not a boolean. (An unquoted yes is YAML 1.1's true, and is accepted.)
reject "a quoted \"yes\" for may_merge" "roles.em.may_merge must be true or false" "" "" ', may_merge: "yes"'
e2e_end=warnings # the last line: test/e2e.sh checks that the file ran to here
