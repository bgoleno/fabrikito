# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# Skills named in a role's prompt.
echo "--- skills named in a role's prompt"
render_em() { ruby $SRC/lib/team_config.rb $T/v.yaml render em 2>&1; }
accept "skills by name and with a note" "" "" ', skills: [code-review, { "superpowers:test-driven-development": "before writing implementation code" }]'
out=$(render_em)
echo "$out" | grep -qxF -- '- `code-review`' && echo "$out" | grep -qxF -- '- `superpowers:test-driven-development`: before writing implementation code' \
  && ok "the rendered prompt lists each configured skill, with its note" || { bad "skills in the rendered prompt"; echo "$out"; }
# Nothing is assumed installed: the section says a listed skill may be absent, and what to do then.
echo "$out" | grep -qF "if it is installed" && echo "$out" | grep -qF "If one is not installed, work without it" \
  && ok "the skills section holds when a skill is not installed" || { bad "skills wording"; echo "$out"; }
[ "$(echo "$out" | grep -n -xF 'p' | cut -d: -f1)" -lt "$(echo "$out" | grep -n -xF '## Skills' | cut -d: -f1)" ] 2>/dev/null \
  && ok "the skills section follows the role's own prompt" || { bad "skills section position"; echo "$out"; }
ruby $SRC/lib/team_config.rb $SRC/teams/example.yaml render fs1 2>&1 | grep -qF -- '- `superpowers:test-driven-development`: ' \
  && ok "the example team names skills in an engineer's prompt" || bad "the example team names skills in an engineer's prompt"
mk ""; render_em | grep -q "Skills" && bad "a role without skills gets a skills section" || ok "a role without skills gets no skills section"
reject "skills that are not a list" "roles.em.skills must be a list" "" "" ", skills: code-review"
reject "a skill name with a space" "roles.em.skills: 'code review' is not a skill name" "" "" ', skills: ["code review"]'
reject "a skill listed twice" "roles.em.skills: 'code-review' is listed twice" "" "" ", skills: [code-review, code-review]"
reject "a skill entry with two names" "roles.em.skills: a mapping entry must be one skill name and its note" "" "" ', skills: [{ a: "x", b: "y" }]'
reject "a skill note over two lines" "roles.em.skills: the note for 'a' must be one line of text" "" "" ', skills: [{ a: "x\ny" }]'
# A carriage return or other control character would be written raw into the prompt.
reject "a skill note with a carriage return" "roles.em.skills: the note for 'a' must be one line of text" "" "" ', skills: [{ a: "x\ry" }]'
reject "a skill note with an escape character" "roles.em.skills: the note for 'a' must be one line of text" "" "" ', skills: [{ a: "x\ey" }]'
reject "a skill note with a tab" "roles.em.skills: the note for 'a' must be one line of text" "" "" ', skills: [{ a: "x\ty" }]'
# The wrapper claude runs through is protected like factory.sh: a file, or its whole .app bundle.
mk; ws=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em)
echo "$ws" | grep -q "wrap\|\.app" && bad "no wrapper configured, but a wrapper deny was added" || ok "no wrapper configured: no wrapper deny"
# With CLAUDE_CONFIG_DIR set, Claude Code keeps the user's config there, .claude.json included
# (code.claude.com/docs/en/claude-directory), so that folder is protected too. ~/.claude and
# ~/.claude.json stay protected: the owner's sessions started without the variable still load them.
mk; cc=$(CLAUDE_CONFIG_DIR=$T/cfg TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em | ruby -rjson -e 'puts JSON.parse(STDIN.read)["permissions"]["deny"]')
missing=""
for p in settings.json .claude.json CLAUDE.md plugins/** skills/** agents/** commands/** hooks/** rules/**; do echo "$cc" | grep -qxF "Edit(/$RT/cfg/$p)" || missing="$missing $p"; done
[ -z "$missing" ] && ok "CLAUDE_CONFIG_DIR set: the user's config paths, .claude.json included, are built from it" || { bad "CLAUDE_CONFIG_DIR paths missing:$missing"; echo "$cc" | grep cfg; }
missing=""
for p in $RHC/settings.json $RH/.claude.json $RHC/CLAUDE.md "$RHC/plugins/**" "$RHC/skills/**" "$RHC/agents/**" "$RHC/commands/**" "$RHC/hooks/**" "$RHC/rules/**"; do echo "$cc" | grep -qxF "Edit(/$p)" || missing="$missing $p"; done
[ -z "$missing" ] && ok "CLAUDE_CONFIG_DIR set: ~/.claude and ~/.claude.json stay protected too" || bad "CLAUDE_CONFIG_DIR set, default config paths no longer denied:$missing"
echo "$cc" | grep -qxF "Edit(/$RT/cfg/projects/$(enc "$T/repo")/memory/**)" && echo "$cc" | grep -qxF "Edit(/$RHC/projects/$(enc "$T/repo")/memory/**)" &&
  ok "CLAUDE_CONFIG_DIR set: the auto-memory folder is denied under it and under ~/.claude" || { bad "auto-memory folder with CLAUDE_CONFIG_DIR"; echo "$cc" | grep memory; }
# A folder name over 200 characters is cut to 200 with a hash of the path appended, which the
# launcher cannot compute: the deny takes the first 200 and a *. The repo is reached through a long
# link here, so its real path gives a short name too, and both are denied.
LONG=$T/$(printf 'L%.0s' $(seq 1 210)); ln -s $T/repo $LONG
mk; sed -i '' "s#{ path: $T/repo,#{ path: $LONG,#" $T/v.yaml
lm=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em | ruby -rjson -e 'puts JSON.parse(STDIN.read)["permissions"]["deny"]')
long=$(enc "$LONG")
[ ${#long} -gt 200 ] && echo "$lm" | grep -qxF "Edit(/$RHC/projects/${long:0:200}*/memory/**)" && echo "$lm" | grep -qxF "Edit(/$RHC/projects/$(enc "$RT/repo")/memory/**)" &&
  ok "auto-memory folder: a name over 200 characters is denied by its first 200 and a *, the real path's short name too" || { bad "auto-memory folder, long name"; echo "$lm" | grep memory; }
# The seat uses the folder its rules protect: the launch script pins CLAUDE_CONFIG_DIR, or unsets it.
grep -qx "unset CLAUDE_CONFIG_DIR" $T/state/launch/em.sh && ok "unset when up ran: the launch script unsets CLAUDE_CONFIG_DIR" || { bad "launch script without CLAUDE_CONFIG_DIR"; grep CLAUDE_CONFIG_DIR $T/state/launch/em.sh; }
CLAUDE_CONFIG_DIR=$T/cfg TEAM_STATE_DIR=$T/state3 TEAM_VIEW=0 $S -c $T/v.yaml up --no-view >/dev/null 2>&1
grep -qx "export CLAUDE_CONFIG_DIR=$T/cfg" $T/state3/launch/em.sh && ok "set when up ran: the launch script exports that CLAUDE_CONFIG_DIR" || { bad "launch script with CLAUDE_CONFIG_DIR"; grep CLAUDE_CONFIG_DIR $T/state3/launch/em.sh 2>&1; }
TEAM_STATE_DIR=$T/state3 $S -c $T/v.yaml down --yes >/dev/null 2>&1
ln -s $T/bin $T/linkbin; mk "wrapper: $T/linkbin/wrap"; ws=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em)
echo "$ws" | grep -qF "\"Edit(/$T/linkbin/wrap)\"" && echo "$ws" | grep -qF "\"Edit(/$RT/bin/wrap)\"" && ok "a wrapper reached through a symlinked folder: the link path and the real path are both denied" || { bad "symlinked wrapper"; echo "$ws" | grep -i wrap; }
mk "wrapper: $T/Wrap.app/Contents/MacOS/Wrap"; ws=$(TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em)
echo "$ws" | grep -qF "\"Edit(/$RT/Wrap.app/**)\"" && ok "a wrapper inside an .app: Edit deny on the whole bundle" || { bad "wrapper .app deny"; echo "$ws" | grep -i wrap; }
mk "permission_mode: dontAsk" "$(rule ask '"Bash(rm *)"')"
$S -c $T/v.yaml check 2>&1 | grep -qF "ask rules are refused in dontAsk" && ok "check: ask-becomes-deny note under dontAsk" || bad "check: dontAsk note"
mk; sed -i '' 's#github: local/origin.git }#github: local/origin.git, base: main }#' $T/v.yaml
nb=$($S -c $T/v.yaml check 2>&1); TEAM_STATE_DIR=$T/state ruby $SRC/lib/team_config.rb $T/v.yaml settings em | grep -q "git push" && bad "base without a remote still produced push rules" || { echo "$nb" | grep -qF "no base-branch push rules" && ok "repo.base without a remote: no push rules, and check says so" || { bad "check: no base-branch note"; echo "$nb" | tail -3; }; }
mk "args: [--dangerously-skip-permissions]"
lg=$($S -c $T/v.yaml check 2>&1) && echo "$lg" | grep -qE "^em .* bypassPermissions \(args\)" && ok "legacy: --dangerously-skip-permissions in args with no mode still loads; check shows bypassPermissions (args)" || { bad "legacy args file"; echo "$lg" | tail -4; }
e2e_end=skills # the last line: test/e2e.sh checks that the file ran to here
