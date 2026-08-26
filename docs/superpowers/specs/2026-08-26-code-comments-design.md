# Code Comments Skill — Design

**Status:** approved 2026-08-26, implemented. Kept as the design record.
**Plan:** `docs/superpowers/plans/2026-08-26-comment-manager.md`

> The file list below names `tests/skill-triggering/prompts/comment-manager.txt`, which
> no longer exists: that suite was deleted because it could never run without credentials
> this repo does not hold. A third reference, `trap-examples.md`, was added afterwards.

## 1. Problem

The repo has no rule set governing how comments get written. `iterative-code-review`
carries three thin lines about comments inside its Style section, and
`iterative-security-audit` says nothing about comments at all — so a credential or an
internal hostname left in a comment passes both loops. Meanwhile agents, left to their own
defaults, generate comments prolifically and restate the code.

Two failure modes, opposite in direction, both currently unguarded:

- **Under-documented** — a public API with no contract, an unsafe block with no stated
  invariant, a sentinel value nobody can decode.
- **Over-commented** — noise that restates the code, change journals, bylines, banners,
  commented-out code, and doc blocks mandated per-construct rather than earned.

A third, worse than either: a comment that is *wrong*. Empirical work on 1,500 systems
(Wen et al., ICPC 2019) finds code and comments co-evolve in roughly 90% of cases but are
redocumented only in later revisions, and that inconsistent changes are ~1.5× more likely
to be bug-introducing than consistent ones. For an agent the cost is higher still: an
agent treats a comment as authoritative context it cannot cheaply falsify.

## 2. Goal

One skill that governs comment authoring across every language, enforced inside both
existing review loops, deriving its rules from published authoritative sources rather than
taste.

## 3. Research base

~35 primary sources. Full citations in `skills/comment-manager/references/comment-rules.md`
and `references/language-matrix.md`. Summary of what they establish:

**Universal — asserted by every source consulted:**

| Principle | Representative source |
|---|---|
| A comment carries what the code cannot | Ousterhout: *"Comments should describe things that are not obvious from the code."* |
| Do not state the obvious | Google C++ *Don'ts*; Clean Code ch. 4 (Redundant, Noise) |
| Unclear code is fixed, not annotated | Google eng-practices: *"If the code isn't clear enough to explain itself, then the code should be made simpler."*; tidyverse; Linux ch. 8; Epic |
| Interface and implementation comments are separate | Go: *"Doc comments should not explain internal details."*; Elixir docs-vs-comments; Ousterhout red flag |
| Public API is documented; obvious members are not | Google Java, Swift, Google JS, Kotlin, Dart, Rust |
| Summary is one sentence, first, standalone | Javadoc, PEP 257, Go, rustdoc, Swift, Dart, Elixir, Scaladoc |
| History and authorship belong to version control | Clean Code (Journal, Attributions); Google C++ author lines; Google timeless-documentation |
| Stale comments are defects | Ruby guide; Epic (*"Never contradict the code"*); ICPC 2019 |

**Divergent — must be resolved per language, not globally:**

| Axis | Spread |
|---|---|
| Summary mood | imperative (PEP 257, Julia) · descriptive (Google C++, Objective-C) · name-first sentence (Go) · "Returns XXX" (Scaladoc) · sentence *fragment* (Swift, Google Java) · third-person verb (Dart) |
| Comment prose width | 72 (Python) · 80 (C, C++, Shell, Ruby, Rust, JS/TS, Lua, Dart, R) · 92 (Julia) · 98 (Elixir) · 100 (Java, Kotlin, Swift, Obj-C, GDScript) · none (Go) |
| Tag policy | required (Java, Scala, Swift, PowerShell, C#) · prose-preferred (Kotlin, Dart) · none exist (Go) |
| Comment support | absent entirely (JSON) · present but not the documentation mechanism (GraphQL, Terraform) |

A single global rule gets several of these wrong. Hence the core/matrix split.

## 4. Decisions

**D1 — One skill, three modes.** `necturalabs:comment-manager`, modes Author / Audit / Fix.
Author fires on any code written or changed; Audit and Fix serve the review loops and
manual invocation.

**D2 — Language-neutral core + explicit per-language matrix.** The core binds everywhere.
The matrix carries only genuine divergences, each with its source named. Where no
authoritative convention exists for a language, the matrix says so rather than inventing
one, and the fallback rule applies.

**D3 — Comments are opt-in, not default.** A three-part admission test (§5) gates every
comment. Rejected by the sources' own logic: per-construct mandates, density targets, and
comment-to-code ratios.

**D4 — Closed content lists.** A doc comment and an implementation comment each have an
enumerated set of admissible contents, plus a ban list. Anything outside is a finding. This
is what stops narrative, history and hedging from accumulating.

**D5 — Enforced in both loops.** Comment defects are ordinary blocking findings in
`iterative-code-review` under the existing no-deferral rule. Comment-borne information
disclosure is a first-class category in `iterative-security-audit` with its own trigger, so
the audit fires when comments are touched — not only when auth or crypto is.

**D6 — Duplication guarded, not avoided.** The authoring canon lives in `comment-manager`;
the review-side checklist lives in `iterative-code-review` (a dispatched reviewer subagent
can only resolve absolute paths under the skill that dispatched it). A phrase validator plus
a mutation guard keep the shared rules identical, matching the `house-rules.md` /
`testing-rules.md` pattern this repo already has evidence it needs.

**D7 — Project configuration wins.** Precedence: project formatter config
(`.editorconfig`, `rustfmt.toml`, `.prettierrc`, checkstyle, ruff) → language matrix →
universal core. The skill never reformats comments a project's formatter owns.

## 5. Admission test

All three must pass, in order, before a comment is written:

1. **Necessity** — name the specific thing a competent reader of this language cannot
   recover from the code in ~30 seconds. Cannot name it → do not write it.
2. **Irreducibility** — could clearer code remove the need (rename, extract, named
   constant, enum over bool, options object)? If yes, change the code. Google C++ lists
   exactly these remedies *before* reaching for a comment.
3. **Durability** — will this still be true and still useful after the next reasonable
   change? If it describes momentary state, it is a tracked annotation or it is nothing.

Standing exception, itself gated: public API surface where the language's own guide
requires a doc comment. The published carve-outs still apply — obvious accessors,
overrides, self-evident enum cases.

## 6. Content lists

**Doc (interface) comment — admissible content, exhaustive:** summary · parameter meaning
where name and type don't carry it (units, ranges, encoding, nullability, ownership) ·
return and output semantics including sentinel values · errors, exceptions, panics and
their conditions · pre/postconditions, invariants, call-order restrictions · thread-safety
and synchronization assumptions · lifetime, ownership and resource obligations · complexity
or performance where it constrains use · safety obligations for unsafe operations · a
minimal example where the API is not obvious.

**Implementation comment — admissible content, exhaustive:** why this approach over the
obvious alternative · the non-obvious invariant relied on · a citation (spec, RFC,
algorithm, standard, bug) · a hazard (required ordering, held lock, workaround for an
external defect) · a step overview for a genuinely intricate block.

**Banned:** restating the code · change history and journals · bylines and attributions ·
time-anchored language · commented-out code · banners, position markers, ASCII boxes ·
closing-brace labels · mandated boilerplate on obvious members · implementation detail
inside an interface comment · non-local information · repeating a supertype's doc on an
override · speculation and hedging · apologies, jokes, narration · annotations with no
owner or tracked reference · secrets, keys, internal hostnames, PII, exploit detail ·
directives addressed to whoever reads the file rather than facts about the code.

The last is agent-specific and deliberate: a comment states facts about the code; it never
instructs its reader.

## 7. Size limits

| Kind | Width | Size |
|---|---|---|
| Trailing / side | fits on the code's own line within the limit; ≥2 spaces of separation | one clause; never wraps — if it does not fit it becomes a block comment above |
| Block (implementation) | comment prose width | one paragraph; target ≤3 sentences, ceiling 7 lines |
| Doc summary | one physical line within the limit | exactly one sentence or fragment |
| Doc body | comment prose width | one paragraph per topic, each ≤7 lines; one sentence per tag description |
| File / module header | comment prose width | 1–3 sentences |

**Provenance, stated honestly.** Widths are verbatim from each language's own guide and are
hard rules. The 7-line paragraph ceiling is Microsoft's Writing Style Guide — *"Three to
seven lines is about the right length for a paragraph"* — and the ≤3-sentence target is
Google's documentation style guide (*"1–3 sentences"*); both are prose-writing guidance
applied to comment bodies, which is a synthesis and is labelled as such wherever it appears.

Breaching the ceiling is a **design signal, not a formatting nit**. Linux ch. 8 (a function
needing heavy in-body commentary should be split) and Ousterhout (extensive documentation is
a red flag about the design) both point the same way: split the function, or move the
material to a doc comment or an ADR and cite it. Never wrap the paragraph and move on.

**No density target.** No minimum comment count, no comment-to-code ratio, in either
direction.

## 8. Review-loop integration

`iterative-code-review`:
- Comments joins the checklist summary table as its own category.
- `references/comment-checklist.md` becomes a third literal absolute path in the dispatch
  table, so the reviewer subagent actually receives the rules.
- Severity ladder — CRITICAL: comment contradicts the code, or leaks sensitive information.
  HIGH: missing doc on public API; missing error / nullability / ownership / thread-safety
  contract; commented-out code; untracked annotation. MEDIUM: restates the code;
  over-length; implementation detail in an interface comment; journal, byline or
  time-anchored language; wrong placement. LOW: punctuation, format, decorative boxes.
- Findings bind under the existing no-deferral rule.

`iterative-security-audit`:
- New category *Comment-Borne Disclosure*, covering CWE-615 (sensitive information in source
  code comments), CWE-540 (sensitive information in source code), CWE-546 (suspicious
  comment), and the OWASP SCP requirement to remove comments in user-accessible production
  code that reveal backend or other sensitive information.
- The skill's trigger list gains comments, so a change that only touches comments still
  routes through the audit.

Also updated: `using-necturalabs` skills table and decision flow, `README.md`, `AGENTS.md`
gate line, and a minor version bump across the four config files.

## 9. Files

```
skills/comment-manager/SKILL.md                        # modes, gates, dispatch
skills/comment-manager/references/comment-rules.md     # universal core (canon)
skills/comment-manager/references/language-matrix.md   # per-language deltas + sources
skills/iterative-code-review/references/comment-checklist.md
tests/validate-comment-rules.sh                        # cross-copy phrase check
tests/comment-rules-guard.sh                           # mutation guard for the validator
tests/skill-triggering/prompts/comment-manager.txt
```

## 10. Non-goals

- Not a linter. The skill does not replace `clippy`, `ruff`, `checkstyle` or `eslint`; where
  a project's tooling already enforces a rule, the tooling wins.
- Not a documentation generator. Prose docs, ADRs and guides remain `docs-manager`'s.
- No reformatting of comments a project's formatter owns.
- No coverage claim for languages without a published convention — those get the fallback
  rule and the matrix says so.
