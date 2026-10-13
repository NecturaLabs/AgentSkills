# Independent review of filed issues

A reviewer that did not write the issues checks every claim in them against the code, then fixes
what it finds in the issues themselves. Reporting a finding without editing the issue is not this
review. The writer's own read-back is not this review either; it is step 3 of the process.

## When

After filing or substantially rewriting issues, before anyone builds from them; several issues
filed in one task share one review. Also when an issue's facts look stale, or an owner decision
changed what several issues say. Progress notes, label corrections and closing need the read-back
only.

## Who

A separate context with no part in writing the issues: a subagent or reviewer the harness provides,
at a strong tier for the depth this needs. When no separate context is allowed, the writer reviews
against this file and labels the result a self-review, never an independent one. A reviewer
receives the issue numbers, the standards, the owner's decisions as the owner stated them, and
pointers to the code and docs; it does not receive the writer's conclusions about whether the
issues are right.

## Brief

State: the repository and the issue numbers (and related issues touched); that it edits issues,
labels, titles and comments only, never code or documentation, and builds or runs nothing (reading
scripts is allowed); which files to read first (the project's instruction files, its contribution
guide, this skill's standards, its ADRs and design docs); the owner decisions to keep, verbatim,
reworded for clarity only; what the owner wants every issue to contain beyond the standard; the
subject groups the writer knows of; what it may do (edit bodies, titles, labels, link and comment,
split into a new issue, close an exact duplicate as not planned with a link and `duplicate`) and
may not (close anything else, change the owner's decisions); where to put its working files
(outside the repository); and the report it returns.

## Procedure

Every step leaves its output in the working notes; a step without its output was not done.

1. **Snapshot.** Before any edit, save every issue in the batch and every older issue it may touch:
   title, labels, state, body and comments, one file per issue. Output: the originals.
2. **Read the whole batch** before verifying or editing any of it, and list the subject groups:
   issues that share code, a setting, wording, tokens or a decision. Output: the checklist, with
   one row per issue and the groups.
3. **Check the routes to see it once for the batch.** Read the screenshot or run script's help
   text and the source that parses it, the list of overlays, views and demo scenarios, and the
   fixture tool, and note what each cannot stage (environment variables it clears, pointer and
   hover states, missing remotes). Output: the valid commands and their limits.
4. **Verify each issue, claim by claim.** List every path, symbol, line number, behaviour,
   count, quoted string, command, issue reference and proposed addition in the body, and check
   each one as the issue standards' "What counts as verified" table says: search for it, read the
   code around it, follow the path from trigger to result, fetch each cited issue's title and
   state. Output per claim: verified, corrected (old → new, with the symbol or command that showed
   it), removed, or not verified (where you looked).
5. **Add what the issue lacks.** Where it is vague about what to build, derive the set from the
   code and write it in: the table of values with their source symbols, the call sites with the
   search and its scope, the current layout or order, the existing mechanism it would duplicate.
   Add missing constraints (product rules, ADRs to amend, legal text, security pass, documents
   that state the rule being changed), and a test criterion for every defect found while checking.
   Output: the material, in the notes before it goes into the issue.
6. **Check the batch against the backlog.** Search open and closed issues for each subject with
   several phrasings (the feature, the symptom, the setting name), read the bodies of the related
   open issues found, and compare each subject group side by side: terms, values, decisions, who
   owns which part, links both ways. Overlaps become a split or a merge; a duplicate is closed as
   not planned with `duplicate` and a link. Output: the searches run and their verdicts.
7. **Check standard, labels and decisions.** Title, section order and depth; exactly one type,
   area, priority and size, plus `security` and `needs-verification` where they apply; size and
   priority raised or lowered to what step 4 and 5 found, with the reason; anything the issue
   decided that was the owner's to decide, and every conflict between the owner's words and the
   code, written as an open decision with the facts and a recommendation. A type change (a "bug"
   that reverses documented intent is an enhancement) gets its reason in a comment.
8. **Edit** as described below, one issue at a time, ticking its checklist row after the read-back.
9. **Sweep the batch.** Re-read the labels of every issue, the new ones included; search every
   body for remaining line-number references and check each against the code; confirm each split
   and supersession is recorded on both sides. Output: the sweep result in the checklist.

## Working notes

Kept outside the repository so a stop loses nothing: the originals (step 1), every body as pushed,
the edit scripts, and the checklist. The checklist holds the brief in short, then per issue what
was verified, what was corrected and why, what is still to do, and the material derived but not
yet written into an issue (step 5), in a form that can be pasted. It is updated after each issue
is pushed, not at the end, so the same reviewer resumed, or another one, continues from it.

## How it edits

Fetch the issue's current body immediately before editing, never from the snapshot, so a change
made meanwhile is kept. Apply changes to that copy as exact-match replacements that fail loudly
when the expected text is missing, write the result to a file, and push the file as the body.
Then read the issue back and compare it with the file pushed (whitespace at the end aside), and
search it for the new text. The body is the current truth, in the standard's section order: keep
the owner's decisions and every unresolved requirement; trim only filler. A new issue only for a
clean split, done as the standard's split rule says; a comment only for history that should stay
visible (a split, a priority change, a decision that changes another issue).

## Stopping and resuming

Asked to stop, the reviewer pushes only the corrections it has already verified, never a
half-checked one; writes everything else it has derived into the checklist; and reports what is
done and what remains. Resumed, it reads the checklist and continues from it without re-deriving
what it records. Whoever dispatched it resumes the same reviewer for the rest rather than starting
another that rebuilds the context, unless the owner says otherwise. A reviewer the owner has
stopped, resumed or messaged is theirs: leave it alone and wait for its report.

## Report

Per issue: `ok`, or the list of changes (title, labels with the reason, sections, links) with every
factual correction and what was wrong. Then: issues split, merged or closed, and comments added;
each claim not verified and where it looked; how the edits were confirmed (full read-back or
spot check); the limits of any count (text matching misses indirect calls); and the open owner
decisions, each with the facts and a recommendation. The writer relays this report and does not
resend what the reviewer fixed.
