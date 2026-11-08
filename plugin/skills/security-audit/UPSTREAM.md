# Where this skill comes from

This folder is a modified copy of the `security-audit` skill from Cloudflare's
[cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill), released under the MIT
License. The license text, with Cloudflare's copyright line, is in [LICENSE](LICENSE). The project's notice
for it is [THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md).

| | |
|---|---|
| Upstream repository | <https://github.com/cloudflare/security-audit-skill> |
| Upstream commit copied | `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8` |
| Date copied | 2026-11-07 |
| Upstream path copied | `skills/security-audit/`, plus `LICENSE` from the repository root |
| Not copied | The upstream repository's root `README.md` |

## What is unchanged

All files except those listed below are byte-identical to upstream's `skills/security-audit/`, plus `LICENSE`
from the repository root. That covers the hunting and reference documents, `report-schema.json`, the two
validators (`validate-findings.cjs`, `validate-coverage-ledger.cjs`) and their tests.

## What changed

Every change to `SKILL.md` is marked in place. In the body the marker is the line
`<!-- fabrikito change: see UPSTREAM.md -->`. In the frontmatter, where an HTML comment does not fit, the
marker is the YAML comment line `# fabrikito change: see UPSTREAM.md`.

| File | Change |
|---|---|
| `SKILL.md` (i) | The frontmatter `description` starts "For sec only" and says that the complete audit needs the owner's say-so through the EM. |
| `SKILL.md` (ii) | A notice under the title says this is a modified copy, points to `FABRIKITO-PROCESS.md` as the file to read first, and links this page. |
| `SKILL.md` (iii) | The "Output directory" bullet under "Full audit setup" puts a run under `<state>/triage/audit/<repo-name>/run-<N>/`, never inside the target and never under a worktree, in place of upstream's default under the home folder and its option to write inside the target. |
| `SKILL.md` (iv) | Two one-line pointers to `FABRIKITO-PROCESS.md`: one under the "Full audit mode" bullet of "Operating modes" (a full audit needs the owner's authorization recorded in `run-metadata.json`), one under item 6, "Target-neutral report", of the "Full audit workflow" list (deliver nothing outside the run folder, and route each finding through `security-triage`). |
| `FABRIKITO-PROCESS.md` | New. The rules this team adds to the upstream workflow. Where it differs from `SKILL.md`, it wins. |
| `UPSTREAM.md` | New. This page. |
| `LICENSE` | Added. Copied unchanged from upstream's repository root. |

## Running the validators' tests

Run this inside this folder:

```
node --test validate-findings.test.cjs validate-coverage-ledger.test.cjs
```

Upstream's README names those two test files and no other test command.

## Updating from upstream

To take a newer upstream version, copy `skills/security-audit/` and `LICENSE` from the new commit, redo the
changes in the table above, and update the commit and date at the top of this page. The e2e test
(`test/e2e/audit.sh`) checks that this page names the pinned commit.
