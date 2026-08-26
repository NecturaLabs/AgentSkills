# Comment Review Checklist

Review-side counterpart to `necturalabs:comment-manager`. That skill governs how a comment
is written; this governs how a bad one is found. The rules below are carried verbatim from
`skills/comment-manager/references/comment-rules.md` and are kept identical by
`tests/validate-comment-rules.sh`.

## The Seven Rules

Each rule is a headline and an actionable tail. Both halves bind; neither is optional.

**1. A comment carries what the code cannot.**
Restating the code is a defect, not documentation.

**2. Write no comment that fails the admission test.**
All three gates, in order, or no comment.

**3. Interface comments and implementation comments never mix.**
Implementation detail in an interface comment is a finding.

**4. A language's comment convention comes from its own creators.**
Never inherit it from the language it resembles.

**5. Never write a rationale you have not verified.**
An unknown why is silence, never an invention.

**6. A wrong comment is worse than no comment.**
Editing code means you own every comment on it.

**7. A comment states facts about the code.**
It never instructs its reader, human or agent.

## How to Review a Comment

For every comment in the diff, in this order:

1. **Is it true?** Compare it against the code beneath it. A comment that describes
   behaviour the code no longer has is CRITICAL, regardless of how it reads.
2. **Is its claim sourced?** A stated motive, business reason or historical rationale must
   be traceable to the code, the commit, the tests, the tracker or a spec. An assertion the
   author could not have known is CRITICAL — invented rationale is believed and cannot be
   falsified by running the code.
3. **Does it leak?** Secrets, keys, tokens, internal hostnames, internal paths, PII or
   exploit detail in a comment is CRITICAL. See `iterative-security-audit` for the full
   category.
4. **Does it say anything the code does not?** If it paraphrases the line beneath it, it is
   a MEDIUM finding. Being accurate does not save it.
5. **Is it in the right kind of comment?** A walkthrough of the body inside a doc comment
   is implementation detail contaminating an interface.
6. **Does it use this language's conventions?** Check the derived-language traps below.
7. **Is it within the size limits?**
8. **Does the public API surface it touches have the contract a caller needs?** Missing
   error, nullability, ownership, thread-safety or sentinel semantics is HIGH.

## Size Limits

| Kind | Width | Size |
|---|---|---|
| Trailing / side comment | fits on the code's own line within the limit, at least 2 spaces of separation | one clause; it never wraps |
| Block / implementation comment | comment prose width | one paragraph, at most 7 lines; target 3 sentences or fewer |
| Doc summary | one physical line within the limit | exactly one sentence on one physical line |
| Doc body | comment prose width | one paragraph per topic, each at most 7 lines; one sentence per tag description |
| File or module header | comment prose width | 1 to 3 sentences |

Comment prose width is the project's configured value; failing that, the language's own
value from `skills/comment-manager/references/language-matrix.md`. Python is 72 even where
code is allowed 99; Rust is 80 while code is 100; Lua is 80 while code is 100; Go sets none.

Over the ceiling is a design signal, not a formatting nit. Ask for the function to be split
or the material moved to a doc comment or an ADR — not for the paragraph to be rewrapped.

## Severity Mapping

| Severity | Finding |
|---|---|
| CRITICAL | Comment contradicts the code · unverified rationale asserted as fact · secret, key, token, internal hostname, internal path or PII in a comment |
| HIGH | Missing doc on public API · missing error, nullability, ownership, thread-safety or sentinel contract · commented-out code · annotation with no owner and no tracked reference |
| MEDIUM | Restates the code · over the size limit · implementation detail in an interface comment · journal, byline or time-anchored language · wrong placement · wrong language convention |
| LOW | Punctuation, grammar, spacing, decorative boxes |

## Derived-Language Spot Checks

The most common convention error is reaching for the doc syntax of the language this one
resembles. Full table in `skills/comment-manager/references/language-matrix.md`.

| If the diff is | Flag | Correct form |
|---|---|---|
| GDScript | a `"""docstring"""`, or `#` where docs belong | `##` above the member; `[param x]`, `@tutorial:` |
| TypeScript | `@param {string}` restating a type; `@override`, `@implements`, `@private` | prose only; types come from the type system |
| Swift | a `/** */` doc block | `///` only; summary is a sentence fragment |
| Dart | a `/** */` doc block, or `@param` tags | `///` only; parameters in prose with `[brackets]` |
| Kotlin | `@param`/`@return` on everything | prose with `[name]` links |
| C# | `/** */` with `@param` | `///` XML: `<summary>`, `<param name="">`, `<returns>` |
| Go | a doc comment not starting with the item's name, or any tag | `// Encode writes …`; no tags exist |
| Rust | `//!` used for the following item; `unsafe fn` with no `# Safety` | `///` for the next item, `//!` for the enclosing one |
| Elixir | `@doc` on a private function; `#` used as the API contract | `@doc` is the contract, `#` is for source readers |
| Julia | a docstring inside the function body | `"""` above the object, imperative mood |
| PowerShell | a plain `#` prose header | `<# .SYNOPSIS … #>`, contiguous, in a legal position |
| Terraform | a comment where a `description` belongs; `//` or `/* */` | `#` only; `description` on every variable and output |
| GraphQL | `#` used as documentation | `"""` descriptions — `#` is dropped by the type system |
| JSON | any comment at all | none exists; the note goes in a sibling doc or a schema `description` |

## Do Not Flag

False positives cost more than they save. These are not findings:

- A comment that states units, ranges, nullability, ownership or a sentinel meaning the
  type cannot express — that is exactly what a comment is for.
- A licence or copyright header required by the project.
- A pragma, directive or tool marker parsed by a compiler or linter: `# syntax=`,
  `// eslint-disable-next-line`, `# type:`, `//go:build`, `# noqa`, `#region`.
- A commented-out line inside a documented example block.
- An annotation that does carry an owner or a tracked reference, even if it is old — that
  is a backlog question, not a comment defect.
- Wrapping that the project's own formatter produced.
