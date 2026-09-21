# What a good instruction file contains

Sections in order of priority. Include each one unless that section's own test says to omit it —
an empty heading kept "just in case" is worse than no heading, because it invites someone to fill
it with whatever's lying around instead of asking whether it belongs there at all.

## 1. Project overview (one to three sentences)

What the project does, who it's for, and the tech stack with pinned versions. The versions are the
part actually worth writing down — deriving them means opening manifests and reconciling several of
them, which is exactly the kind of repeated lookup this file exists to save. If the sentences just
restate the README's opening paragraph, cut them and point at the README instead.

## 2. Commands

Exact build, test, lint and single-test commands, each one run and confirmed per the verification
rule in `SKILL.md`, with flags included. Put this section early — it gets referenced on nearly every
task. The single-test entry earns its place in any language: running one test instead of the whole
suite is the hardest invocation to guess correctly and the one most often needed.

```markdown
## Commands
- Build: `make build`
- Test: `go test ./...`
- Single test: `go test ./billing -run TestReconcile`
- Lint: `golangci-lint run` (add `--fix` to apply)
- Dev server: `make dev` (long-running; not run during verification)
```

## 3. Code conventions (non-obvious only)

Only what differs from the framework's own defaults, or what the agent genuinely can't infer from
reading existing code. Write the rule, not the idiom — a convention that only makes sense inside one
language usually belongs in that language's linter config instead of prose here.

```markdown
## Conventions
- Errors carry a stable `code` field; callers switch on it, never on message text
- Time values are UTC at every boundary; convert only for display
- Public API changes require a version bump in `api/VERSION`
```

## 4. Project structure (only what navigation can't infer)

Include a directory only when one of these holds — and if none do, omit the section entirely rather
than leaving a thin, low-value listing:

- Its name does not predict its contents.
- A boundary between two similar-looking directories is load-bearing (which one a change belongs
  in actually matters).
- Editing it by hand would be wrong — generated code, vendored dependencies, anything a build step
  owns. Name these explicitly; "don't hand-edit this" is exactly the kind of rule an agent can't
  recover by reading the directory, because the generated file looks like ordinary source until you
  try to keep an edit to it.

```markdown
## Structure
- `domain/` — Business rules. No framework or transport imports allowed here.
- `adapters/` — Everything that touches the network or disk.
- `proto/generated/` — Protobuf output. Regenerate with `make proto`; never hand-edit.
```

A conventional `src/` and `tests/` layout earns nothing here — spend lines only where they shorten
the path to the right file.

## 5. Testing approach

Omit unless something about it is genuinely non-obvious: a suite that needs a fixture server or a
seeded database, tests that don't live where the language conventionally puts them, a runner other
than the ecosystem's usual one, or a required flag the suite misbehaves without. Framework choice
and file naming an agent gets from scanning a couple of existing tests do not need a section.

## 6. Boundaries

Always include this one, even when short. Name security-sensitive areas explicitly rather than
leaving them to be inferred — a file that documents build commands in detail and says nothing about
what's off-limits is telling an agent, by omission, that nothing is.

```markdown
## Boundaries
- **Always**: Run the Test command above before committing
- **Ask first**: Database schema changes, dependency additions
- **Never**: Commit secrets, hand-edit `proto/generated/`, force push to main
- **Security-sensitive**: `domain/auth/` and `domain/billing/` — never log request bodies; token
  handling changes need human review
```

## Optional sections

Include only if the repository genuinely needs them, and each is held to the same placement test as
everything else:

- Domain terminology — jargon definitions the code doesn't self-document.
- Common workflows — step-by-step for a task that recurs but isn't a single command.
- Environment setup quirks — the one non-obvious step a fresh checkout needs.
- Commit and PR conventions — only where no other file in the repository already states them.

## What not to write

| Exclude | Why |
|---|---|
| Anything derivable from reading the code | Costs tokens to state, and the agent gets there anyway |
| Content already in the README, CONTRIBUTING, or `docs/` | Restating it adds cost without adding anything the source didn't already say, and the copy is what goes stale |
| Standard language or framework conventions | The agent already knows these |
| Detailed API documentation | Link to it instead of inlining it |
| Frequently changing data (current sprint, contributor list, in-flight status) | Goes stale fast and poisons trust in the rest of the file |
| Vague principles ("write clean code", "follow best practices") | Not actionable, and gets silently ignored because there's nothing to check it against |
| File-by-file descriptions | The agent discovers structure through its own tools |
| Rules a linter, formatter or type checker already enforces | The tool never drifts and never needs re-reading; a model re-deriving what a tool already guarantees is pure waste |
| Secrets or credentials | Security risk, and out of place in a file meant to be read by every session |
| Contradicting instructions, whether within the file or against another instruction file | The agent resolves the conflict arbitrarily, which is worse than omitting either rule |

## Writing style

- **Specific and verifiable.** "New endpoints must be registered in `routes/index` — the router
  does not autodiscover" carries information; "wire up new endpoints properly" doesn't.
- **Actionable.** The agent can follow it without interpreting what it might mean.
- **Non-obvious.** Only what the agent wouldn't already do by default.
- **State the reasoning where it changes behavior at the edges.** "Run tests through the project's
  task runner, not the test binary directly, because it sets required env vars" — the why helps an
  agent recognize when the rule doesn't apply.
- **One example beats three paragraphs** of description trying to convey the same shape.
- **Most important rules first** — an agent working under a token budget reads the top of the file
  more reliably than the bottom.
- Shouting a rule in capitals or repeating MUST/NEVER does not make it more binding than stating it
  once, plainly, as a concrete and verifiable instruction. A rule that needs volume to be obeyed is
  usually a rule that isn't specific enough to be obeyed on its own merits — fix the specificity,
  not the emphasis.

## Nested files

Write a nested file only for a subtree whose conventions genuinely differ from the root — never to
break a long file into shorter pieces that all describe the same scope. Each one has to hold up on
its own:

- **Self-contained for its subtree.** It must make sense as the only file an agent working there
  ever reads. Different harnesses combine nested files differently — nearest-wins in one, root-to-cwd
  concatenation with closer files overriding in another — so depending on a particular merge order
  is not reliable.
- **Never contradicts the root.** A nested file narrows or adds; it never reverses a root rule for
  its subtree. A rule that's wrong for one subtree belongs at the level where it's actually true,
  not overridden downward.
- **The root holds only what's true everywhere.** Anything true of one subproject and not another
  moves down to that subproject's own file rather than staying at the root with an implicit
  exception nobody wrote down.

Nested files are not free to add without limit. At least one harness this repository targets caps
the whole concatenated chain at a fixed byte budget and drops whatever doesn't fit — typically the
deepest, most specific file — without an error, so keep every file in a chain short, not only the
root.

## Worked examples

The sections above are the reasoning; these are finished files that apply it. Read one when you
want to see how much detail a real file carries at a given scope, then write for your own
repository rather than adapting theirs.

- [`examples/global-agents.md`](../../../examples/global-agents.md)
  — user-scope working agreement. Note how every machine-, harness- and vendor-specific rule is
  parameterized rather than stated literally, and how model selection is expressed as tiers,
  because vendor model names change faster than an instruction file should.
- [`examples/project-agents.md`](../../../examples/project-agents.md)
  — repository-level file. Note what it leaves out: no generic engineering doctrine, no framework
  conventions, no file-by-file tour. It is roughly a fifth the size of the global file, and links
  out to the architecture docs instead of summarizing them.
- [`examples/nested-agents.md`](../../../examples/nested-agents.md)
  — subtree file for a directory whose toolchain, command set and safety boundary genuinely
  differ. The test it passes: every rule in it would be false or harmful if applied to the
  repository root, which is what separates a warranted nested file from pagination.

They are named `*-agents.md`, not `AGENTS.md`, so that an agent working in that directory does not
load an example as its own scoped instructions.
