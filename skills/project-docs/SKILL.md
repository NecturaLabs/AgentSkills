---
name: project-docs
description: Create or maintain durable project documentation: architecture overviews, architecture decision records, design documents, runbooks and reference docs. Use when recording a consequential decision and its rationale, documenting how a system is structured, or auditing documentation that has drifted from the code. Not for code comments, not for explaining code in conversation, and not for AGENTS.md or any other agent-instruction file.
---

# Project Docs

Project documentation is one of three separate layers of knowledge a repository carries: a
persistent-instruction file tells an agent how to behave, a skill carries a conditional procedure,
and a document records a fact about *this* project — how a system is built, why a decision was
made, how to operate it. This skill owns the third layer. It never edits a persistent-instruction
file or a skill; if a task asks for that, say so and stop.

It is also not for explaining something in conversation. A request to understand or walk through
how something works is answered in the reply, with no document created or changed, unless the
person also asks for something durable to be written down.

## Mode classification

| Signal | Mode | Reference |
|---|---|---|
| A consequential, hard-to-reverse decision was made or is being made, and the reasoning needs to survive past this conversation | ADR | `references/adr.md` |
| A system's structure needs a map for someone who has not seen it | Architecture overview | `references/doc-types.md` |
| A design is being worked out, before or during a build, and will keep changing as it does | Design document | `references/doc-types.md` |
| A repeatable operational task or procedure needs steps someone else can follow | Runbook / how-to | `references/doc-types.md` |
| Stable facts — configuration, an API surface, a data model — need to be looked up rather than narrated | Reference documentation | `references/doc-types.md` |
| Existing docs might no longer match the code, config or commands they describe | Documentation audit | `references/audit.md` |

Read only the reference the classification selects. Most tasks need exactly one.

## Where docs live

Follow the project's existing documentation layout if it has one — same directory, same naming, same
depth. Do not restructure it as a side effect of adding one document.

If there is no existing layout, scale it to the size of the project:

- A small repository gets a small tree — a handful of files directly under a `docs/` directory, or
  even a single file, is correct and complete. Do not scaffold `decisions/`, `design/`, `guides/` and
  `reference/` subdirectories up front on the promise that they will eventually be needed.
- Create a subdirectory only once there are enough documents of one kind to need one, not before.
- Do not create an empty directory, and do not create an index file for a directory unless something
  will actually read it as an index — an index nobody navigates to is ceremony, not documentation.
- A document's own frontmatter, if any, exists only for a concrete consumer (a status a lifecycle
  actually branches on, a date a reader actually needs). Do not add fields because a template had
  them.

## Invariants

These hold in every mode:

- **An ADR records a consequential, hard-to-reverse decision** — one with real alternatives, where a
  future reader will need to know why the chosen one won. It does not record a trivial or easily
  reversed choice; that is either not written down at all, or covered in a design doc's ordinary
  prose. See `references/adr.md` for the test.
- **Architecture docs are a map, not an inventory.** They describe boundaries, components and how
  data and control flow between them, and they point at the code for the rest. A doc that restates
  what a file already says clearly is duplicating a fact that will drift; link to the file instead.
- **Design docs are living.** Unlike an ADR, a design doc is expected to change as the design changes
  — update it in place rather than layering a second document over the first.
- **A stale doc is a defect, exactly like a stale comment.** When a change makes a document wrong,
  fixing the document is part of finishing that change, in the same commit or the same tightly
  coupled series — not a follow-up, and not a calendar-scheduled review some time later. Reviewing on
  a fixed schedule with no real change behind it is the ceremony this skill exists to avoid; a doc
  earns a look when the thing it describes changes, not when a date arrives.
- **Durable rationale lives in one place.** When the "why" belongs in a document, a comment or commit
  message links to it — it does not repeat it. Duplicating the same rationale into both means one of
  the two goes stale silently.

## Process

1. **Classify** the request against the table above and read the one reference it points to.
2. **Check what already exists.** Search for a document that already covers this system or decision
   before starting a new one — updating a stale section beats forking a duplicate.
3. **Write at the right altitude for the mode** — an ADR is short and decision-shaped, an architecture
   overview stays at the map level, a runbook is steps a reader can follow without owning the
   background, a reference doc is looked up rather than read start to end. `references/doc-types.md`
   sizes each one.
4. **Use the matching template** as a starting skeleton, not a form to fill in mechanically — cut any
   section the document genuinely does not need. `templates/adr.md` and `templates/design-doc.md`
   are under `templates/`.
5. **Land it with the change it documents**, when one exists, so the doc and the behavior it
   describes never ship out of sync.

## Audit mode, briefly

Audit is the highest-value mode because a wrong document actively misleads, where a missing one just
leaves a gap. It is not a read-through: find the docs, extract what each one claims, check every
claim against the current code and — for any documented command — by actually running it, then
classify each document as stale, wrong, duplicated, orphaned or fine. The full procedure and the
classification definitions are in `references/audit.md`; do not skip straight to writing a report
without doing the verification it describes.

## Not this skill

- **Explaining code or a decision in conversation**, with no lasting artifact asked for. Answer it in
  the reply; create or edit nothing. If the person also wants it written down, that part is this
  skill — the explanation itself is not.
- **Code comments and doc comments.** Those live at the call site, in the language's own convention,
  and are owned by whatever this repository uses for comment work — never this skill. A comment may
  *link* to a document this skill produced; it does not duplicate one.
- **Editing a persistent-instruction file (`AGENTS.md`, `CLAUDE.md`) or a skill.** Those tell an agent
  how to behave or carry a procedure; this skill records what is true about the project. If a task
  needs the former, say so and route there instead of writing a document that will not be read the
  same way.
- **Routine status updates, changelogs, or commit messages.** Those already have an owner and a
  format; this skill is for the kind of documentation meant to outlive a single change.

## Output contract

Report, whichever mode ran:

- Which document(s) were created or updated, at what path, and in which mode.
- For an ADR: the status it was given and, if it supersedes or is superseded by another, which one.
- For an audit: the documents examined, the claims checked, and the classification of each — not a
  bare pass/fail.
- Anything the request implied should exist but that this pass did not create, and why — usually
  because it belongs in a different layer (a persistent-instruction file, a skill, a code comment) or
  because the underlying decision was not actually consequential enough to record.

## References

- `references/doc-types.md` — architecture overview, design document, runbook and reference doc: what
  each is for, what belongs in it, and roughly how long it should run.
- `references/adr.md` — the test for whether a decision earns an ADR, its structure, and the status
  lifecycle, including how superseding one works.
- `references/audit.md` — the audit procedure and the stale / wrong / duplicated / orphaned / fine
  classification.

## Templates

- `templates/adr.md`
- `templates/design-doc.md`
