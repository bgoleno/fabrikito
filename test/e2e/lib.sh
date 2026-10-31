# Sourced by test/e2e.sh, in its shell and in the order of AREAS there (#70); not run alone.
# Helpers that more than one area uses. A helper one area uses stays in that area.
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
am() { ruby -rjson -e 's = JSON.parse(STDIN.read); puts [s["autoMemoryEnabled"].inspect, s.dig("env", "CLAUDE_CODE_DISABLE_AUTO_MEMORY").inspect].join(" ")'; }
# A minimal valid team file; $1 is the sessions.claude body, $2 extra top-level lines, $3 extra keys for role em.
mk() {
  cat > $T/v.yaml <<Y
team: tv
repo: { path: $T/repo, github: local/origin.git${REPO_EXTRA:+, $REPO_EXTRA} }
project: { name: B, url: "https://github.com/users/x/projects/9" }
storage: { volume: $VOL, root: $ROOT }
sessions: { prefix: tv, claude: { ${1:-} } }
${2:-}
roles:
  em: { title: M, workdir: { type: project, path: $T/proj }, prompt_text: "p" ${3:-} }
Y
}
# reject <what> <expected message> <mk args...>
reject() {
  local what=$1 msg=$2 out rc; shift 2; mk "$@"
  out=$($S -c $T/v.yaml check 2>&1); rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$msg"; then ok "rejects $what"; else bad "rejects $what (rc=$rc)"; echo "$out" | tail -2; fi
}
# accept <what> <mk args...>
accept() {
  local what=$1 out; shift; mk "$@"
  if out=$($S -c $T/v.yaml check 2>&1); then ok "accepts $what"; else bad "accepts $what"; echo "$out" | tail -2; fi
}
rule() { echo "permissions: { $1: [$2] }"; }
