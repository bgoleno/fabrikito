# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# The security-audit plugin skill (#266): a process-aligned copy of an upstream skill.
echo "--- the security-audit skill"
SA=$SRC/plugin/skills/security-audit
sa_missing=
for sa_f in SKILL.md FABRIKITO-PROCESS.md UPSTREAM.md LICENSE report-schema.json validate-findings.cjs validate-coverage-ledger.cjs \
  validate-findings.test.cjs validate-coverage-ledger.test.cjs HUNTING.md RECONNAISSANCE.md VALIDATION-AND-REPORTING.md ATTACK-CLASSES.md; do
  [ -f "$SA/$sa_f" ] || sa_missing="$sa_missing $sa_f"
done
[ -z "$sa_missing" ] && ok "the security-audit skill folder holds its files" || bad "the security-audit skill folder is missing:$sa_missing"
[ -f "$SRC/THIRD_PARTY_NOTICES.md" ] && grep -qF "Cloudflare, Inc." "$SRC/THIRD_PARTY_NOTICES.md" \
  && ok "the third-party notices name the upstream copyright holder" || bad "THIRD_PARTY_NOTICES.md is missing or lacks the upstream copyright holder"
grep -qxF "Copyright (c) 2025-2026 Cloudflare, Inc." "$SA/LICENSE" && grep -qxF "MIT License" "$SA/LICENSE" \
  && ok "the skill's LICENSE keeps the upstream MIT text and copyright line" || bad "the skill's LICENSE lacks the upstream copyright line"
grep -qF "c1c8a8c1471069fb0e188eeaff69b8e8db6564a8" "$SA/UPSTREAM.md" \
  && ok "the origin note names the pinned upstream commit" || bad "UPSTREAM.md does not name the pinned upstream commit"
sa_fm=$(sed -n '2,/^---$/p' "$SA/SKILL.md")
echo "$sa_fm" | grep -qxF "name: security-audit" && echo "$sa_fm" | grep -q '^description: "For sec only' \
  && ok "the skill's frontmatter names it and starts the description 'For sec only'" || { bad "the skill's frontmatter name or description"; echo "$sa_fm" | head -5; }
grep -qF "(FABRIKITO-PROCESS.md)" "$SA/SKILL.md" && grep -qF "(UPSTREAM.md)" "$SA/SKILL.md" \
  && ok "SKILL.md points to the process overlay and the origin note" || bad "SKILL.md does not point to FABRIKITO-PROCESS.md and UPSTREAM.md"
[ "$(grep -c '^<!-- fabrikito change: see UPSTREAM.md -->$' "$SA/SKILL.md")" -ge 3 ] && grep -qF "# fabrikito change: see UPSTREAM.md" "$SA/SKILL.md" \
  && ok "each SKILL.md change carries the fabrikito change marker" || bad "SKILL.md change markers are missing"
# Edit, not overlay: no file may still carry the upstream output default or the inside-the-target option.
if grep -rnF -e '~/security-audit-skill' -e 'Use a directory inside the target only when' "$SA" >/dev/null; then
  bad "a security-audit file still holds the upstream output default or the inside-the-target option"; grep -rnF -e '~/security-audit-skill' -e 'Use a directory inside the target only when' "$SA" | cut -c1-120
else ok "no security-audit file holds the upstream output default or the inside-the-target option"; fi
grep -qF 'triage/audit/' "$SA/SKILL.md" && grep -qF 'triage/audit/' "$SA/FABRIKITO-PROCESS.md" \
  && ok "the output directory is under the triage state folder in SKILL.md and the overlay" || bad "the output directory text"
# No other role's rendered prompt lists it (checked on the example team, whatever #265 has landed).
sa_others=
for sa_r in $(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["roles"].keys' "$SRC/teams/example.yaml" 2>/dev/null | grep -vx sec); do
  ruby "$SRC/lib/team_config.rb" "$SRC/teams/example.yaml" render "$sa_r" 2>&1 | grep -qF 'fabrikito:security-audit' && sa_others="$sa_others $sa_r"
done
[ -z "$sa_others" ] && ok "no role but sec lists fabrikito:security-audit in the example team" || bad "the example team lists fabrikito:security-audit for:$sa_others"
# The upstream validators' own tests: run when Node exists; a missing Node is a visible SKIP, never a pass.
if command -v node >/dev/null 2>&1; then
  sa_out=$(cd "$SA" && node --test validate-findings.test.cjs validate-coverage-ledger.test.cjs 2>&1); sa_rc=$?
  [ $sa_rc -eq 0 ] && ok "the upstream validators' tests pass under node --test" || { bad "the upstream validators' tests (rc=$sa_rc)"; echo "$sa_out" | tail -15; }
else
  echo "SKIP the upstream validators' tests: node is not installed (not run, not counted as a pass)"
fi
e2e_end=audit # the last line: test/e2e.sh checks that the file ran to here
