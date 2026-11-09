# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# up: seats started (w2 refused for its legacy worktree), repo.copy and repo.bootstrap, launch flags; the fabrikito plugin.
# Uses the setup in test/e2e.sh. Leaves em and w1 running, and sets RWT1 and PLUG for later areas.
echo "--- up (w2 has a legacy worktree, expect it to be refused)"
out=$($S -c $T/team.yaml up --no-view 2>&1); echo "$out" | grep -E "start|error|ATTENTION" | cut -c1-170
echo "$out" | grep -q "start  w1" && ok "w1 started" || bad "w1 started"
echo "$out" | grep -q "migrate w2" && ok "w2 refused with migrate hint" || bad "w2 refused with migrate hint"
case "$(git -C $T/repo worktree list)" in *"$VOL/$ROOT/team-w1"*) ok "w1 worktree is on the volume";; *) bad "w1 worktree is on the volume";; esac
RWT1=$(cd $VOL/$ROOT/team-w1 2>/dev/null && pwd -P)
[ "$(cat $VOL/$ROOT/team-w1/.env.local 2>/dev/null)" = "SECRET=1" ] && [ "$(cat $VOL/$ROOT/team-w1/conf/dev.json 2>/dev/null)" = '{"dev":true}' ] && ok "repo.copy: w1's new worktree has .env.local and conf/dev.json from the main checkout" || { bad "repo.copy into w1"; ls -la $VOL/$ROOT/team-w1 2>&1 | head; }
grep -qE "^w1 $RWT1 env=yes repo=.*/repo$" $T/boot.log && ok "repo.bootstrap ran in w1's new worktree, after the copy, with TEAM_ROLE and TEAM_REPO" || { bad "repo.bootstrap in w1"; cat $T/boot.log 2>&1; }
echo "$out" | grep -qF "repo.copy: $T/repo/missing.txt does not exist" && ok "repo.copy warns about a missing file and goes on" || { bad "repo.copy missing-file warning"; echo "$out" | grep -i copy; }
! grep -q "^em " $T/boot.log && ok "repo.bootstrap does not run for a project workdir (em)" || bad "repo.bootstrap ran for em"
[ "$(cat $T/state/setup/w1 2>/dev/null)" = "$RWT1" ] && [ ! -e $T/state/setup/em ] && ok "the setup of w1's new worktree is marked done once copy and bootstrap finished (none for em)" || { bad "setup mark for w1"; ls -la $T/state/setup 2>&1; }
sleep 3
grep -q "^w1 .*--model sonnet --effort low" $T/args.log && ok "w1 launched with --model sonnet --effort low" || { bad "w1 args"; cat $T/args.log; }
PLUG=$(cd $SRC/plugin && pwd -P)
grep -qF "em --permission-mode bypassPermissions --plugin-dir $PLUG --settings $T/state/settings/em.json -n tt-em" $T/args.log && ok "em launched with the team mode, the fabrikito plugin, its settings file, no --model/--effort (inherit)" || { bad "em args"; cat $T/args.log; }
grep -qF "w1 --model sonnet --effort low --permission-mode default --plugin-dir $PLUG --settings $T/state/settings/w1.json -n tt-w1" $T/args.log && ok "w1 launched with its own mode (default) and its settings file" || { bad "w1 mode/settings args"; cat $T/args.log; }
grep -E "^(em|w1) " $T/args.log | grep -c -- "--effort" | grep -q '^1$' && ok "only w1 got --effort" || bad "only w1 got --effort"
echo "--- fabrikito plugin"
# The plugin each seat loads: a manifest named fabrikito and the placeholder skill that proves loading.
ruby -rjson -e 'exit(JSON.parse(File.read(ARGV[0]))["name"] == "fabrikito" ? 0 : 1)' $SRC/plugin/.claude-plugin/plugin.json 2>/dev/null && ok "plugin.json parses and names the plugin fabrikito (skills are /fabrikito:<skill>)" || bad "plugin.json"
grep -qx "name: ping" $SRC/plugin/skills/ping/SKILL.md 2>/dev/null && ok "the placeholder skill skills/ping exists" || bad "skills/ping/SKILL.md"
# Every skill in the plugin, checked here once so a PR that adds a skill adds no test code (#17). The
# frontmatter parses; name is the folder's name; the description is one line of at most 300 characters
# (it sits in every seat's skill list, so it costs context everywhere); no @@PLACEHOLDER@@ is left
# (skills are not rendered); a skill only the owner may start sets disable-model-invocation; and no skill
# has allowed-tools unless it is listed here, since that lets it use those tools without asking in every
# seat. Names of projects or people cannot be told apart generically: the pre-commit git grep covers them.
skl=$(ruby -ryaml -e '
  owner_only = %w[merge-train]
  may_allow_tools = %w[]
  errs = []; n = 0
  Dir[File.join(ARGV[0], "skills", "*", "SKILL.md")].sort.each do |f|
    s = File.basename(File.dirname(f)); t = File.read(f); n += 1
    m = t.match(/\A---\n(.*?)\n---\n/m)
    fm = m && (YAML.safe_load(m[1]) rescue nil)
    unless fm.is_a?(Hash) then errs << "#{s}: no frontmatter that parses"; next end
    errs << "#{s}: name is #{fm["name"].inspect}, not the folder name" unless fm["name"] == s
    d = fm["description"]
    errs << "#{s}: description must be one line of 1 to 300 characters" unless d.is_a?(String) && !d.strip.empty? && !d.include?("\n") && d.length <= 300
    errs << "#{s}: an @@PLACEHOLDER@@ is left" if t =~ /@@[A-Z_]+@@/
    errs << "#{s}: owner-only, needs disable-model-invocation: true" if owner_only.include?(s) && fm["disable-model-invocation"] != true
    errs << "#{s}: allowed-tools needs review (add the skill to may_allow_tools in test/e2e/launch.sh)" if fm.key?("allowed-tools") && !may_allow_tools.include?(s)
  end
  errs << "no skills found" if n.zero?
  puts errs.empty? ? "ok #{n}" : errs' $SRC/plugin 2>&1)
case $skl in "ok "*) ok "every plugin skill has valid frontmatter, a one-line description, no placeholder (${skl#ok } skills)" ;; *) bad "plugin skills"; echo "$skl" ;; esac
# Each fabrikito skill the example team names in a role's skills: exists in the plugin.
miss=""; for x in $(grep -o 'fabrikito:[a-z][a-z0-9-]*' $SRC/teams/example.yaml | sort -u); do [ -f "$SRC/plugin/skills/${x#fabrikito:}/SKILL.md" ] || miss="$miss $x"; done
[ -z "$miss" ] && grep -q '"fabrikito:assign"' $SRC/teams/example.yaml && ok "every fabrikito skill named in teams/example.yaml exists in plugin/skills" || bad "example.yaml names missing fabrikito skills:$miss"
# args.log holds each launch line followed by the multi-line prompt, so each seat's line is found by its role.
pd() { grep -E "^$1 " $T/args.log | grep -o -- "--plugin-dir [^ ]*"; }
[ "$PLUG" = "$(cd $SRC && pwd -P)/plugin" ] && [ "$(pd em)" = "--plugin-dir $PLUG" ] && [ "$(pd w1)" = "--plugin-dir $PLUG" ] && ok "every seat got --plugin-dir once, with the real path of <install>/plugin" || { bad "--plugin-dir per seat"; cat $T/args.log; }
$S -c $T/team.yaml check 2>&1 | grep -qxF "plugin    : $PLUG (skills as /fabrikito:<skill>)" && ok "check: plugin header shows the loaded plugin" || { bad "check: plugin header"; $S -c $T/team.yaml check 2>&1 | head -10; }
echo "--- factory.sh shim (deprecated name, #261)"
# The old name runs fabrikito with the same arguments and exit status, and says on stderr that it is deprecated.
shim_new=$($S -c $T/team.yaml check 2>/dev/null); shim_new_rc=$?
shim_old=$($SRC/factory.sh -c $T/team.yaml check 2>$T/shim.err); shim_old_rc=$?
[ "$shim_old_rc" = "$shim_new_rc" ] && [ -n "$shim_old" ] && [ "$shim_old" = "$shim_new" ] && ok "shim: factory.sh check prints what fabrikito check prints, with the same exit status" || { bad "shim: same output and status"; echo "$shim_old_rc vs $shim_new_rc"; }
[ "$(cat $T/shim.err)" = "factory.sh is deprecated; use fabrikito" ] && ok "shim: factory.sh prints the deprecation notice on stderr, one line" || { bad "shim: deprecation notice"; cat $T/shim.err; }
[ -z "$(echo "$shim_old" | grep -F 'deprecated')" ] && ok "shim: the notice is not on stdout" || bad "shim: notice leaked to stdout"
$SRC/factory.sh -c $T/team.yaml nosuchcommand >/dev/null 2>&1; shim_old_bad=$?
$S -c $T/team.yaml nosuchcommand >/dev/null 2>&1; shim_new_bad=$?
[ "$shim_new_bad" != 0 ] && [ "$shim_old_bad" = "$shim_new_bad" ] && ok "shim: a failing command exits with the same non-zero status through factory.sh" || bad "shim: failing exit status ($shim_old_bad vs $shim_new_bad)"
# Called through a symlink, from another folder: it still finds fabrikito next to the real file, and a relative link works too.
mkdir -p $T/shimlink/sub && ln -s $SRC/factory.sh $T/shimlink/abs.sh && ln -s ../abs.sh $T/shimlink/sub/rel.sh
shim_abs=$(cd / && $T/shimlink/abs.sh -c $T/team.yaml check 2>/dev/null); shim_rel=$(cd /tmp && $T/shimlink/sub/rel.sh -c $T/team.yaml check 2>/dev/null)
[ "$shim_abs" = "$shim_new" ] && [ "$shim_rel" = "$shim_new" ] && ok "shim: works through an absolute and a relative symlink, from another folder" || bad "shim: symlink or other cwd"
# fabrikito itself through a symlink to its file (#263): an absolute link, a relative one, a chain of links
# (one relative, one absolute), each from another folder, finds lib/ and prints what a direct run prints.
mkdir -p $T/selflink/sub $T/selflink/deep && ln -s $SRC/fabrikito $T/selflink/abs && ln -s ../abs $T/selflink/sub/rel && ln -s $T/selflink/sub/rel $T/selflink/deep/chain && ln -s ../deep/chain $T/selflink/sub/chain2
self_direct=$($S -c $T/team.yaml check 2>/dev/null)
for sl in abs sub/rel deep/chain sub/chain2; do
  self_out=$(cd / && $T/selflink/$sl -c $T/team.yaml check 2>&1); self_rc=$?
  [ "$self_rc" = 0 ] && [ -n "$self_direct" ] && [ "$self_out" = "$self_direct" ] && ok "fabrikito through a symlink ($sl) finds lib/ and prints what a direct run prints" || { bad "fabrikito through a symlink ($sl) (rc=$self_rc)"; echo "$self_out" | tail -3; }
done
self_rel=$(cd $T/selflink/sub && ./rel -c $T/team.yaml check 2>&1)
[ "$self_rel" = "$self_direct" ] && ok "fabrikito through a relative link, run from the link's own folder" || bad "fabrikito through a relative link from its own folder"
# A relative link whose target goes up through a symlinked folder (dl/../rel2): the kernel resolves the .. in the
# folder dl points at, so the resolver must use the physical folder (cd -P), not the path as written (#263).
mkdir -p $T/selflink/real/a $T/selflink/L/m && ln -s ../abs $T/selflink/real/rel2 && ln -s $T/selflink/real/a $T/selflink/L/m/dl && ln -s dl/../rel2 $T/selflink/L/m/k
self_dl=$(cd / && $T/selflink/L/m/k -c $T/team.yaml check 2>&1); self_dl_rc=$?
[ "$self_dl_rc" = 0 ] && [ "$self_dl" = "$self_direct" ] && ok "fabrikito through a relative link whose target goes up through a symlinked folder" || { bad "fabrikito through dl/../rel2 (rc=$self_dl_rc)"; echo "$self_dl" | tail -3; }
e2e_end=launch # the last line: test/e2e.sh checks that the file ran to here
