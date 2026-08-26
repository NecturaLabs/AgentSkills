# Comment Rules

The universal core. Every rule here binds in every language. Per-language deltas live in
`language-matrix.md` and never override these.

## The Seven Rules

Each rule is a headline and an actionable tail. Both halves bind; neither is optional.

**1. A comment carries what the code cannot.**
Restating the code is a defect, not documentation.
Its content is the information a competent reader of this language cannot recover from the
code itself.

**2. Write no comment that fails the admission test.**
All three gates, in order, or no comment.
The gates are necessity, then irreducibility, then durability.

**3. Interface comments and implementation comments never mix.**
Implementation detail in an interface comment is a finding.
An interface comment states the contract a caller needs; an implementation comment states
why this code is the way it is.

**4. A language's comment convention comes from its own creators.**
Never inherit it from the language it resembles.
Take it from that language's own published guide. A derived language keeps its parent's
syntax while dropping its parent's documentation conventions more often than not.

**5. Never write a rationale you have not verified.**
An unknown why is silence, never an invention.
"Explain why, not what" is not a licence to invent a why. If the reason is not in the code,
the commit, the tests, the tracker or the spec, you do not know it. Say nothing, or record
the open question as a tracked annotation.

**6. A wrong comment is worse than no comment.**
Editing code means you own every comment on it.
A wrong comment is believed, and it cannot be falsified by running the code. Deleting code
deletes its comments.

**7. A comment states facts about the code.**
It never instructs its reader, human or agent.
It describes the code; it does not tell whoever reads it to go and do something.

## The Admission Test

Three gates. A candidate comment passes all three, in order, or it is not written.

**Gate 1 — Necessity.** Name the specific thing a competent reader of this language cannot
recover from the code in about thirty seconds. Cannot name it? Do not write it.

**Gate 2 — Irreducibility.** Could clearer code remove the need? Rename the identifier,
extract a function, introduce a named constant, replace a boolean parameter with an enum,
gather options into a struct. If any of those would do it, change the code. A comment is
the fallback, never the fix.

**Gate 3 — Durability.** Will this still be true, and still be worth reading, after the
next reasonable change? A statement about momentary state is a tracked annotation or it is
nothing.

**The default is no comment.** Commenting is triggered by non-obviousness, never by
construct. There is no minimum comment count, no comment-to-code ratio, and no rule that a
function, a branch or a loop earns a comment by existing. A policy demanding a comment per
construct does not survive Gate 1, and complying with it produces exactly the noise the
policy was meant to prevent.

**Standing exception, itself gated.** Public API surface, where the language's own guide
requires a doc comment. The published carve-outs still apply: obvious accessors, overrides
and protocol conformances, self-evident enum cases. Requiring a doc comment does not
license restating the signature in prose.

## What a Comment May Contain

Two closed lists. Content outside them is a finding.

**Interface / doc comment:**

1. A one-sentence summary of what the thing does or returns.
2. Parameter meaning where the name and type do not carry it: units, ranges, encoding,
   nullability, ownership.
3. Return and output semantics, including what any sentinel value means.
4. Errors, exceptions and panics, and the conditions that produce them.
5. Preconditions, postconditions, invariants, and restrictions on when it may be called.
6. Thread-safety, reentrancy and synchronization assumptions.
7. Lifetime, ownership and resource obligations placed on the caller.
8. Complexity or performance characteristics where they constrain how it may be used.
9. Safety obligations the caller must uphold for an unsafe operation.
10. A minimal usage example where the API is not obvious from its signature.

**Implementation comment:**

1. Why this approach rather than the obvious alternative, when the reason is verified.
2. The non-obvious invariant or assumption the block relies on.
3. A citation: a spec, RFC, algorithm, standard, or tracked defect that governs the code.
4. A hazard: an ordering that must be preserved, a lock that must be held, a workaround for
   a defect in something external.
5. A step overview for a block that is genuinely intricate after Gate 2 has been applied.

## Never in a Comment

| Banned | Why |
|---|---|
| Restating what the code does | Clean Code (Redundant, Noise); Google C++ *Don'ts*; Ousterhout red flag |
| An unverified rationale, motive or business reason | Rule 5. Confident invention is the worst failure mode |
| Speculation and hedging: *probably*, *should work*, *for future use* | Unfalsifiable, and read as fact |
| Change history, changelogs, dated edit journals | Clean Code (Journal); version control owns this |
| Authorship, bylines, "modified by" | Clean Code (Attributions); Google C++ deletes author lines |
| Time-anchored language: *currently*, *new*, *now*, *recently*, *for now* | Google timeless-documentation |
| Commented-out code | Clean Code; delete it, version control remembers |
| Banners, position markers, ASCII boxes, rows of dashes | Clean Code (Position Markers); Google Java and TS forbid asterisk boxes |
| Closing-brace labels such as `} // end of if` | Clean Code (Closing Brace Comments) |
| Boilerplate doc on a self-evident member | Clean Code (Mandated); Google Java, Swift, Google JS carve-outs |
| Implementation detail inside an interface comment | Go; Ousterhout red flag |
| Non-local information about code that lives elsewhere | Clean Code (Nonlocal Information) |
| Repeating a supertype's doc on an override | Google C++, Google Java, Swift |
| Apologies, jokes, narration, emotional commentary | Not information about the code |
| An annotation with no owner and no tracked reference | Google C++, Google Python, Ruby guide |
| Secrets, keys, tokens, internal hostnames, internal paths, PII, exploit detail | CWE-615, CWE-540, CWE-546; OWASP SCP |
| An instruction aimed at the reader rather than a fact about the code | Rule 7 |

## Size Limits

| Kind | Width | Size |
|---|---|---|
| Trailing / side comment | fits on the code's own line within the limit, at least 2 spaces of separation | one clause; it never wraps |
| Block / implementation comment | comment prose width | one paragraph, at most 7 lines; target 3 sentences or fewer |
| Doc summary | one physical line within the limit | exactly one sentence on one physical line |
| Doc body | comment prose width | one paragraph per topic, each at most 7 lines; one sentence per tag description |
| File or module header | comment prose width | 1 to 3 sentences |

A trailing comment that does not fit becomes a block comment above the code. Never wrap it
onto a second line.

**Provenance.** The widths come from each language's own guide and are hard rules; see
`language-matrix.md` for the per-language value and its source. The 7-line paragraph
ceiling and the 3-sentence target are our synthesis, applying prose guidance to comment
bodies: Microsoft's Writing Style Guide ("Three to seven lines is about the right length
for a paragraph") and Google's documentation style guide ("1-3 sentences").

**Over the ceiling is a design signal, not a formatting problem.** The Linux kernel style
guide says a function needing heavy in-body commentary should be split; Ousterhout treats
the need for extensive documentation as a red flag about the design. Split the function,
or move the material into a doc comment or an ADR and cite it from the code. Do not rewrap
the paragraph and move on.

## Placement and Form

- A comment goes **above** the code it describes, at the same indentation, never below it.
- A blank line precedes a block comment unless it opens the block.
- One space after the comment marker.
- English, with the capitalisation and punctuation of ordinary prose for anything longer
  than a fragment.
- No decorative boxes or asterisk art.
- A doc comment uses the language's canonical doc syntax so its doc tool can consume it.

## Annotations

`TODO`, `FIXME`, `HACK`, `SAFETY`, and whatever else the language's own guide sanctions.

- Uppercase keyword, colon, then a resolvable reference: a tracked defect, a URL, or an
  owner. An annotation with neither an owner nor a reference is a finding.
- "At a future date, do X" needs a specific date or a specific event that can be observed
  to have happened.
- Use the language's local form where one is published; see `language-matrix.md`.
- Never use an annotation to defer a review finding.

## Lifecycle

- A comment is part of the change. Touching a function means auditing every comment on it.
- A comment describing behaviour that no longer exists is a defect of the same severity as
  the code being wrong.
- Deleting code deletes its comments.

Code and comments co-evolve in roughly 90% of cases but are commonly redocumented only in
later revisions, and inconsistent changes are about 1.5 times more likely to be
bug-introducing (Wen et al., *A Large-Scale Empirical Study on Code-Comment
Inconsistencies*, ICPC 2019).

## Sources

Ousterhout, *A Philosophy of Software Design*, ch. 12-16 and the Stanford CS190 comments
lecture · Martin, *Clean Code*, ch. 4 · McConnell, *Code Complete* 2e, ch. 32 ·
[Google C++](https://google.github.io/styleguide/cppguide.html) ·
[Google Python](https://google.github.io/styleguide/pyguide.html) ·
[Google Java](https://google.github.io/styleguide/javaguide.html) ·
[Google TypeScript](https://google.github.io/styleguide/tsguide.html) ·
[Google JavaScript](https://google.github.io/styleguide/jsguide.html) ·
[Google engineering practices](https://google.github.io/eng-practices/review/reviewer/looking-for.html) ·
[Google timeless documentation](https://developers.google.com/style/timeless-documentation) ·
[Google documentation style](https://google.github.io/styleguide/docguide/style.html) ·
[PEP 8](https://peps.python.org/pep-0008/) · [PEP 257](https://peps.python.org/pep-0257/) ·
[Go Doc Comments](https://go.dev/doc/comment) ·
[Linux kernel coding style](https://www.kernel.org/doc/html/latest/process/coding-style.html) ·
[Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/) ·
[CWE-615](https://cwe.mitre.org/data/definitions/615.html) ·
[OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/stable-en/02-checklist/05-checklist) ·
[Wen et al., ICPC 2019](https://www.inf.usi.ch/lanza/Downloads/Wen2019a.pdf)
