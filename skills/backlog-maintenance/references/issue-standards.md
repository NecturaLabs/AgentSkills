# Issue standards

## Title and body

- **Title**: specific and action-oriented, with no type or priority prefix ("Select the row a
  context menu acts on when right-clicking", not "Bug: menu").
- **Body**, in this order, omitting a section that has nothing true to say:
  - *Problem* or *Deliverable*: what is wrong, or what must exist, in plain terms.
  - For a bug: *Observed behaviour*, *Expected behaviour*, *Steps to reproduce*, and the
    environment when known (version, platform, configuration).
  - *Constraints*: the relevant files, interfaces, decisions and limits.
  - *Acceptance criteria*: a checklist of checkable outcomes, each a statement that passes or
    fails. Add the verification they need (a test, a screenshot, a live check) as a criterion.
- Concise and direct. No vague praise, no restating the title, no summary of the issue at its end.

## Labels

Every triaged issue has exactly one of each, except closed duplicates (`duplicate` and a link to
the canonical issue are enough):

- **Type**: `bug`, `enhancement`, `maintenance`, `documentation`, `verification`, `owner-action`.
- **Area**: one `area:*` label naming the part of the project (git, ui, settings, hosting, ...).
- **Priority** (open issues): `priority:p0-critical`, `priority:p1-high`, `priority:p2-normal`,
  `priority:p3-low`.
- **Size** (open issues, remaining work): `size:small`, `size:medium`, `size:large`,
  `size:needs-estimate`; say why when no estimate is possible.

Extra labels, when they apply: `needs-triage` (new, not yet confirmed; a maintainer removes it after
confirming scope, area, priority and size), `needs-verification` (live, platform or owner checks
remain), `security` (credential, trust, privacy or code-execution risk), `owner-action` (decisions
and external-account tasks only the owner can do).

Keep any label catalogue file in the repository (for example `.github/labels.json`) and the live
labels identical.

## Priority

P0 critical: data loss, security exposure or a broken release. P1 high: a core workflow is
wrong or missing. P2 normal: the default. P3 low: polish and wishes. Work the open issues
P0 first, then in issue-number order within a priority.

## Linking

Reference the issue from the change that implements it (`Closes #N` only when every criterion is
verified, else `Refs #N`), and record on the issue what shipped, what was tested and what remains.
