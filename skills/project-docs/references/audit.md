# Documentation audit

An audit checks whether what the docs claim still matches what the code and commands actually do. A
missing doc leaves a gap someone notices and works around; a wrong doc actively misleads someone who
trusted it. Finding and fixing the second kind is the point of this mode.

Scope the audit to what was actually asked — a request to check one system's docs does not license a
sweep of the whole tree, and a request to audit everything does mean everything in scope, not a
sample.

## Procedure

1. **Find the docs.** Locate every document in scope — the requested directory, or the whole
   documentation tree if that is what was asked. Note anything that looks like documentation but
   lives somewhere unexpected (a stray file, a comment block doing a doc's job) as a candidate for
   relocation, not as a defect on its own.

2. **Extract what each one claims.** For each document, list the concrete, checkable claims it makes:
   named components and how they connect, a documented command and its expected effect, a config
   option's default, a described procedure's steps, a decision's stated status. A claim that cannot
   be checked against anything (pure opinion, a goal statement) is not part of this pass.

3. **Check every claim against the current code.** Read the code, config or schema the claim
   describes and compare. For anything the doc says is true of the running system, verify it is still
   true — a named module still exists at that path, a described flow still executes that way, a field
   still has the stated default.

4. **Run every documented command before trusting it.** A command in a runbook or a reference doc
   that has not been executed is a claim, not a fact. Run it (or, where it is destructive or requires
   access this pass does not have, say so explicitly and report the command as unverified rather than
   as passing) and compare its real output or effect against what the doc says will happen. This is
   the check most audits skip and the one that catches the most damage — a runbook's first command
   failing during an incident is the worst possible time to discover it silently changed.

5. **Check for orphans and duplicates while doing the above.** A document nothing links to and that
   no index or table of contents surfaces is an orphan even if its content is accurate — it will not
   be found when needed. Two documents making the same claim, where one was not updated when the
   other was, are duplicates; the fix is to keep one and point the other at it, not to reconcile both
   forever.

## Classification

Classify every document examined into exactly one of these:

| Class | Meaning |
|---|---|
| **Fine** | Every checked claim holds, commands run as documented, and the document is reachable from wherever a reader would look for it. |
| **Stale** | Was accurate when written; the system moved and the document did not follow. The gap is usually small and mechanical to close. |
| **Wrong** | States something that is not true of the system as built, independent of whether it was ever true — an error, not drift. |
| **Duplicated** | Restates a claim another document already makes, and the two have diverged or are one edit away from doing so. |
| **Orphaned** | Accurate, but unreachable — nothing links to it, and it is not where a reader would look. |

A document can combine classes (stale *and* duplicated); report all that apply rather than forcing a
single label.

## Reporting a finding

For each non-fine document: what is wrong, the specific claim and where the code or command actually
disagrees, and the fix — update, merge into the surviving duplicate, relink, or (only when the thing
it describes is genuinely gone) remove. Do not report "documentation could be improved" without a
specific claim and location; a vague finding cannot be verified as fixed.

Coverage gaps found along the way — a consequential decision with no ADR, a system with no
architecture overview — are worth naming, but they are a finding about what does not exist, not a
defect in an existing document; keep the two separate in the report.
