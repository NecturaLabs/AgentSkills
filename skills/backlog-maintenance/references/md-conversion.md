# Converting a file backlog into issues

Applies to any file that tracks work: `TODO.md`, `BACKLOG.md`, `ROADMAP.md`, task lists in
`docs/`, handoff notes' open items, and task checklists in README files. Decisions, designs and
reference prose are not backlog items; leave them in their docs.

1. **Inventory.** Find the files (search the repository for backlog-like names and for unchecked
   checklist items). List every item with its file and line, and its done or open state.
2. **Classify.** Drop items that are done (check the code or history) and record them as closed
   history in the conversion report only. Group items that are one piece of work; split items that
   bundle independent work.
3. **File.** For each open item or group, search existing issues, then file one issue to
   `issue-standards.md` with type, area, priority and size. Carry over every requirement,
   constraint, link and piece of evidence from the source. Do not invent acceptance criteria that
   the source does not support: derive checkable ones from its stated outcome and mark any
   guesswork for the owner under a short *Assumptions* line.
4. **Record where each item went.** Keep a mapping from file line to issue number while working.
5. **Retire the file.** Once every open item is an issue and the mapping is complete, replace the
   file's contents with a short pointer to the issue list (or delete the file when nothing
   references it), in the same change, and fix every link that pointed at it. Never leave a
   half-converted file: a file either still holds the open items or points to the issues.
6. **Report.** The number filed and skipped as done, the mapping, and anything ambiguous that
   needs the owner.

Never convert in bulk without reading each item: a Markdown line is often a symptom or a wish, and
an issue must say what is wrong or what must exist.
