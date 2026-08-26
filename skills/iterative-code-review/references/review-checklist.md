# Code Review Checklist

> Sources: Google Engineering Practices, Clean Code (Robert C. Martin), SOLID Principles, Martin Fowler's Refactoring, SonarQube, Airbnb/Google Style Guides

## 1. Design & Architecture

| Rule | Severity | What to Check |
|------|----------|---------------|
| D-1 | Critical | Code well-designed and fits system architecture |
| D-2 | High | Code belongs in this codebase, not a library |
| D-3 | High | Integrates with existing patterns and conventions |
| D-4 | High | No over-engineering — solve today's problem only |
| D-5 | High | Prefer polymorphism over if/else type-checking chains |
| D-6 | High | Use dependency injection, not direct instantiation |
| D-7 | High | Law of Demeter — no `a.getB().getC().doThing()` chains |
| D-8 | Medium | Keep configurable data at high levels |

### SOLID Principles

| Principle | Violation Indicator |
|-----------|-------------------|
| **SRP** | Class handles multiple unrelated responsibilities |
| **OCP** | Adding a type requires modifying existing code |
| **LSP** | Subclass throws NotImplementedException or enforces stricter preconditions |
| **ISP** | Classes implement methods they don't use |
| **DIP** | High-level code directly depends on infrastructure details |

## 2. Complexity

| Metric | Threshold | Action |
|--------|-----------|--------|
| Cyclomatic complexity/function | >10 | Extract methods, use polymorphism |
| Cognitive complexity/function | >15 | Reduce nesting, simplify booleans |
| Function length | >40 lines | Extract smaller methods |
| Class length | >200 lines | Extract classes, apply SRP |
| Parameters | >3-4 | Introduce parameter object |
| Nesting depth | >3 levels | Early returns, extract methods |

## 3. Code Smells

### Bloaters
| Smell | Fix |
|-------|-----|
| Long Method (>40 lines) | Extract Method |
| Large Class | Extract Class/Subclass |
| Primitive Obsession (currency as float) | Value Objects |
| Long Parameter List (>4) | Parameter Object |
| Data Clumps (same vars passed together) | Extract class |

### OO Abusers
| Smell | Fix |
|-------|-----|
| Switch/type-checking statements | Polymorphism |
| Temporary fields | Separate class |
| Refused Bequest (unused inheritance) | Composition |

### Change Preventers
| Smell | Fix |
|-------|-----|
| Divergent Change (one class, many reasons) | Extract Class |
| Shotgun Surgery (one change, many files) | Move Method |

### Dispensables
| Smell | Fix |
|-------|-----|
| Dead code / commented-out code | Delete |
| Speculative Generality | Remove, build when needed |
| Duplicate code | Extract shared method/class |

### Couplers
| Smell | Fix |
|-------|-----|
| Feature Envy | Move method to envied class |
| Inappropriate Intimacy | Encapsulate |
| Message Chains | Hide Delegate |
| Middle Man | Remove |

## 4. Naming

Per-language casing lives in `naming-and-layout.md`. The rules below are the
language-independent core; that file is what makes them concrete for the language in front
of you. No formatter renames an identifier, so every rule here is reviewable in every
language.

| Rule | Severity |
|------|----------|
| Names descriptive and unambiguous | High |
| No `data1`, `data2` — meaningful distinctions | High |
| Replace magic numbers with named constants | High |
| Consistent vocabulary — one word per concept | High |
| Casing matches the language's own convention — see `naming-and-layout.md` | High where the language's own **creators** state it, Low where the rule is a corporate, project or community guide, or a house default |
| Acronyms cased the way the language specifies, not the way the last language did | Same ladder as casing above |
| Booleans read as predicates **in the language's own form**: `isEmpty`, `is_empty`, `empty?`, `isequal`, `IsEmpty` | Medium |
| Class = noun, Method = verb | Medium |
| No **data type** encoded in the name — no Hungarian notation (`strName`, `iCount`, `lpszBuffer`). Scope, backing-field and kind markers are fine wherever the language's own convention prescribes them: C# `_camelCase`/`s_`/`t_` and `IFoo`, C++ trailing `_` and `kMaxRetries`, Objective-C `_ivar`/`g`/`k` and its class prefix, Kotlin `_name`, Ruby and Lua `_` — see `naming-and-layout.md` | Medium |

## 5. Functions

| Rule | Severity |
|------|----------|
| Functions do ONE thing | Critical |
| No side effects | Critical |
| Prefer <3 arguments | High |
| No flag arguments (split into separate methods) | High |
| Command-Query Separation | Medium |
| Extract try/catch into own functions | Medium |

## 6. Error Handling

| Rule | Severity |
|------|----------|
| Never swallow exceptions (empty catch) | Critical |
| Catch specific exceptions, not base types | High |
| Never log AND throw same exception | High |
| Preserve original exception when wrapping | High |
| Error messages descriptive and actionable | High |
| No sensitive info in error messages | Critical |
| Use language cleanup constructs (using/try-with-resources) | Critical |
| Don't return null where empty collection works | High |

## 7. Performance & Resources

| Rule | Severity |
|------|----------|
| Resources properly closed/disposed | Critical |
| No unbounded caches or collections | Critical |
| DB connections returned to pool | Critical |
| No N+1 query patterns | High |
| Appropriate data structures for access pattern | High |
| Event handlers unsubscribed when done | High |

## 8. Concurrency

| Rule | Severity |
|------|----------|
| All shared mutable state protected | Critical |
| No race conditions in check-then-act | Critical |
| Consistent lock ordering (no deadlocks) | Critical |
| Don't call external methods while holding locks | Critical |
| Minimize critical section scope | High |
| Use proper sync, not Thread.sleep() | High |

## 9. Style & Consistency

Indentation and layout live in `naming-and-layout.md`, which also draws the line between a
layout defect that is a finding and one the formatter owns. Read it before filing anything
in this section — most layout belongs to the tool, and reporting it inflates the iteration
loop with work the formatter does for free.

Every rule here fires on something the diff introduced or changed. A property the file or
the repository already had is an INFO note, raised once, that does not block a clean pass.

| Rule | Severity |
|------|----------|
| Indentation that changes meaning or misleads — Python, YAML, Makefile recipes, CWE-483 | Critical |
| CRLF or a BOM the diff introduces into a file with a shebang, a Makefile recipe, or a strict LF-only parser | Critical |
| Indent character contradicts the language's rule, or tabs and spaces are mixed, in a file the diff adds or re-indents | High |
| Mixed line endings the diff introduces into a file | High |
| The same defects, **pre-existing** in a file the diff merely edits | **INFO**, once, non-blocking |
| A line-ending or encoding flip bundled into a behavior change — it rewrites every line | High |
| Follows project's established style | High |
| Style changes NOT mixed with logic changes | High |
| Consistent error handling patterns | High |
| A file in the diff is unformatted against the formatter config the project already has | Medium |
| Missing newline at end of file — POSIX leaves the file ending in an incomplete line | Medium, unless `insert_final_newline` owns it |
| Missing `.gitattributes`, formatter or linter config — a repository-state observation | **INFO**, once, non-blocking |
| Column counts, wrap points, trailing whitespace and alignment a configured formatter produced or would fix | **Not a finding** |

Comments and doc comments are checked separately — see section 12.

## 10. API Design

| Rule | Severity |
|------|----------|
| Public API backward compatible | Critical |
| Proper HTTP methods and status codes | High |
| All inputs validated at boundaries | Critical |
| Consistent error response format | High |
| No internal details exposed | High |

## 11. Anti-Patterns to Flag

| Pattern | Severity |
|---------|----------|
| God Class | Critical |
| Spaghetti Code | Critical |
| Premature Optimization | High |
| Copy-Paste Programming | High |
| Golden Hammer (one pattern for everything) | High |
| Lava Flow (dead code nobody removes) | High |

## 12. Comments & Documentation

Full checklist, including the size limits, the derived-language spot checks and the
do-not-flag list: `references/comment-checklist.md`.

| Rule | Severity |
|------|----------|
| Comment matches what the code actually does | Critical |
| Every stated rationale is traceable to code, commit, tests, tracker or spec | Critical |
| No credential, key, token, connection string or private key in a comment | Critical |
| Internal hostname, internal path, infrastructure detail or PII in a comment | High |
| A leaked secret is rotated and its history scrubbed, not merely deleted | Critical |
| Public API carries the contract a caller needs | High |
| Error, nullability, ownership, thread-safety and sentinel semantics documented | High |
| No commented-out code | High |
| Every annotation has an owner or a tracked reference | High |
| No comment restates the code | Medium |
| Comments within the size limits for their kind | Medium |
| No implementation detail inside an interface comment | Medium |
| No change history, bylines or time-anchored language | Medium |
| Language's own comment convention used, not a resembling language's | Medium |
| Comment sits above the code it describes, correctly indented | Low |

Two failure directions, both defects: a public API with no contract, and noise that
restates the code. The cure for one is never the other.
